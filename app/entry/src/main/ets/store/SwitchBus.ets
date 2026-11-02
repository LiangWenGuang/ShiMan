/**
 * 换源结果的跨页传递。
 *
 * 换源页点某个候选源后不再自动进阅读器，而是退回作品详情页并应用新源。
 * 但 router.back() 无法直接回传参数，这里用一个模块级单例承载
 * 「待应用的新源」，详情页/阅读器在 onPageShow 里 take() 取走。
 */

export class SwitchPending {
  sourceId: string = '';
  comicId: string = '';
  url: string = '';
  title: string = '';
  /** 新源里对齐到的章节下标（-1 表示不指定） */
  chapterIndex: number = -1;
}

export class SwitchBus {
  private static pending: SwitchPending | null = null;

  static put(value: SwitchPending): void {
    SwitchBus.pending = value;
  }

  static take(): SwitchPending | null {
    const value = SwitchBus.pending;
    SwitchBus.pending = null;
    return value;
  }
}
