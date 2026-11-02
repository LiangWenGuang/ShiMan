/**
 * 规则执行引擎：把 SourceRule 变成真正的数据。
 *
 * 这里只做「解析」，不做网络请求 —— 网络在 net/Http，两者解耦，
 * 便于在没有设备的情况下用纯逻辑测试解析正确性。
 */

import { HtmlNode, HtmlDocument, parseHtml } from './Html.ts';
import { queryAll, queryOne, matches } from './Selector.ts';
import { JsonNode, JsonKind, parseJson, selectPath } from './Json.ts';
import { resolveUrl, decodeEntities, compact, extractNumericId, applyTemplate, toHttps } from './Text.ts';
import { ComicBrief, ChapterBrief, PageImage } from './Models.ts';
import { SourceRule, HeaderPair } from './Rules.ts';
import { cryptoFramework } from './kitshim.ts';
import { buffer } from './kitshim.ts';
import { util } from './kitshim.ts';

/** 模板变量表 */
export class UrlVars {
  private values: Map<string, string> = new Map<string, string>();

  set(key: string, value: string): UrlVars {
    this.values.set(key, value);
    return this;
  }

  apply(template: string): string {
    let out = template;
    this.values.forEach((value: string, key: string) => {
      out = applyTemplate(out, key, value);
    });
    return out;
  }
}

/** 正则后处理：...~s|pattern|replacement| 或 ~si|...|...| */
function applyPostProcess(value: string, expr: string): string {
  const marker = expr.lastIndexOf('~s');
  if (marker < 0) {
    return value;
  }
  const tail = expr.substring(marker);
  const parts = tail.split('|');
  if (parts.length < 3) {
    return value;
  }
  const flags = parts[0].substring(2);
  const pattern = parts[1];
  const replacement = parts[2];
  try {
    const regex = new RegExp(pattern, flags.indexOf('g') >= 0 ? 'g' : '');
    return value.replace(regex, replacement);
  } catch (error) {
    return value;
  }
}

/** 去掉后处理段，只留取值表达式 */
function stripPostProcess(expr: string): string {
  const marker = expr.lastIndexOf('~s');
  return marker < 0 ? expr : expr.substring(0, marker);
}

/** 对单个节点求值 FieldExpr */
export function evalField(scope: HtmlNode, expr: string): string {
  if (expr.length === 0) {
    return '';
  }
  const alternatives = stripPostProcess(expr).split('||');
  const postProcessed = expr !== stripPostProcess(expr);
  let result = '';
  for (let a = 0; a < alternatives.length; a++) {
    const alternative = alternatives[a].trim();
    if (alternative.length === 0) {
      continue;
    }
    const value = evalSingle(scope, alternative);
    if (value.length > 0) {
      result = value;
      break;
    }
  }
  if (result.length === 0) {
    return '';
  }
  const cleaned = compact(decodeEntities(result));
  return postProcessed ? applyPostProcess(cleaned, expr) : cleaned;
}

