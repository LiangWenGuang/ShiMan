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
    while (m) {
      if (m.length > 1 && m[1]) {
        out.push(m[1]);
      } else if (m[0]) {
        out.push(m[0]);
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
  return s
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_m, n) => String.fromCharCode(parseInt(n, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_m, h) => String.fromCharCode(parseInt(h, 16)));
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
    if (!(p in rec)) {
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
    if (!(p in rec)) {
      return [];
    }
    cur = rec[p] as Object;
  }
  if (Array.isArray(cur)) {
    return cur as Object[];
  }
  return [];
}
