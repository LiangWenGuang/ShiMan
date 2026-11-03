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
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import { util } from '@kit.ArkTS';

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
  return targets[0].textContent();
}

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
  out.sort((left: HtmlNode, right: HtmlNode): number => {
    const l = positionOf(scope, left);
    const r = positionOf(scope, right);
    return l - r;
  });
  return out;
}

function positionOf(scope: HtmlNode, node: HtmlNode): number {
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

export function readEmbeddedJson(doc: HtmlDocument, selector: string): string {
  if (selector.length === 0) {
    return '';
  }
  const node = queryOne(doc, selector);
  return node === null ? '' : node.textContent();
}

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
 * 数量匹配不到就返回空，maxCount 只做上限，绝不当默认页数。
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
  // 数量匹配不到就返回空，让上层报「本章未取到图片」；
  // maxCount 只做上限，绝不当默认页数（否则会灌一堆 404 假图）。
  if (count <= 0) {
    return images;
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

function firstCapture(text: string, pattern: string): string {
  let regex: RegExp;
  try {
    regex = new RegExp(pattern);
  } catch (error) {
    return '';
  }
  const m = text.match(regex);
  if (m === null) {
    return '';
  }
  return m.length > 1 ? m[1] : m[0];
}

function firstCaptureOf(text: string, pattern: string): string {
  return firstCapture(text, pattern);
}

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
  let m: RegExpExecArray | null = regex.exec(html);
  while (m !== null) {
    const raw = m.length > 1 ? m[1] : m[0];
    if (raw !== undefined && raw.length > 0) {
      const image = new PageImage();
      image.url = toHttps(resolveUrl(pageUrl, raw));
      image.referer = pageUrl;
      images.push(image);
    }
    m = regex.exec(html);
  }
  return images;
}

/**
 * AES-CBC 解密。
 * cipherBase64 应是去掉 IV 前缀后的 base64 载荷；ivText 为 16 字符明文 IV。
 */
export async function decryptAesCbc(cipherBase64: string, key: string, ivText: string): Promise<string> {
  try {
    if (cipherBase64.length === 0 || ivText.length === 0) {
      return '';
    }
    const base64Helper = new util.Base64Helper();
    const cipherBytes: Uint8Array = base64Helper.decodeSync(cipherBase64);

    const keyRaw = buffer.from(key, 'utf-8');
    // Buffer 在 ArkTS 中暴露 length；按实际 UTF-8 字节长度构造 AES 密钥。
    const keyBytes: Uint8Array = new Uint8Array(keyRaw.length);
    keyBytes.set(new Uint8Array(keyRaw.buffer, keyRaw.byteOffset, keyRaw.length));
    const symKeyBlob: cryptoFramework.DataBlob = { data: keyBytes };
    const keyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const symKey = await keyGenerator.convertKey(symKeyBlob);

    const ivRaw = buffer.from(ivText, 'utf-8');
    const ivBytes: Uint8Array = new Uint8Array(ivRaw.length);
    ivBytes.set(new Uint8Array(ivRaw.buffer, ivRaw.byteOffset, ivRaw.length));
    const ivParams: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: ivBytes }
    };

    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS5');
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParams);
    const out = await cipher.doFinal({ data: cipherBytes });
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(out.data);
  } catch (error) {
    return '';
  }
}

/**
 * aes 模式的图片解析：页面里有一段 base64 密文，AES 解密后是含图片数组的 JSON。
 * mccms：IV 取密文前 16 字符，真正参与解密的 base64 从第 17 字符起。
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
  // mccms：IV 取密文前 16 字符，真正参与解密的 base64 从第 17 字符起
  let ivText = '';
  let payload = cipherText;
  if (rule.images.aesIvSource === 'cipher16') {
    if (cipherText.length <= 16) {
      return images;
    }
    ivText = cipherText.substring(0, 16);
    payload = cipherText.substring(16);
  } else {
    // 仅支持 cipher16；留空或未知策略不解密，避免空 IV 的 CBC 悄悄失败
    return images;
  }
  const plain = await decryptAesCbc(payload, rule.images.aesKey, ivText);
  if (plain.length === 0) {
    return images;
  }
  let raw = plain;
  if (rule.images.aesListPattern.length > 0) {
    const matched = firstCaptureOf(plain, rule.images.aesListPattern);
    if (matched.length > 0) {
      raw = matched;
    }
  }
  const unescaped = raw.split('\\/').join('/');
  const urlRegex = new RegExp('"([^"]+)"', 'g');
  let m: RegExpExecArray | null = urlRegex.exec(unescaped);
  while (m !== null) {
    const u = m[1];
    if (u !== undefined && (u.startsWith('http') || u.startsWith('//'))) {
      const image = new PageImage();
      image.url = toHttps(u.startsWith('//') ? 'https:' + u : u);
      image.referer = pageUrl;
      images.push(image);
    }
    m = urlRegex.exec(unescaped);
  }
  return images;
}

export function parseImagesFromBase64(html: string, rule: SourceRule, pageUrl: string): PageImage[] {
  const images: PageImage[] = [];
  if (rule.images.pattern.length === 0) {
    return images;
  }
  const encoded = firstCaptureOf(html, rule.images.pattern).trim();
  if (encoded.length === 0) {
    return images;
  }
  try {
    const base64Helper = new util.Base64Helper();
    const bytes = base64Helper.decodeSync(encoded);
    const decoder = util.TextDecoder.create('utf-8');
    const plain = decoder.decodeToString(bytes);
    const sep = rule.images.separator.length > 0 ? rule.images.separator : '$qingtiandy$';
    const parts = plain.split(sep);
    for (let i = 0; i < parts.length; i++) {
      const u = parts[i].trim();
      if (u.length === 0) {
        continue;
      }
      const image = new PageImage();
      image.url = toHttps(resolveUrl(pageUrl, u));
      image.referer = pageUrl;
      images.push(image);
    }
  } catch (error) {
    return images;
  }
  return images;
}

export function guessImages(html: string, pageUrl: string): PageImage[] {
  const images: PageImage[] = [];
  const regex = new RegExp('(https?://[^\\s"\'<>]+\\.(?:jpg|jpeg|png|webp|gif))', 'gi');
  let m: RegExpExecArray | null = regex.exec(html);
  while (m !== null) {
    const u = m[1];
    if (u !== undefined) {
      const image = new PageImage();
      image.url = toHttps(u);
      image.referer = pageUrl;
      images.push(image);
    }
    m = regex.exec(html);
  }
  return images;
}