function evalSingle(scope: HtmlNode, alternative: string): string {
  let selectorPart = '';
  let mode = 'text';
  const at = alternative.lastIndexOf('@');
  if (at >= 0) {
    selectorPart = alternative.substring(0, at).trim();
    mode = alternative.substring(at + 1).trim();
  } else {
    // 只写了选择器：默认取文本
    selectorPart = alternative;
    mode = 'text';
  }

  let targets: HtmlNode[] = [];
  if (selectorPart.length === 0) {
    targets = [scope];
  } else {
    targets = queryAllNodes(scope, selectorPart);
  }
  if (targets.length === 0) {
    return '';
  }

  if (mode === 'text' || mode.length === 0) {
    return targets[0].textContent();
  }
  if (mode.startsWith('attr:')) {
    const name = mode.substring(5).trim();
    for (let i = 0; i < targets.length; i++) {
      const value = targets[i].attr(name);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }
  if (mode === 'html') {
    return targets[0].textContent();
  }
  if (mode === 'outer') {
    return targets[0].textContent();
  }
  // 未知模式按文本兜底
  return targets[0].textContent();
}

/**
 * 在作用域内查询节点。
 * 语义：先前序遍历作用域全部后代，命中即收集；
 * 若选择器本身能匹配作用域，则把作用域也纳入（用于 `@text` 这类写法的一致性）。
 */
function queryAllNodes(scope: HtmlNode, selector: string): HtmlNode[] {
  const out: HtmlNode[] = [];
  if (matches(scope, selector)) {
    out.push(scope);
  }
  const stack: HtmlNode[] = [scope];
  while (stack.length > 0) {
    const node = stack.pop() as HtmlNode;
    for (let i = node.children.length - 1; i >= 0; i--) {
      const child = node.children[i];
      if (child.isText) {
        continue;
      }
      if (matches(child, selector)) {
        out.push(child);
      }
      stack.push(child);
    }
  }
  // 上面的栈遍历不保证文档顺序，统一按文档顺序重排
  out.sort((left: HtmlNode, right: HtmlNode): number => {
    const l = positionOf(scope, left);
    const r = positionOf(scope, right);
    return l - r;
  });
  return out;
}

function positionOf(scope: HtmlNode, node: HtmlNode): number {
  // 用「深度优先序号」近似文档顺序：沿父链回到 scope 再累计
  let path: number = 0;
  let cursor: HtmlNode | null = node;
  let factor: number = 1;
  while (cursor !== null && cursor !== scope) {
    const parent: HtmlNode | null = cursor.parent;
    if (parent === null) {
      break;
    }
    const index: number = parent.children.indexOf(cursor);
    path += index * factor;
    factor *= 1000;
    cursor = parent;
  }
  return path;
}

/** 解析列表型页面 */
export function parseListItems(
  html: string,
  listSelector: string,
  sourceId: string,
  baseUrl: string,
  titleExpr: string,
  coverExpr: string,
  linkExpr: string,
  idExpr: string,
  authorExpr: string,
  latestExpr: string
): ComicBrief[] {
  const doc = parseHtml(html);
  const items = queryAll(doc, listSelector);
  const result: ComicBrief[] = [];
  // 首页常有多个推荐区块、同一本漫画重复出现；重复的 comicId 会让 ForEach
  // 的 key 冲突，这里统一按 comicId 去重（保留首次出现）。
  const seen: string[] = [];
  for (let i = 0; i < items.length; i++) {
    const node = items[i];
    const title = evalField(node, titleExpr);
    const link = evalField(node, linkExpr);
    if (title.length === 0 || link.length === 0) {
      continue;
    }
    const url = resolveUrl(baseUrl, link);
    let id = idExpr.length > 0 ? evalField(node, idExpr) : '';
    if (id.length === 0) {
      id = extractNumericId(url);
    }
    if (id.length === 0) {
      id = url;
    }
    if (seen.indexOf(id) >= 0) {
      continue;
    }
    seen.push(id);
    const brief = new ComicBrief();
    brief.sourceId = sourceId;
    brief.comicId = id;
    brief.title = title;
    brief.url = url;
    const cover = coverExpr.length > 0 ? evalField(node, coverExpr) : '';
    brief.cover = cover.length > 0 ? toHttps(resolveUrl(baseUrl, cover)) : '';
    brief.author = authorExpr.length > 0 ? evalField(node, authorExpr) : '';
    brief.latest = latestExpr.length > 0 ? evalField(node, latestExpr) : '';
    result.push(brief);
  }
  return result;
}

/** JSON 型搜索结果（读漫屋等站的搜索接口返回 JSON 数组，不是 HTML） */
export function parseSearchFromJson(text: string, rule: SourceRule, baseUrl: string): ComicBrief[] {
  const result: ComicBrief[] = [];
  if (text.trim().length === 0) {
    return result;
  }
  const root = parseJson(text);
  const nodes = selectPath(root, rule.search.jsonPath);
  const flat: JsonNode[] = [];
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    if (node.kind === JsonKind.Array) {
      for (let k = 0; k < node.items.length; k++) {
        flat.push(node.items[k]);
      }
    } else {
      flat.push(node);
    }
  }
  const seen: string[] = [];
  for (let i = 0; i < flat.length; i++) {
    const item = flat[i];
    if (item.kind !== JsonKind.Object) {
      continue;
    }
    const titleNode = item.get(rule.search.jsonTitleField);
    const title = titleNode === null ? '' : titleNode.asString().trim();
    if (title.length === 0) {
      continue;
    }
    const idNode = item.get(rule.search.jsonIdField);
    const id = idNode === null ? '' : idNode.asString().trim();
    if (id.length === 0 || seen.indexOf(id) >= 0) {
      continue;
    }
    seen.push(id);
    const coverNode = item.get(rule.search.jsonCoverField);
    const cover = coverNode === null ? '' : coverNode.asString().trim();
    const authorNode = item.get(rule.search.jsonAuthorField);
    const author = authorNode === null ? '' : authorNode.asString().trim();
    const latestNode = rule.search.jsonLatestField.length > 0
      ? item.get(rule.search.jsonLatestField) : null;
    const latest = latestNode === null ? '' : latestNode.asString().trim();
    const link = rule.search.jsonLinkTemplate.length > 0
      ? rule.search.jsonLinkTemplate.split('{id}').join(id)
      : id;
    const brief = new ComicBrief();
    brief.sourceId = rule.id;
    brief.comicId = id;
    brief.title = title;
    brief.url = resolveUrl(baseUrl, link);
    brief.cover = cover.length > 0 ? toHttps(resolveUrl(baseUrl, cover)) : '';
    brief.author = author;
    brief.latest = latest;
    result.push(brief);
  }
  return result;
}

