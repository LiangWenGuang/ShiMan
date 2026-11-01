/**
 * 规则执行引擎：把 SourceRule 变成真正的数据。
 *
 * 这里只做「解析」，不做网络请求 —— 网络在 net/Http，两者解耦，
 * 便于在没有设备的情况下用纯逻辑测试解析正确性。
 */

import { HtmlNode, HtmlDocument, parseHtml } from '../parse/Html';
import { queryAll, queryOne, matches } from '../parse/Selector';
import { JsonNode, JsonKind, parseJson, selectPath } from '../parse/Json';
import { resolveUrl, decodeEntities, compact, extractNumericId, applyTemplate, toHttps } from '../util/Text';
import { ComicBrief, ChapterBrief, PageImage } from '../model/Models';
import { SourceRule, HeaderPair } from './Rules';

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
export function parseChapters(doc: HtmlDocument, rule: SourceRule, pageUrl: string): ChapterBrief[] {
  const items = queryAll(doc, rule.chapters.listSelector);
  const chapters: ChapterBrief[] = [];
  for (let i = 0; i < items.length; i++) {
    const node = items[i];
    const title = evalField(node, rule.chapters.title);
    const link = evalField(node, rule.chapters.link);
    if (link.length === 0) {
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
    chapters.push(chapter);
  }
  if (rule.chapters.reverse) {
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
export function parseChaptersFromJson(text: string, rule: SourceRule, pageUrl: string): ChapterBrief[] {
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
      link = applyJsonTemplate(item, rule.chapters.json.linkTemplate);
    }
    const chapter = new ChapterBrief();
    chapter.chapterId = id.length > 0 ? id : extractNumericId(linkRaw);
    chapter.title = titleNode === null ? `第 ${i + 1} 话` : titleNode.asString();
    chapter.url = link.length > 0 ? resolveUrl(base, link) : base;
    chapter.index = i;
    chapters.push(chapter);
  }
  if (rule.chapters.reverse) {
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
 */
function applyJsonTemplate(item: JsonNode, template: string): string {
  const tokens = template.match(new RegExp('\\{[A-Za-z0-9_]+\\}', 'g'));
  let result = template;
  if (tokens === null) {
    return result;
  }
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    const name = token.substring(1, token.length - 1);
    const node = item.get(name);
    const value = node === null ? '' : node.asString();
    result = result.split(token).join(value);
  }
  return result;
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
export function parseImagesFromRegex(html: string, rule: SourceRule, pageUrl: string): PageImage[] {  const images: PageImage[] = [];
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
    const url = raw.trim();
    if (url.length > 0 && seen.indexOf(url) < 0) {
      seen.push(url);
      const image = new PageImage();
      image.url = toHttps(url.startsWith('//') ? 'https:' + url : url);
      image.referer = pageUrl;
      images.push(image);
    }
    // 零长度匹配保护：否则 exec 会原地打转
    if (match.index === regex.lastIndex) {
      regex.lastIndex++;
    }
    match = regex.exec(html);
  }
  return images;
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
