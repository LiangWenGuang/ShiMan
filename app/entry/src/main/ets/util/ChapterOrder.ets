import { ChapterBrief, ComicDetail } from '../model/Models';

/**
 * 章节内在阅读顺序（与「目录正序/倒序展示」完全独立）。
 * 只有足够可信的章节编号趋势才覆盖图源 reverse；混乱、无编号时沿用规则。
 * 不对列表整体按数字排序，以保留番外篇和特别篇的相对位置。
 */
export function normalizeChapterOrder(chapters: ChapterBrief[], sourceReversed: boolean): ChapterBrief[] {
  const descending = detectChapterDirection(chapters);
  return reindexChapters(chapters, descending === null ? sourceReversed : descending);
}

/** 为当前漫画纠正阅读方向：返回新章节实例，避免修改已经绑定到 UI 的旧条目。 */
export function flipChapterOrder(chapters: ChapterBrief[]): ChapterBrief[] {
  return reindexChapters(chapters, true);
}

function reindexChapters(chapters: ChapterBrief[], reversed: boolean): ChapterBrief[] {
  const from: ChapterBrief[] = chapters.slice();
  if (reversed) {
    from.reverse();
  }
  const result: ChapterBrief[] = [];
  for (let i = 0; i < from.length; i++) {
    const item = new ChapterBrief();
    item.chapterId = from[i].chapterId;
    item.title = from[i].title;
    item.url = from[i].url;
    item.time = from[i].time;
    item.index = i;
    result.push(item);
  }
  return result;
}

/** 将简单中文章节编号转换为数字：第一话、第二十回、第一百零三章。 */
function chineseNumber(raw: string): number {
  const map: string = '零〇一二两三四五六七八九';
  let total = 0;
  let digit = 0;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw.charAt(i);
    if (ch === '十' || ch === '百' || ch === '千') {
      const unit = ch === '十' ? 10 : (ch === '百' ? 100 : 1000);
      total += (digit === 0 ? 1 : digit) * unit;
      digit = 0;
    } else {
      const pos = map.indexOf(ch);
      if (pos < 0) {
        return -1;
      }
      if (ch === '零' || ch === '〇') digit = 0;
      else if (ch === '一') digit = 1;
      else if (ch === '二' || ch === '两') digit = 2;
      else if (ch === '三') digit = 3;
      else if (ch === '四') digit = 4;
      else if (ch === '五') digit = 5;
      else if (ch === '六') digit = 6;
      else if (ch === '七') digit = 7;
      else if (ch === '八') digit = 8;
      else if (ch === '九') digit = 9;
    }
  }
  return total + digit;
}

/**
 * 只认明确的章节编号，不把卷数、更新日期、特别篇、标题中的普通数字作为序号。
 * 数字型标题支持第 12 话 / 12话 / 第十二回 / Chapter 12 / EP.12 / 12。
 */
export function chapterOrderNumber(title: string): number {
  const t = title.replace(/[０-９]/g, (v: string): string => String(v.charCodeAt(0) - 65296)).trim();
  if (/(番外|外传|特典|特别|预告|序章|序言|前言|后记|附录|公告|插画|vol\.?\s*\d|第\s*\d+\s*卷)/i.test(t)) {
    return -1;
  }
  const labeled = t.match(/第\s*(\d+(?:\.\d+)?)\s*[话話回章节節集期]/);
  if (labeled !== null) {
    return parseFloat(labeled[1]);
  }
  const cn = t.match(/第\s*([零〇一二两三四五六七八九十百千]+)\s*[话話回章节節集期]/);
  if (cn !== null) {
    return chineseNumber(cn[1]);
  }
  // 更新日期 2026-11-14 不是第 2026 章，日期本身不参加趋势投票。
  if (/^\d{4}[-\\/年]\d{1,2}[-\\/月]/.test(t)) return -1;
  const bare = t.match(/^(?:\s*(?:chapter|episode|ch\.?|ep\.?)\s*#?\s*)?(\d+(?:\.\d+)?)(?:\s*[话話回章节節集期]|\s*[.、:：_-]|\s*$)/i);
  if (bare !== null) {
    return parseFloat(bare[1]);
  }
  const prefixed = t.match(/^(?:chapter|episode|ch\.?|ep\.?)\s*#?\s*(\d+(?:\.\d+)?)/i);
  if (prefixed !== null) {
    return parseFloat(prefixed[1]);
  }
  return -1;
}

/**
 * true: 原列表由新到旧；false: 旧到新；null: 无把握。
 * 多数投票容忍重复编号、番外与单次跳号，避免「一处异常」导致整站配置反转。
 */
export function detectChapterDirection(chapters: ChapterBrief[]): boolean | null {
  let previous = -1;
  let asc = 0;
  let desc = 0;
  let extracted = 0;
  for (let i = 0; i < chapters.length; i++) {
    const current = chapterOrderNumber(chapters[i].title);
    if (current < 0) {
      continue;
    }
    extracted++;
    if (previous >= 0) {
      const delta = current - previous;
      // 大跳跃常来自卷号重置、列表分页拼接；忽略而非误判为相反方向。
      if (delta > 0 && delta <= 50) {
        asc++;
      } else if (delta < 0 && delta >= -50) {
        desc++;
      }
    }
    previous = current;
  }
  const votes = asc + desc;
  if (extracted < 2 || votes === 0) {
    return null;
  }
  // 两个有编号的章节也能判断；多章节要求至少 2 次投票且显著多数。
  if (extracted > 2 && votes < 2) {
    return null;
  }
  if (asc >= 2 && asc >= desc * 3) {
    return false;
  }
  if (desc >= 2 && desc >= asc * 3) {
    return true;
  }
  if (extracted === 2 && votes === 1) {
    return desc === 1;
  }
  return null;
}

/** 新建详情实例触发 ArkUI @State 更新；避免直接修改旧章节数组导致 UI 不刷新。 */
export function flippedComicDetail(detail: ComicDetail): ComicDetail {
  const result = new ComicDetail();
  result.sourceId = detail.sourceId;
  result.comicId = detail.comicId;
  result.title = detail.title;
  result.cover = detail.cover;
  result.author = detail.author;
  result.description = detail.description;
  result.status = detail.status;
  result.tags = detail.tags.slice();
  result.url = detail.url;
  result.chapters = flipChapterOrder(detail.chapters);
  return result;
}

/** 通过章节标识恢复阅读进度，避免图源重排后旧 index 指向另一章。 */
export function findChapterIndex(chapters: ChapterBrief[], id: string, title: string, fallback: number): number {
  if (id.length > 0 && title.length > 0) {
    for (let i = 0; i < chapters.length; i++) {
      if (chapters[i].chapterId === id && chapters[i].title === title) {
        return i;
      }
    }
  }
  if (id.length > 0) {
    for (let i = 0; i < chapters.length; i++) {
      if (chapters[i].chapterId === id) {
        return i;
      }
    }
  }
  if (title.length > 0) {
    for (let i = 0; i < chapters.length; i++) {
      if (chapters[i].title === title) {
        return i;
      }
    }
  }
  return fallback >= 0 && fallback < chapters.length ? fallback : 0;
}

/** 目录界面翻转展示副本，不改变阅读章节的 index 与上一/下一章方向。 */
export function chaptersForDisplay(chapters: ChapterBrief[], descending: boolean): ChapterBrief[] {
  const displayed = chapters.slice();
  if (descending) {
    displayed.reverse();
  }
  return displayed;
}