/** 解析详情页的元信息（不含章节） */
export class DetailFields {
  title: string = '';
  cover: string = '';
  author: string = '';
  description: string = '';
  status: string = '';
  tags: string = '';
}

export function parseDetailFields(
  doc: HtmlDocument,
  rule: SourceRule,
  pageUrl: string
): DetailFields {
  const fields = new DetailFields();
  const root = doc.root;
  fields.title = evalField(root, rule.detail.title);
  const cover = evalField(root, rule.detail.cover);
  fields.cover = cover.length > 0 ? toHttps(resolveUrl(pageUrl, cover)) : '';
  fields.author = evalField(root, rule.detail.author);
  fields.description = evalField(root, rule.detail.desc);
  fields.status = evalField(root, rule.detail.status);
  fields.tags = evalField(root, rule.detail.tags);
  return fields;
}

/** 解析章节列表 */
export function parseChapters(doc: HtmlDocument, rule: SourceRule, pageUrl: string, applyReverse: boolean = true): ChapterBrief[] {
  const items = queryAll(doc, rule.chapters.listSelector);
  const chapters: ChapterBrief[] = [];
  for (let i = 0; i < items.length; i++) {
    const node = items[i];
    const title = evalField(node, rule.chapters.title);
    const link = evalField(node, rule.chapters.link);
    if (link.length === 0 || link.indexOf('javascript:') === 0 || link.indexOf('#') === 0) {
      continue;
    }
    const url = resolveUrl(pageUrl, link);
    let id = rule.chapters.id.length > 0 ? evalField(node, rule.chapters.id) : '';
    if (id.length === 0) {
      id = extractNumericId(url);
    }
    if (id.length === 0) {
      id = url;
    }
    const chapter = new ChapterBrief();
    chapter.chapterId = id;
    chapter.title = title.length > 0 ? title : `第 ${i + 1} 话`;
    chapter.url = url;
    chapter.index = i;
    if (rule.chapters.time.length > 0) {
      chapter.time = compact(evalField(node, rule.chapters.time));
    }
    chapters.push(chapter);
  }
  if (rule.chapters.reverse && applyReverse) {
    chapters.reverse();
    for (let i = 0; i < chapters.length; i++) {
      chapters[i].index = i;
    }
  }
  return chapters;
}

/** 从页面内嵌的 JSON 节点里取文本（如 <script type="text/plain" id="x">） */
export function readEmbeddedJson(doc: HtmlDocument, selector: string): string {
  if (selector.length === 0) {
    return '';
  }
  const node = queryOne(doc, selector);
  return node === null ? '' : node.textContent();
}

