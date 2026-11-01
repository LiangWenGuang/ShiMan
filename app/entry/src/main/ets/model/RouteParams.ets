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
}

export class SwitchParams {
  sourceId: string = '';
  comicId: string = '';
  title: string = '';
  chapterIndex: number = 0;
  chapterTitle: string = '';
}
