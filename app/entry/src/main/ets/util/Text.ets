/**
 * 文本与章节号工具。
 * chapterNumber 优先匹配「第 N 话/回/章」形式，并剥离日期，减少换源对齐偏差。
 */

export function trim(s: string): string {
  return s.replace(/^\s+|\s+$/g, '');
}

export function collapseSpace(s: string): string {
  return s.replace(/\s+/g, ' ').trim();
}

export function stripHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

export function absUrl(base: string, href: string): string {
  if (!href || href.length === 0) {
    return '';
  }
  if (href.startsWith('http://') || href.startsWith('https://')) {
    return href;
  }
  if (href.startsWith('//')) {
    const scheme = base.startsWith('https') ? 'https:' : 'http:';
    return scheme + href;
  }
  try {
    // 简易绝对化
    const m = base.match(/^(https?:\/\/[^\/]+)/);
    const origin = m ? m[1] : base;
    if (href.startsWith('/')) {
      return origin + href;
    }
    const dir = base.replace(/\/[^\/]*$/, '/');
    return dir + href;
  } catch {
    return href;
  }
}

const URL_SCHEME = new RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://');

/** 将规则中的相对链接解析为绝对链接，支持协议相对、查询参数及 .. 路径。 */
export function resolveUrl(base: string, relative: string): string {
  const raw = relative.trim();
  if (raw.length === 0) return base;
  if (URL_SCHEME.test(raw) || raw.startsWith('data:')) return raw;
  if (raw.startsWith('//')) return (base.startsWith('https://') ? 'https:' : 'http:') + raw;
  // 纯锚点保留当前页面路径及查询参数，不按目录拼接。
  if (raw.startsWith('#')) return base.split('#')[0] + raw;
  const hashBase = base.split('#')[0];
  const scheme = hashBase.indexOf('://');
  if (scheme < 0) return raw;
  const hostStart = scheme + 3;
  const authorityEnd = hashBase.substring(hostStart).search(/[/?]/);
  const boundary = authorityEnd < 0 ? hashBase.length : hostStart + authorityEnd;
  const origin = hashBase.substring(0, boundary);
  let path = hashBase.substring(boundary);
  if (!path.startsWith('/')) path = '/' + path;
  if (raw.startsWith('/')) return origin + raw;
  if (raw.startsWith('?')) {
    const q = path.indexOf('?');
    return origin + (q >= 0 ? path.substring(0, q) : path) + raw;
  }
  const q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  const last = path.lastIndexOf('/');
  // 查询参数里的斜线不属于路径，先分离再折叠 . 和 ..。
  const suffixAt = raw.search(/[?#]/);
  const relativePath = suffixAt < 0 ? raw : raw.substring(0, suffixAt);
  const suffix = suffixAt < 0 ? '' : raw.substring(suffixAt);
  const merged = (last >= 0 ? path.substring(0, last + 1) : '/') + relativePath;
  const parts = merged.split('/');
  const stack: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    if (parts[i] === '' || parts[i] === '.') continue;
    if (parts[i] === '..') {
      if (stack.length > 0) stack.pop();
    } else stack.push(parts[i]);
  }
  const trailing = merged.endsWith('/') || merged.endsWith('/.') || merged.endsWith('/..');
  return origin + '/' + stack.join('/') + (trailing && stack.length > 0 ? '/' : '') + suffix;
}

/** 规则模板单键替换。 */
export function applyTemplate(template: string, key: string, value: string): string {
  return template.split('{' + key + '}').join(value);
}

export function firstCaptureOf(text: string, pattern: string): string {
  if (!pattern || pattern.length === 0) {
    return '';
  }
  try {
    const re = new RegExp(pattern, 'i');
    const m = text.match(re);
    if (m && m.length > 1) {
      return m[1] ?? '';
    }
    if (m && m.length === 1) {
      return m[0] ?? '';
    }
  } catch {
    // ignore bad pattern
  }
  return '';
}

export function allCapturesOf(text: string, pattern: string): string[] {
  const out: string[] = [];
  if (!pattern || pattern.length === 0) {
    return out;
  }
  try {
    const re = new RegExp(pattern, 'gi');
    let m: RegExpExecArray | null = re.exec(text);
    // 图源正则可能匹配空字符串。全局 RegExp.exec 在零宽匹配时不会自动前进。
    let steps = 0;
    while (m !== null && steps < 10000) {
      if (m.length > 1 && m[1]) {
        out.push(m[1]);
      } else if (m[0]) {
        out.push(m[0]);
      }
      steps++;
      if (m[0].length === 0) {
        if (re.lastIndex >= text.length) break;
        re.lastIndex++;
      }
      m = re.exec(text);
    }
  } catch {
    // ignore
  }
  return out;
}

/**
 * 从标题中提取章节序号，用于跨源对齐。
 * 优先「第 N 话/回/章/节/集」，避免把日期或 Vol.2 里的数字当章节号。
 */
export function chapterNumber(title: string): number {
  // 优先「第 N 话/回/章/节/集」，避免把日期或 Vol.2 里的数字当章节号
  const labeled = title.match(new RegExp('第\\s*(\\d+(?:\\.\\d+)?)\\s*[话回章节集]'));
  if (labeled && labeled[1]) {
    const n = parseFloat(labeled[1]);
    if (!isNaN(n)) {
      return n;
    }
  }
  // 去掉日期片段再取第一个数字，减少「12月3日 第5话」对齐到 12 的情况
  const cleaned = title
    .replace(/\d{4}[-年/]\d{1,2}[-月/]\d{1,2}/g, ' ')
    .replace(/\d{1,2}月\d{1,2}日/g, ' ')
    .replace(/\d{4}-\d{2}-\d{2}/g, ' ');
  const m = cleaned.match(/(\d+(?:\.\d+)?)/);
  if (m && m[1]) {
    const n = parseFloat(m[1]);
    if (!isNaN(n)) {
      return n;
    }
  }
  return -1;
}

export function normalizeTitle(title: string): string {
  return collapseSpace(
    title
      .replace(/[【\[\(（].*?[】\]\)）]/g, '')
      .replace(/第\s*\d+\s*[话回章节集]/g, '')
      .toLowerCase()
  );
}

export function similarity(a: string, b: string): number {
  const x = normalizeTitle(a);
  const y = normalizeTitle(b);
  if (x.length === 0 || y.length === 0) {
    return 0;
  }
  if (x === y) {
    return 1;
  }
  if (x.includes(y) || y.includes(x)) {
    return 0.85;
  }
  // 简单字符重叠
  const setA = new Set(x.split(''));
  let hit = 0;
  for (const c of y) {
    if (setA.has(c)) {
      hit++;
    }
  }
  return hit / Math.max(x.length, y.length);
}

export function decodeHtmlEntities(s: string): string {
  return decodeEntities(s);
}

/** HTML 实体解码，避免 ArkTS 对正则回调隐式 any 的限制。 */
export function decodeEntities(input: string): string {
  let out = input.split('&nbsp;').join(' ').split('&amp;').join('&')
    .split('&lt;').join('<').split('&gt;').join('>').split('&quot;').join('"')
    .split('&#39;').join("'").split('&apos;').join("'");
  const numeric = new RegExp('&#(x?)([0-9a-fA-F]+);', 'g');
  let match: RegExpExecArray | null = numeric.exec(out);
  while (match !== null) {
    const code = match[1] === 'x' ? parseInt(match[2], 16) : parseInt(match[2], 10);
    if (!isNaN(code) && code >= 0 && code <= 0x10ffff) {
      // 补充平面字符需要代理对，避免表情或生僻字被截断为单个 UTF-16 字符。
      const decoded = code <= 0xffff ? String.fromCharCode(code) :
        String.fromCharCode(0xd800 + ((code - 0x10000) >> 10), 0xdc00 + ((code - 0x10000) & 0x3ff));
      out = out.replace(match[0], decoded);
      numeric.lastIndex = 0;
    }
    match = numeric.exec(out);
  }
  return out;
}

export function compact(input: string): string {
  return input.replace(/\s+/g, ' ').trim();
}

export function extractNumericId(url: string): string {
  let path = url;
  const scheme = path.indexOf('://');
  if (scheme >= 0) {
    const slash = path.indexOf('/', scheme + 3);
    path = slash >= 0 ? path.substring(slash) : '/';
  }
  const query = path.indexOf('?');
  if (query >= 0) path = path.substring(0, query);
  const runs = path.match(/\d{2,}/g);
  if (runs !== null && runs.length > 0) {
    let best = runs[0];
    for (let i = 1; i < runs.length; i++) if (runs[i].length > best.length) best = runs[i];
    return best;
  }
  const fallback = url.match(/\d{2,}/);
  return fallback === null ? '' : fallback[0];
}

export function toHttps(url: string): string {
  return url.startsWith('http://') ? 'https://' + url.substring(7) : url;
}

export function shortTime(raw: string): string {
  const full = raw.match(/(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
  if (full !== null) return `${full[2]}-${full[3]}`;
  const short = raw.match(/(\d{1,2})[-/](\d{1,2})/);
  if (short !== null) return `${short[1]}-${short[2]}`;
  return raw.length > 10 ? raw.substring(0, 10) : raw;
}

export function safeJsonParse(text: string): Object | null {
  try {
    return JSON.parse(text) as Object;
  } catch {
    return null;
  }
}

export function pickString(obj: Object | null, path: string): string {
  if (obj === null || path.length === 0) {
    return '';
  }
  const parts = path.split('.');
  let cur: Object | null = obj;
  for (const p of parts) {
    if (cur === null || typeof cur !== 'object') {
      return '';
    }
    const rec = cur as Record<string, Object>;
    if (Object.keys(rec).indexOf(p) < 0) {
      return '';
    }
    cur = rec[p] as Object;
  }
  if (cur === null || cur === undefined) {
    return '';
  }
  return String(cur);
}

export function pickArray(obj: Object | null, path: string): Object[] {
  if (obj === null || path.length === 0) {
    return [];
  }
  const parts = path.split('.');
  let cur: Object | null = obj;
  for (const p of parts) {
    if (cur === null || typeof cur !== 'object') {
      return [];
    }
    const rec = cur as Record<string, Object>;
    if (Object.keys(rec).indexOf(p) < 0) {
      return [];
    }
    cur = rec[p] as Object;
  }
  if (Array.isArray(cur)) {
    return cur as Object[];
  }
  return [];
}