/** 解析 JSON 型的章节列表 */
export function parseChaptersFromJson(
  text: string,
  rule: SourceRule,
  pageUrl: string,
  comicId: string = '',
  applyReverse: boolean = true
): ChapterBrief[] {
  if (text.trim().length === 0) {
    return [];
  }
  const root = parseJson(text);
  const nodes = selectPath(root, rule.chapters.json.path);
  const flat: JsonNode[] = [];
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    if (node.kind === JsonKind.Array) {
      for (let k = 0; k < node.items.length; k++) {
        flat.push(node.items[k]);
      }
    } else {
      flat.push(node);
    }
  }
  const chapters: ChapterBrief[] = [];
  const base = rule.chapters.json.baseUrl.length > 0 ? rule.chapters.json.baseUrl : pageUrl;
  for (let i = 0; i < flat.length; i++) {
    const item = flat[i];
    if (item.kind !== JsonKind.Object) {
      continue;
    }
    const idNode = item.get(rule.chapters.json.idField);
    const titleNode = item.get(rule.chapters.json.titleField);
    const linkNode = item.get(rule.chapters.json.linkField);
    if (linkNode === null && idNode === null) {
      continue;
    }
    const linkRaw = linkNode === null ? '' : linkNode.asString();
    const id = idNode === null ? extractNumericId(linkRaw) : idNode.asString();
    if (id.length === 0 && linkRaw.length === 0) {
      continue;
    }
    let link = linkRaw;
    // 接口只给 id 不给地址的站点，按模板拼（`/chapter/{contentId}-{id}.html`）
    if (link.length === 0 && rule.chapters.json.linkTemplate.length > 0) {
      link = applyJsonTemplate(item, rule.chapters.json.linkTemplate, comicId);
    }
    const chapter = new ChapterBrief();
    chapter.chapterId = id.length > 0 ? id : extractNumericId(linkRaw);
    chapter.title = titleNode === null ? `第 ${i + 1} 话` : titleNode.asString();
    chapter.url = link.length > 0 ? resolveUrl(base, link) : base;
    chapter.index = i;
    if (rule.chapters.json.timeField.length > 0) {
      const timeNode = item.get(rule.chapters.json.timeField);
      if (timeNode !== null) {
        chapter.time = compact(timeNode.asString());
      }
    }
    chapters.push(chapter);
  }
  if (rule.chapters.reverse && applyReverse) {
    chapters.reverse();
    for (let i = 0; i < chapters.length; i++) {
      chapters[i].index = i;
    }
  }
  return chapters;
}

/**
 * 用 JSON 条目的字段拼地址：`/chapter/{contentId}-{id}.html`。
 * 花括号里写字段名，取不到就留空，避免拼出 `undefined`。
 * 额外支持 `{comicId}` 这类规则级变量（由调用方传入）。
 */
function applyJsonTemplate(item: JsonNode, template: string, comicId: string = ''): string {
  const tokens = template.match(new RegExp('\\{[A-Za-z0-9_]+\\}', 'g'));
  let result = template;
  if (tokens === null) {
    return result;
  }
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    const name = token.substring(1, token.length - 1);
    let value = '';
    if (name === 'comicId') {
      value = comicId;
    } else {
      const node = item.get(name);
      value = node === null ? '' : node.asString();
    }
    result = result.split(token).join(value);
  }
  return result;
}

/** 合并两批章节，按 URL 去重，保持先 first 后 second 的顺序 */
export function mergeChapters(first: ChapterBrief[], second: ChapterBrief[]): ChapterBrief[] {
  const seen: string[] = [];
  const out: ChapterBrief[] = [];
  for (let i = 0; i < first.length; i++) {
    if (seen.indexOf(first[i].url) < 0) {
      seen.push(first[i].url);
      out.push(first[i]);
    }
  }
  for (let i = 0; i < second.length; i++) {
    if (seen.indexOf(second[i].url) < 0) {
      seen.push(second[i].url);
      out.push(second[i]);
    }
  }
  return out;
}

