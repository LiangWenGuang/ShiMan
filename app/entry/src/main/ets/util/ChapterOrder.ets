import { ChapterBrief } from '../model/Models';
import { chapterNumber } from './Text';

/**
 * 将图源返回的章节列表归一化为阅读顺序：index 0 永远是最早章节。
 * reverse 只描述图源接口的返回方向，不能和页面的正序/倒序显示状态混用。
 * 当标题中至少有两个章节号且方向一致时，以实际章节号方向为准，修正配置填反的图源。
 */
export function normalizeChapterOrder(chapters: ChapterBrief[], sourceReversed: boolean): ChapterBrief[] {
  const ordered = chapters.slice();
  // 只检测方向，不按数值排序，避免把前言、番外等非数字章节错误插入数字章节中。
  const detectedDescending = chapterDirection(ordered);
  const shouldReverse = detectedDescending === null ? sourceReversed : detectedDescending;
  if (shouldReverse) {
    ordered.reverse();
  }
  for (let i = 0; i < ordered.length; i++) {
    ordered[i].index = i;
  }
  return ordered;
}

/** 返回原始列表是否为倒序；null 表示章节号不足或方向不一致，交由图源配置兜底。 */
function chapterDirection(chapters: ChapterBrief[]): boolean | null {
  const numbers: number[] = [];
  for (let i = 0; i < chapters.length; i++) {
    const number = chapterNumber(chapters[i].title);
    if (number >= 0) {
      numbers.push(number);
    }
  }
  if (numbers.length < 2) {
    return null;
  }
  let increasing = true;
  let decreasing = true;
  for (let i = 1; i < numbers.length; i++) {
    if (numbers[i] <= numbers[i - 1]) {
      increasing = false;
    }
    if (numbers[i] >= numbers[i - 1]) {
      decreasing = false;
    }
  }
  if (!increasing && !decreasing) {
    return null;
  }
  return decreasing;
}

/** 详情页只翻转显示副本，阅读器仍使用归一化后的原始索引。 */
export function chaptersForDisplay(chapters: ChapterBrief[], descending: boolean): ChapterBrief[] {
  const displayed = chapters.slice();
  if (descending) {
    displayed.reverse();
  }
  return displayed;
}
