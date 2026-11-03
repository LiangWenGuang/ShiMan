/** 页面路由参数：统一类型，避免各页面用裸对象互传导致字段丢失。 */

export class DetailParams {
  sourceId: string = '';
  comicId: string = '';
  url: string = '';
  title: string = '';
}

export class ReaderParams {
  sourceId: string = '';
  comicId: string = '';
  /** 详情页地址，换源与目录回跳都要用 */
  comicUrl: string = '';
  chapterIndex: number = 0;
  /** 从书架/历史进入时直接定位的章节 id */
  chapterId: string = '';
  /** 从书架/历史继续阅读时，恢复到这一页（0 起） */
  page: number = 0;
  /** 继续阅读时恢复到当前页内的偏移（vp）。 */
  pageOffset: number = 0;
}

export class SwitchParams {
  sourceId: string = '';
  comicId: string = '';
  title: string = '';
  chapterIndex: number = 0;
  chapterTitle: string = '';
}