/** JSON 类源的图片解析 */
export function parseImagesFromJson(body: string, rule: SourceRule, referer: string): PageImage[] {
  const root = parseJson(body);
  const nodes = selectPath(root, rule.images.list);
  const images: PageImage[] = [];
  for (let n = 0; n < nodes.length; n++) {
    const node = nodes[n];
    if (node.kind === JsonKind.Array) {
      for (let i = 0; i < node.items.length; i++) {
        pushImage(images, node.items[i], rule.images.field, referer);
      }
    } else if (node.kind === JsonKind.Object) {
      pushImage(images, node, rule.images.field, referer);
    }
  }
  return images;
}

function pushImage(target: PageImage[], node: JsonNode, field: string, referer: string): void {
  if (node.kind !== JsonKind.Object) {
    return;
  }
  const value = node.get(field);
  if (value === null) {
    return;
  }
  const url = value.asString().trim();
  if (url.length === 0) {
    return;
  }
  const image = new PageImage();
  image.url = toHttps(url.startsWith('//') ? 'https:' + url : url);
  image.referer = referer;
  target.push(image);
}

/** HTML 类源的图片解析 */
export function parseImagesFromHtml(html: string, rule: SourceRule, pageUrl: string): PageImage[] {
  const doc = parseHtml(html);
  const items = rule.images.list.length > 0 ? queryAll(doc, rule.images.list) : doc.flat;
  const images: PageImage[] = [];
  for (let i = 0; i < items.length; i++) {
    const raw = evalField(items[i], rule.images.field);
    if (raw.length === 0) {
      continue;
    }
    const image = new PageImage();
    image.url = toHttps(resolveUrl(pageUrl, raw));
    image.referer = pageUrl;
    images.push(image);
  }
  return images;
}

/**
 * 序号类源的图片解析。
 *
 * 一批国内漫画站把正文图写成「前缀 + 序号」：
 *   var num =eval("45")
 *   var pasd = "https://image1.example.com/mh/{hash}/{uuid}/"
 *   for(i=1;i<=num;i++) img.src = pasd + i + ".webp"
 * 页面里一个 <img> 都没有，光抠地址是抠不到的，但前缀和数量都在 HTML 里，
 * 按模板生成即可 —— 比无头取图快两个数量级。
 */
export function parseImagesFromSequence(html: string, rule: SourceRule, pageUrl: string): PageImage[] {
  const images: PageImage[] = [];
  if (rule.images.pattern.length === 0 || rule.images.template.length === 0) {
    return images;
  }
  const base = firstCapture(html, rule.images.pattern);
  if (base.length === 0) {
    return images;
  }
  let count = 0;
  if (rule.images.countPattern.length > 0) {
    const raw = firstCapture(html, rule.images.countPattern);
    const parsed = parseInt(raw, 10);
    count = isNaN(parsed) ? 0 : parsed;
  }
  if (count <= 0) {
    count = rule.images.maxCount;
  }
  if (count > rule.images.maxCount) {
    count = rule.images.maxCount;
  }
  for (let i = 1; i <= count; i++) {
    const url = rule.images.template
      .replace('{base}', base)
      .replace('{i}', String(i))
      .replace('{chapterUrl}', pageUrl);
    if (url.length === 0) {
      continue;
    }
    const image = new PageImage();
    image.url = toHttps(url.startsWith('//') ? 'https:' + url : url);
    image.referer = pageUrl;
    images.push(image);
  }
  return images;
}

/** 取第一个捕获组（无捕获组时取整个匹配） */
function firstCapture(text: string, pattern: string): string {  let regex: RegExp;
  try {
    regex = new RegExp(pattern);
  } catch (error) {
    return '';
  }
  const match = regex.exec(text);
  if (match === null) {
    return '';
  }
  const value = match.length > 1 ? match[1] : match[0];
  return value === undefined ? '' : value.trim();
}

