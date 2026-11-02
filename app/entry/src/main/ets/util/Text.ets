/**
 * 字符串与 URL 工具。
 *
 * 图源规则里大量出现「相对地址 + 模板替换 + 正则后处理」，
 * 这里集中实现，避免各处重复且语义不一致。
 */

const SCHEME = new RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://');

/** 判断是否为绝对 URL */
export function isAbsoluteUrl(value: string): boolean {
  if (value.length === 0) {
    return false;
  }
  return SCHEME.test(value) || value.startsWith('//') || value.startsWith('data:');
}

/**
 * 把相对地址解析为绝对地址。
 * 手写实现而非 URL 类，因为要处理 `//host/x`、`../x`、`?query`、纯锚点等
 * 站点常见的非规范写法。
 */
export function resolveUrl(base: string, relative: string): string {
  const raw = relative.trim();
  if (raw.length === 0) {
    return base;
  }
  if (SCHEME.test(raw)) {
    return raw;
  }
  if (raw.startsWith('//')) {
    const protocol = base.startsWith('https://') ? 'https:' : 'http:';
    return protocol + raw;
  }
  if (raw.startsWith('#')) {
    const hashIndex = base.indexOf('#');
    return (hashIndex >= 0 ? base.substring(0, hashIndex) : base) + raw;
  }

  const baseNoHash = base.split('#')[0];
  const protocolIndex = baseNoHash.indexOf('://');
  if (protocolIndex < 0) {
    return raw;
  }
  const schemeEnd = protocolIndex + 3;
  const pathStart = baseNoHash.indexOf('/', schemeEnd);
  const origin = pathStart < 0 ? baseNoHash : baseNoHash.substring(0, pathStart);
  let basePath = pathStart < 0 ? '/' : baseNoHash.substring(pathStart);

  if (raw.startsWith('/')) {
    return origin + raw;
  }
  if (raw.startsWith('?')) {
    const q = basePath.indexOf('?');
    return origin + (q >= 0 ? basePath.substring(0, q) : basePath) + raw;
  }

  // 相对路径：以 base 所在目录为基准
  const queryIndex = basePath.indexOf('?');
  if (queryIndex >= 0) {
    basePath = basePath.substring(0, queryIndex);
  }
  const lastSlash = basePath.lastIndexOf('/');
  const dir = lastSlash >= 0 ? basePath.substring(0, lastSlash + 1) : '/';
  const merged = dir + raw;
  return origin + normalizePath(merged);
}

/** 折叠 `.` 与 `..` 段 */
function normalizePath(input: string): string {
  const parts = input.split('/');
  const stack: string[] = [];
  for (const part of parts) {
    if (part === '.') {
      continue;
    }
    if (part === '..') {
      if (stack.length > 1) {
        stack.pop();
      }
      continue;
    }
    stack.push(part);
  }
  let out = stack.join('/');
  if (out.length === 0) {
    out = '/';
  }
  if (!out.startsWith('/')) {
    out = '/' + out;
  }
  return out;
}

/** 取出 URL 的 origin（协议 + 主机 + 端口） */
export function originOf(url: string): string {
  const index = url.indexOf('://');
  if (index < 0) {
    return '';
  }
  const schemeEnd = index + 3;
  const slash = url.indexOf('/', schemeEnd);
  return slash < 0 ? url : url.substring(0, slash);
}

/** 模板替换：{kw} {page} {chapterId} {comicId} {url} 等占位符 */
export function applyTemplate(template: string, key: string, value: string): string {
  return template.split('{' + key + '}').join(value);
}

/** HTML 实体反转义（覆盖站点常用的少数实体 + 数字实体） */
export function decodeEntities(input: string): string {
  if (input.indexOf('&') < 0) {
    return input;
  }
  let out = input;
  out = out.split('&nbsp;').join(' ');
  out = out.split('&amp;').join('&');
  out = out.split('&lt;').join('<');
  out = out.split('&gt;').join('>');
  out = out.split('&quot;').join('"');
  out = out.split('&#39;').join('\'');
  out = out.split('&apos;').join('\'');
  const numeric = new RegExp('&#(x?)([0-9a-fA-F]+);', 'g');
  out = out.replace(numeric, (match: string, hex: string, digits: string) => {
    const code = hex === 'x' ? parseInt(digits, 16) : parseInt(digits, 10);
    if (isNaN(code) || code < 0 || code > 0x10ffff) {
      return match;
    }
    return String.fromCharCode(code);
  });
  return out;
}

/** 压缩连续空白，用于标题/作者等展示字段 */
export function compact(input: string): string {
  return input.replace(new RegExp('\\s+', 'g'), ' ').trim();
}

/** 截断过长文本，避免详情页描述撑爆布局 */
export function clampText(input: string, max: number): string {
  if (input.length <= max) {
    return input;
  }
  return input.substring(0, max) + '…';
}

/**
 * 从形如 `/manhua432/` 或 `/comic/index/id/531040` 的地址里抽数字 id。
 *
 * 必须只看路径、且取最长的那串数字：
 * ① 域名里可能带数字（m206.com），按整串 URL 找会把所有条目算成同一个 id，
 *    表现是 ForEach 的 key 全部重复 → 三列网格退化成单列；
 * ② 路径里可能有次要数字（/comic/12345/2.html），取最后一串会取到页码。
 */
export function extractNumericId(url: string): string {
  let path = url;
  const scheme = path.indexOf('://');
  if (scheme >= 0) {
    const slash = path.indexOf('/', scheme + 3);
    path = slash >= 0 ? path.substring(slash) : '/';
  }
  const query = path.indexOf('?');
  if (query >= 0) {
    path = path.substring(0, query);
  }
  const runs = path.match(new RegExp('\\d{2,}', 'g'));
  if (runs !== null && runs.length > 0) {
    let best = runs[0];
    for (let i = 1; i < runs.length; i++) {
      if (runs[i].length > best.length) {
        best = runs[i];
      }
    }
    return best;
  }
  const fallback = url.match(new RegExp('\\d{2,}'));
  return fallback === null ? '' : fallback[0];
}

/**
 * 把 http 升级成 https。
 * 鸿蒙默认拦截明文 HTTP，而不少站点的图片地址仍是 http；
 * 实测这些 CDN 的 https 与 http 返回完全一致，直接升级最省事。
 */
export function toHttps(url: string): string {
  if (url.startsWith('http://')) {
    return 'https://' + url.substring(7);
  }
  return url;
}

/** 章节标题里的数字序号，用于跨源对齐 */
export function chapterNumber(title: string): number {
  const arabic = title.match(new RegExp('(\\d+(?:\\.\\d+)?)'));
  if (arabic !== null) {
    const parsed = parseFloat(arabic[1]);
    if (!isNaN(parsed)) {
      return parsed;
    }
  }
  return -1;
}

/**
 * 章节更新时间压缩成一行短文本，方便塞在章节格子/目录行里。
 * `2026-11-02 01:53:30` → `11-02`；`2023-12-06` → `12-06`；
 * 认不出来的原样返回（最多 10 字），不至于显示成空白。
 */
export function shortTime(raw: string): string {
  const full = raw.match(new RegExp('(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})'));
  if (full !== null) {
    return `${full[2]}-${full[3]}`;
  }
  const short = raw.match(new RegExp('(\\d{1,2})[-/](\\d{1,2})'));
  if (short !== null) {
    return `${short[1]}-${short[2]}`;
  }
  return raw.length > 10 ? raw.substring(0, 10) : raw;
}
