/**
 * 全局数据模型。
 *
 * 注意：这里用 class 而不是 interface —— ArkTS 里 interface 只是类型，
 * 不能 `new`，而我们的解析层需要大量构造实例。用类还有一个好处：
 * 每个字段都有确定性初值，页面拿到的对象不会出现 undefined 字段。
 */

/** 图源列表里的一条漫画（轻量，用于搜索/分类/首页） */
export class ComicBrief {
  sourceId: string = '';
  /** 源内唯一标识，可为 url、数字 id 或 slug */
  comicId: string = '';
  title: string = '';
  cover: string = '';
  author: string = '';
  latest: string = '';
  /** 详情页绝对地址，供详情与换源使用 */
  url: string = '';
}

/** 章节条目 */
export class ChapterBrief {
  chapterId: string = '';
  title: string = '';
  /** 章节页绝对地址 */
  url: string = '';
  /** 在源内的顺序，从 0 开始 */
  index: number = 0;
}

/** 漫画详情 */
export class ComicDetail {
  sourceId: string = '';
  comicId: string = '';
  title: string = '';
  cover: string = '';
  author: string = '';
  description: string = '';
  status: string = '';
  tags: string[] = [];
  chapters: ChapterBrief[] = [];
  url: string = '';
}

/** 阅读中的页面图片 */
export class PageImage {
  url: string = '';
  referer: string = '';
}

/** 书架条目 */
export class ShelfItem {
  sourceId: string = '';
  comicId: string = '';
  title: string = '';
  cover: string = '';
  author: string = '';
  url: string = '';
  updatedAt: number = 0;
}

/** 阅读进度 */
export class ReadProgress {
  sourceId: string = '';
  comicId: string = '';
  title: string = '';
  cover: string = '';
  chapterId: string = '';
  chapterIndex: number = 0;
  chapterTitle: string = '';
  page: number = 0;
  updatedAt: number = 0;
}

/** 跨源换源的候选 */
export class SwitchCandidate {
  sourceId: string = '';
  sourceName: string = '';
  comicId: string = '';
  title: string = '';
  cover: string = '';
  author: string = '';
  url: string = '';
  chapterCount: number = 0;
  latestTitle: string = '';
  /** 标题与原名的一致度 0..1 */
  similarity: number = 0;
  /** 已按章节标题/序号对齐到的目标章 */
  alignedChapterIndex: number = 0;
  alignedChapterTitle: string = '';
  /** 详细失败原因（加载详情失败时） */
  error: string = '';
}

/** 统一结果包装，避免到处 try/catch 后丢失错误上下文 */
export class Outcome<T> {
  ok: boolean;
  value?: T;
  message: string;

  private constructor(ok: boolean, value: T | undefined, message: string) {
    this.ok = ok;
    this.value = value;
    this.message = message;
  }

  static success<T>(value: T): Outcome<T> {
    return new Outcome<T>(true, value, '');
  }

  static failure<T>(message: string): Outcome<T> {
    return new Outcome<T>(false, undefined, message);
  }
}