/** 正则类源的图片解析：从原始 HTML 里直接抠地址 */
export function parseImagesFromRegex(html: string, rule: SourceRule, pageUrl: string): PageImage[] {
  const images: PageImage[] = [];
  if (rule.images.pattern.length === 0) {
    return images;
  }
  let regex: RegExp;
  try {
    regex = new RegExp(rule.images.pattern, 'g');
  } catch (error) {
    return images;
  }
  const seen: string[] = [];
  let guard = 0;
  let match: RegExpExecArray | null = regex.exec(html);
  while (match !== null) {
    guard++;
    if (guard > 2000) {
      break;
    }
    let raw = match.length > 1 ? match[1] : match[0];
    if (raw === undefined) {
      raw = '';
    }
    // 捕获到的可能是一个 URL，也可能是「一串 URL 连在一起」（如
    // current_chapter:{...chapter_img_list:["url1","url2",...]} 这种内联数组），
    // 这里统一拆开，逐个去重入列。
    for (let u = 0; u < splitUrls(raw).length; u++) {
      const url = splitUrls(raw)[u];
      if (url.length > 0 && seen.indexOf(url) < 0) {
        seen.push(url);
        const image = new PageImage();
        image.url = toHttps(url.startsWith('//') ? 'https:' + url : url);
        image.referer = pageUrl;
        images.push(image);
      }
    }
    // 零长度匹配保护：否则 exec 会原地打转
    if (match.index === regex.lastIndex) {
      regex.lastIndex++;
    }
    match = regex.exec(html);
  }
  return images;
}

/** 把「可能是多个 URL 拼在一起」的捕获串拆成独立 URL 列表 */
function splitUrls(raw: string): string[] {
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return [];
  }
  // 内联数组形如 `"url1","url2",...`，直接按引号拆；
  // 拆出来的每一段里只要以 http(s):// 或 // 开头，就当作一个 URL。
  const pieces = trimmed.split('"');
  const out: string[] = [];
  for (let i = 0; i < pieces.length; i++) {
    const piece = pieces[i].trim();
    if (piece.indexOf('http://') === 0 || piece.indexOf('https://') === 0 ||
      piece.indexOf('//') === 0) {
      out.push(piece);
    }
  }
  // 没拆出多个（比如单条 URL 或其它形态），按原串兜底
  if (out.length === 0) {
    out.push(trimmed);
  }
  return out;
}

/** 从页面里找出所有疑似图片地址（web 模式的兜底） */
export function guessImages(html: string, pageUrl: string): PageImage[] {
  const images: PageImage[] = [];
  const pattern = new RegExp('(?:https?:)?//[^"\'\\s\\\\)]+\\.(?:jpg|jpeg|png|webp)[^"\'\\s\\\\)]*', 'gi');
  const found = html.match(pattern);
  if (found === null) {
    return images;
  }
  const noise = new RegExp('logo|icon|avatar|favicon|banner|placeholder|sprite|loading', 'i');
  for (let i = 0; i < found.length; i++) {
    const url = found[i];
    if (noise.test(url)) {
      continue;
    }
    if (images.length > 0 && images[images.length - 1].url === url) {
      continue;
    }
    const image = new PageImage();
    image.url = toHttps(url.startsWith('//') ? 'https:' + url : url);
    image.referer = pageUrl;
    images.push(image);
  }
  return images;
}

/**
 * AES-CBC 解密（针对爱国漫/国漫网这类站）。
 * 密文是 base64，密钥固定，CBC 模式的 IV 取密文前 16 字符的 UTF-8 字节。
 */
export async function decryptAesCbc(cipherBase64: string, key: string, ivText: string): Promise<string> {
  try {
    const base64Helper = new util.Base64Helper();
    const cipherBytes: Uint8Array = base64Helper.decodeSync(cipherBase64);

    const keyBytes: Uint8Array = new Uint8Array(buffer.from(key, 'utf-8').buffer);
    const symKeyBlob: cryptoFramework.DataBlob = { data: keyBytes };
    const keyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const symKey = await keyGenerator.convertKey(symKeyBlob);

    const ivBytes: Uint8Array = new Uint8Array(buffer.from(ivText, 'utf-8').buffer);
    const ivParams: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: ivBytes }
    };

    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS5');
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParams);
    const plainData: cryptoFramework.DataBlob = await cipher.doFinal({ data: cipherBytes });
    const plainBytes = new Uint8Array(plainData.data);
    return buffer.from(plainBytes.buffer).toString('utf-8');
  } catch (error) {
    return '';
  }
}

/** 取正则第一个捕获组（无捕获组取整个匹配） */
function firstCaptureOf(text: string, pattern: string): string {
  try {
    const regex = new RegExp(pattern);
    const match = regex.exec(text);
    if (match === null) {
      return '';
    }
    const value = match.length > 1 ? match[1] : match[0];
    return value === undefined ? '' : value;
  } catch (error) {
    return '';
  }
}

/**
 * aes 模式的图片解析：页面里有一段 base64 密文，AES 解密后是含图片数组的 JSON。
 * 流程：正则提取密文 → AES-CBC 解密 → 正则提取图片数组 → 按引号拆成 URL 列表。
 */
export async function parseImagesFromAes(html: string, rule: SourceRule, pageUrl: string): Promise<PageImage[]> {
  const images: PageImage[] = [];
  if (rule.images.aesKey.length === 0 || rule.images.aesPattern.length === 0) {
    return images;
  }
  const cipherText = firstCaptureOf(html, rule.images.aesPattern).trim();
  if (cipherText.length === 0) {
    return images;
  }
  // IV 来源：默认取密文前 16 字符
  const ivText = rule.images.aesIvSource === 'cipher16' ? cipherText.substring(0, 16) : '';
  const plain = await decryptAesCbc(cipherText, rule.images.aesKey, ivText);
  if (plain.length === 0) {
    return images;
  }
  // 从解密后的明文里提取图片数组
  let raw = plain;
  if (rule.images.aesListPattern.length > 0) {
    const matched = firstCaptureOf(plain, rule.images.aesListPattern);
    if (matched.length > 0) {
      raw = matched;
    }
  }
  // 按引号拆出 URL（解密后的 JSON 里图片地址是 "..." 格式，可能带 \/ 转义）
  const unescaped = raw.split('\\/').join('/');
  const seen: string[] = [];
  const urls = splitUrls(unescaped);
  for (let i = 0; i < urls.length; i++) {
    const url = urls[i];
    if (url.length === 0 || seen.indexOf(url) >= 0) {
      continue;
    }
    seen.push(url);
    const image = new PageImage();
    image.url = toHttps(url.startsWith('//') ? 'https:' + url : url);
    image.referer = pageUrl;
    images.push(image);
  }
  return images;
}

/**
 * base64 模式的图片解析（猫咪漫画 qTcms 系）。
 * 页面里 `qTcms_S_m_murl_e = "<base64>"`，解码后是多个图片地址，
 * 用 `$qingtiandy$` 这类分隔符串起来。
 */
export function parseImagesFromBase64(html: string, rule: SourceRule, pageUrl: string): PageImage[] {
  const images: PageImage[] = [];
  if (rule.images.pattern.length === 0) {
    return images;
  }
  const raw = firstCaptureOf(html, rule.images.pattern).trim();
  if (raw.length === 0) {
    return images;
  }
  let decoded = '';
  try {
    const helper = new util.Base64Helper();
    const bytes: Uint8Array = helper.decodeSync(raw);
    decoded = buffer.from(bytes.buffer).toString('utf-8');
  } catch (error) {
    return images;
  }
  const separator = rule.images.separator.length > 0 ? rule.images.separator : '\n';
  const parts = decoded.split(separator);
  const seen: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const url = parts[i].trim();
    if (url.indexOf('http') !== 0 && url.indexOf('//') !== 0) {
      continue;
    }
    if (seen.indexOf(url) >= 0) {
      continue;
    }
    seen.push(url);
    const image = new PageImage();
    image.url = toHttps(url.startsWith('//') ? 'https:' + url : url);
    image.referer = pageUrl;
    images.push(image);
  }
  return images;
}
