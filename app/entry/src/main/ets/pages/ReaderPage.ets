import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceApi, ImageResult } from '../source/SourceApi';
import { SourceRule } from '../rule/Rules';
import { ComicBrief, ComicDetail, ChapterBrief, PageImage, ReadProgress } from '../model/Models';
import { Library } from '../store/Library';
import { SwitchBus } from '../store/SwitchBus';
import { ReaderParams, SwitchParams } from '../model/RouteParams';
import { parseJson, JsonKind } from '../parse/Json';
import { Trace } from '../util/Trace';
import { shortTime } from '../util/Text';
import { RemoteImage } from '../view/RemoteImage';
import { Theme } from '../theme/Theme';

const BG: string = '#080B0F';
const BAR: string = '#151A21';
const TEXT_MAIN: string = Theme.text;
const TEXT_SUB: string = Theme.textSub;
const ACCENT: string = Theme.accent;

/** 跨源续读：书名命中的接管结果 */
class HealResult {
  rule: SourceRule = new SourceRule();
  comicId: string = '';
  url: string = '';
}

@Entry
@Component
struct ReaderPage {
  @State detail: ComicDetail | null = null;
  @State chapterIndex: number = 0;
  @State images: PageImage[] = [];
  @State loading: boolean = true;
  @State error: string = '';
  @State showUi: boolean = true;
  @State showCatalog: boolean = false;
  /** 目录展示顺序，与详情页共用同一偏好 */
  @State chapterDescending: boolean = false;
  @State loadingText: string = '正在取图…';
  @State currentPage: number = 0;
  @State pageOffset: number = 0;

  // web 型图源的取图状态
  @State harvesting: boolean = false;
  @State harvestUrl: string = '';
  private harvestSelector: string = '';
  private harvestExtract: string = '';
  private harvestSettle: number = 1200;
  private webController: webview.WebviewController = new webview.WebviewController();
  /**
   * 取图会话令牌。腾讯这类站点在章节页会发生一次 HTTP 跳转，
   * onPageEnd 会被触发多次；没有这个令牌就会出现并发 runJavaScript，
   * 直接把 Web 控制器打崩（实测表现为 App 闪退，日志里是 JS_ERROR）。
   */
  private harvestToken: number = 0;
  private harvestDone: boolean = false;
  private harvestChapter: ChapterBrief | null = null;

  private params: ReaderParams = new ReaderParams();
  private scroller: Scroller = new Scroller();
  private catalogScroller: Scroller = new Scroller();
  /** 继续阅读要恢复到的页（0 起，-1 表示不恢复） */
  private targetPage: number = -1;
  // 仅对已拿到真实图片比例的目标项恢复页内位置。
  private readyPages: Set<number> = new Set<number>();
  private targetPageOffset: number = 0;
  private restoringPage: boolean = false;
  private restoreTimer: number = -1;
  /** 章节请求令牌：切章时让旧请求无法覆盖新章节。 */
  private chapterToken: number = 0;
  /** 页面重新进入或换源时，使上一轮详情请求失效。 */
  private bootstrapToken: number = 0;
  /** 合并快速滚动产生的进度写入，降低 Preferences 持久化频率。 */
  private progressTimer: number = -1;

  aboutToAppear(): void {
    // router.getParams() 返回的是普通对象，ArkTS 下直接 `as ReaderParams` 强转后
    // 字段可能因为序列化丢失类型；逐个取并兜底，避免继续阅读因为参数错乱直接崩。
    const raw = router.getParams();
    if (raw !== undefined && raw !== null) {
      const p = raw as Record<string, Object>;
      const safe = new ReaderParams();
      safe.sourceId = this.asString(p['sourceId']);
      safe.comicId = this.asString(p['comicId']);
      safe.comicUrl = this.asString(p['comicUrl']);
      const ci = p['chapterIndex'];
      safe.chapterIndex = typeof ci === 'number' ? ci : (parseInt(this.asString(ci), 10) || 0);
      safe.chapterId = this.asString(p['chapterId']);
      const pg = p['page'];
      safe.page = typeof pg === 'number' ? pg : (parseInt(this.asString(pg), 10) || 0);
      const po = p['pageOffset'];
      safe.pageOffset = typeof po === 'number' && po > 0 ? po : 0;
      this.params = safe;
    }
    Trace.write('reader', 'enter source=' + this.params.sourceId +
      ' comicId=' + this.params.comicId + ' bookmarked=' + (this.params.comicUrl.length > 0) +
      ' chapter=' + this.params.chapterIndex + ' chapterId=' + this.params.chapterId);
    this.chapterDescending = Library.get().isChapterDescending();
    this.bootstrap();
  }

  private asString(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }

  /**
   * 从换源页返回：换源不再自动进阅读器，而是退回上一页（详情页或阅读器）后
   * 由上一页接管。阅读器这里接管时重新用新源加载并跳到对齐的章节。
   */
  onPageShow(): void {
    const pending = SwitchBus.take();
    if (pending === null || pending.sourceId.length === 0) {
      return;
    }
    this.params.sourceId = pending.sourceId;
    this.params.comicId = pending.comicId;
    this.params.comicUrl = pending.url;
    this.params.chapterIndex = pending.chapterIndex >= 0 ? pending.chapterIndex : 0;
    this.params.chapterId = '';
    this.bootstrap();
  }

  onPageHide(): void {
    // 离开阅读器时立即落盘最后页，避免延迟写入被页面销毁取消。
    if (this.progressTimer >= 0) {
      clearTimeout(this.progressTimer);
      this.progressTimer = -1;
    }
    // 取图未完成时不写入空页，避免覆盖已有的有效阅读进度。
    if (!this.loading && !this.harvesting && this.images.length > 0) {
      this.saveProgressNow();
    }
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
    this.restoringPage = false;
  }

  private async bootstrap(): Promise<void> {
    const bootstrapToken = ++this.bootstrapToken;
    const registry = SourceRegistry.get();
    let rule: SourceRule | null = registry.find(this.params.sourceId);
    if (rule === null) {
      // 源可能被重命名/移除（多次迭代后，历史里记的 sourceId 会失效）。
      // 用存下的书名在所有启用源里搜一次，命中就接管，让「继续阅读」不至于直接报错。
      Trace.write('reader', 'source missing, try heal by title: ' + this.params.sourceId);
      const healed = await this.healByTitleAcrossSources();
      if (healed === null) {
        this.loading = false;
        this.error = '找不到对应的图源，可能已被移除';
        return;
      }
      rule = healed.rule;
      this.params.sourceId = healed.rule.id;
      this.params.comicId = healed.comicId;
      this.params.comicUrl = healed.url;
    }
    // 从书架/历史直接进阅读器时没有带详情地址，必须自己找回来，
    // 否则只剩 baseUrl+id 的兜底拼接，各站路径不同 -> 必然 404
    let comicUrl = this.params.comicUrl;
    if (comicUrl.length === 0) {
      comicUrl = Library.get().resolveComicUrl(this.params.sourceId, this.params.comicId);
      this.params.comicUrl = comicUrl;
    }
    let detailOutcome = await SourceApi.detail(rule, this.params.comicId, comicUrl);
    if (bootstrapToken !== this.bootstrapToken) {
      return;
    }
    if (!detailOutcome.ok && comicUrl.length > 0) {
      // 记下的地址可能已经过期（站点改版），再按源内约定重试一次
      detailOutcome = await SourceApi.detail(rule, this.params.comicId, '');
      if (bootstrapToken !== this.bootstrapToken) {
        return;
      }
    }
    if (!detailOutcome.ok) {
      // 最后的自救：按书名回源站搜一次，命中同名就把地址纠正过来。
      // 老版本的进度记录没有存地址，这条路径能救回来。
      const healed = await this.healUrlByTitle(rule);
      if (healed.length > 0) {
        this.params.comicUrl = healed;
        detailOutcome = await SourceApi.detail(rule, this.params.comicId, healed);
        if (bootstrapToken !== this.bootstrapToken) {
          return;
        }
      }
    }
    if (!detailOutcome.ok || detailOutcome.value === undefined) {
      this.loading = false;
      this.error = detailOutcome.message;
      return;
    }
    this.detail = detailOutcome.value;
    // 详情地址可能有更新，写回参数，换源与重试都用得上
    this.params.comicUrl = this.detail.url;
    let start = this.params.chapterIndex;
    // 章节列表可能因图源更新而重排：优先按章节 ID，再按保存的标题，最后才用旧序号。
    const saved = Library.get().progress(this.params.sourceId, this.params.comicId);
    let chapterMatched = false;
    if (this.params.chapterId.length > 0) {
      for (let i = 0; i < this.detail.chapters.length; i++) {
        if (this.detail.chapters[i].chapterId === this.params.chapterId) {
          start = i;
          chapterMatched = true;
          break;
        }
      }
    }
    if (!chapterMatched && this.params.chapterId.length > 0 && saved !== null && saved.chapterTitle.length > 0) {
      let matched = false;
      for (let i = 0; i < this.detail.chapters.length; i++) {
        if (this.detail.chapters[i].title === saved.chapterTitle) {
          start = i;
          matched = true;
          break;
        }
      }
      if (!matched) {
        start = saved.chapterIndex;
      }
    }
    const total = this.detail.chapters.length;
    if (start < 0 || start >= total) {
      start = 0;
    }
    this.targetPageOffset = this.params.pageOffset > 0 ? this.params.pageOffset : 0;
    this.targetPage = this.params.page > 0 || this.targetPageOffset > 0 ? this.params.page : -1;
    await this.loadChapter(start);
    this.scrollToTargetPage();
  }

  /**
   * 当存下来的 sourceId 已失效（源被改名/移除）时，用书名在所有启用源里搜一遍，
   * 命中同名/包含的书就接管它的 rule、comicId 和详情地址，让「继续阅读」能续上。
   */
  private async healByTitleAcrossSources(): Promise<HealResult | null> {
    const progress = Library.get().progress(this.params.sourceId, this.params.comicId);
    const title = progress === null ? '' : progress.title;
    if (title.length === 0) {
      return null;
    }
    const sources = SourceRegistry.get().enabled();
    for (let s = 0; s < sources.length; s++) {
      const r = sources[s];
      const outcome = await SourceApi.search(r, title, 1);
      if (!outcome.ok || outcome.value === undefined) {
        continue;
      }
      const items = outcome.value;
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (item.url.length > 0 && (item.title === title || item.title.indexOf(title) >= 0)) {
          Trace.write('reader', 'healed across sources: ' + r.id + ' -> ' + item.url);
          const result = new HealResult();
          result.rule = r;
          result.comicId = item.comicId;
          result.url = item.url;
          return result;
        }
      }
    }
    return null;
  }

  /** 详情地址未知时，用书名回源站搜一次，返回最匹配的详情地址 */
  private async healUrlByTitle(rule: SourceRule): Promise<string> {    const progress = Library.get().progress(this.params.sourceId, this.params.comicId);
    const title = progress === null ? '' : progress.title;
    if (title.length === 0) {
      return '';
    }
    this.loadingText = '正在重新定位这本漫画…';
    const outcome = await SourceApi.search(rule, title, 1);
    if (!outcome.ok || outcome.value === undefined) {
      return '';
    }
    const items: ComicBrief[] = outcome.value;
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.url.length > 0 && (item.title === title || item.title.indexOf(title) >= 0)) {
        return item.url;
      }
    }
    return '';
  }

  private async loadChapter(index: number): Promise<void> {
    if (this.detail === null) {
      return;
    }
    const chapters = this.detail.chapters;
    if (index < 0 || index >= chapters.length) {
      promptAction.showToast({ message: index < 0 ? '已经是第一章' : '已经是最后一章' });
      return;
    }
    const registry = SourceRegistry.get();
    const rule: SourceRule | null = registry.find(this.params.sourceId);
    if (rule === null) {
      this.error = '图源已失效';
      return;
    }
    const token = ++this.chapterToken;
    this.readyPages.clear();
    this.loading = true;
    this.error = '';
    this.images = [];
    this.chapterIndex = index;
    this.currentPage = 0;
    this.pageOffset = 0;
    this.loadingText = '正在取图…';
    this.harvestToken++;
    this.harvestDone = false;
    this.harvesting = false;
    this.harvestUrl = '';
    this.harvestChapter = null;

    const chapter: ChapterBrief = chapters[index];
    const outcome = await SourceApi.images(rule, this.params.comicId, chapter);
    if (token !== this.chapterToken) {
      return;
    }
    if (!outcome.ok || outcome.value === undefined) {
      this.loading = false;
      this.error = outcome.message;
      return;
    }
    const result: ImageResult = outcome.value;
    if (result.needsHarvest) {
      // 交给内嵌 Web 组件执行站点脚本后再取图
      this.harvestSelector = result.readySelector;
      this.harvestExtract = result.extract;
      this.harvestSettle = result.settleMs;
      this.loadingText = '正在解析图源页面…';
      this.harvestChapter = chapter;
      this.harvestUrl = result.harvestUrl;
      this.harvesting = true;
      this.loading = false;
      Trace.write('harvest', 'start ' + result.harvestUrl);
      const token = this.harvestToken;
      // 看门狗：站点卡住时不能让用户一直看转圈
      setTimeout(() => {
        if (token === this.harvestToken && !this.harvestDone) {
          this.harvestDone = true;
          this.finishHarvest('解析图源页面超时，可尝试换源');
        }
      }, 25000);
      return;
    }
    this.loading = false;
    this.images = result.images;
    this.saveProgress();
  }

  /** Web 页面加载完成后，注入脚本把图片地址取回来 */
  private async extractFromWeb(token: number): Promise<void> {
    // 令牌不匹配或本会话已结束 —— 说明这是一次跳转产生的重复回调，直接丢弃
    if (token !== this.harvestToken || this.harvestDone) {
      return;
    }
    this.harvestDone = true;
    Trace.write('harvest', 'extract begin token=' + token);
    try {
      const attribute = this.harvestExtract.startsWith('attr:')
        ? this.harvestExtract.substring(5) : '';
      const selectorLiteral = JSON.stringify(this.harvestSelector);
      const attrLiteral = JSON.stringify(attribute);
      const script =
        '(function(){try{' +
        'var out=[];var nodes=document.querySelectorAll(' + selectorLiteral + ');' +
        'for(var i=0;i<nodes.length;i++){' +
        'var n=nodes[i];' +
        'var v=' + (attribute.length > 0
          ? 'n.getAttribute(' + attrLiteral + ')||n.getAttribute("data-src")||n.getAttribute("src")'
          : 'n.getAttribute("data-src")||n.getAttribute("src")') + ';' +
        'if(v&&out.indexOf(v)<0)out.push(v);}' +
        'return JSON.stringify(out);' +
        '}catch(e){return "[]";}})()';

      const raw = await this.webController.runJavaScript(script);
      const text: string = typeof raw === 'string' ? raw : '';
      Trace.write('harvest', 'js returned len=' + text.length);
      if (text.length === 0) {
        this.finishHarvest('图源页面没有返回数据，可尝试换源');
        return;
      }
      Trace.write('harvest', 'parse begin');
      const parsed = parseJson(text);
      const urls: string[] = [];
      if (parsed.kind === JsonKind.Array) {
        for (let i = 0; i < parsed.items.length; i++) {
          const value = parsed.items[i].asString();
          if (value.length > 0) {
            urls.push(value);
          }
        }
      }
      Trace.write('harvest', 'parsed urls=' + urls.length);
      // 过滤站点图标/分享图/封面这类噪声；正文章节页不可能只有一张图
      const noise = new RegExp('logo|icon|avatar|share|cover|banner|placeholder|loading', 'i');
      const cleaned: string[] = [];
      for (let i = 0; i < urls.length; i++) {
        if (!noise.test(urls[i])) {
          cleaned.push(urls[i]);
        }
      }
      if (cleaned.length < 2) {
        this.finishHarvest('该图源未能提取到正文图片，可尝试换源');
        return;
      }
      const images: PageImage[] = [];
      const referer = this.harvestChapter === null ? '' : this.harvestChapter.url;
      for (let i = 0; i < cleaned.length; i++) {
        const image = new PageImage();
        image.url = cleaned[i].startsWith('//') ? 'https:' + cleaned[i] : cleaned[i];
        image.referer = referer;
        images.push(image);
      }
      Trace.write('harvest', 'built images=' + images.length);
      // 先摘掉 Web 再灌数据：WebView 和大批图片同时存在容易把内存顶爆
      this.harvesting = false;
      this.harvestUrl = '';
      this.images = images;
      Trace.write('harvest', 'done images=' + images.length);
      this.saveProgress();
      this.scrollToTargetPage();
    } catch (error) {
      Trace.write('harvest', 'exception ' + String(error));
      this.finishHarvest('取图脚本执行失败，可尝试换源');
    }
  }

  private finishHarvest(message: string): void {
    Trace.write('harvest', 'fail ' + message);
    this.harvesting = false;
    this.harvestUrl = '';
    this.error = message;
  }

  private saveProgress(): void {
    if (this.detail === null) {
      return;
    }
    const chapter = this.detail.chapters[this.chapterIndex];
    if (chapter === undefined) {
      return;
    }
    if (this.progressTimer >= 0) {
      clearTimeout(this.progressTimer);
    }
    this.progressTimer = setTimeout(() => {
      this.progressTimer = -1;
      this.saveProgressNow();
    }, 300);
  }

  private saveProgressNow(): void {
    if (this.detail === null || this.loading || this.harvesting || this.images.length === 0 || this.restoringPage || this.targetPage >= 0) {
      return;
    }
    const chapter = this.detail.chapters[this.chapterIndex];
    if (chapter === undefined) {
      return;
    }
    const progress = new ReadProgress();
    progress.sourceId = this.detail.sourceId;
    progress.comicId = this.detail.comicId;
    progress.title = this.detail.title;
    progress.cover = this.detail.cover;
    progress.url = this.detail.url;
    progress.chapterId = chapter.chapterId;
    progress.chapterIndex = this.chapterIndex;
    progress.chapterTitle = chapter.title;
    progress.page = this.currentPage;
    progress.pageOffset = this.pageOffset;
    Library.get().saveProgress(progress);
  }

  /** 继续阅读时滚到上次看到的页（0 起），只消费一次 */
  private scrollToTargetPage(): void {
    if (this.targetPage < 0 || this.images.length === 0) {
      return;
    }
    const page = this.targetPage < this.images.length ? this.targetPage : this.images.length - 1;
    this.targetPage = page;
    let sizesReady = true;
    for (let index = Math.max(0, page - 2); index <= page; index++) {
      if (!this.readyPages.has(index)) sizesReady = false;
    }
    if (!sizesReady) {
      this.currentPage = page;
      this.restoringPage = true;
      const token = this.chapterToken;
      this.restoreTimer = setTimeout(() => {
        if (token === this.chapterToken) this.scroller.scrollToIndex(page, false, ScrollAlign.START);
        this.restoreTimer = -1;
      }, 100);
      return;
    }
    const offset = this.targetPageOffset;
    this.currentPage = page;
    this.pageOffset = offset;
    this.restoringPage = true;
    const token = this.chapterToken;
    this.restoreTimer = setTimeout(() => {
      if (token !== this.chapterToken) {
        this.restoringPage = false;
        this.restoreTimer = -1;
        return;
      }
      this.scroller.scrollToIndex(page, false, ScrollAlign.START);
      if (offset > 0) {
        // scrollToIndex 之后再补页内偏移；scrollBy 的单位为 vp（SDK list.d.ts）。
        this.restoreTimer = setTimeout(() => {
          if (token === this.chapterToken) {
            this.scroller.scrollBy(0, offset);
            this.targetPage = -1;
            this.targetPageOffset = 0;
          }
          this.restoringPage = false;
          this.restoreTimer = -1;
        }, 80);
      } else {
        this.targetPage = -1;
        this.targetPageOffset = 0;
        this.restoringPage = false;
        this.restoreTimer = -1;
      }
    }, 120);
  }

  /** 目录按当前排序显示，翻的是副本；上一章/下一章仍按原始章节顺序 */
  private orderedChapters(): ChapterBrief[] {
    if (this.detail === null) {
      return [];
    }
    const items: ChapterBrief[] = this.detail.chapters.slice();
    if (this.chapterDescending) {
      items.reverse();
    }
    return items;
  }

  private openCatalog(): void {
    this.showCatalog = true;
    // 等目录布局完成再滚，直接滚会因为 List 还没测量而落到错位置
    setTimeout(() => {
      this.scrollCatalogToCurrent();
    }, 80);
  }

  /** 把目录滚到当前正在读的那一章，避免上千章时从头翻 */
  private scrollCatalogToCurrent(): void {
    if (this.detail === null) {
      return;
    }
    const total = this.detail.chapters.length;
    const position = this.chapterDescending ? total - 1 - this.chapterIndex : this.chapterIndex;
    if (position <= 0 || position >= total) {
      return;
    }
    try {
      this.catalogScroller.scrollToIndex(position);
    } catch (error) {
      // 目录尚未布局完成时可能越界，忽略即可
    }
  }

  private toggleChapterOrder(): void {
    const next = !this.chapterDescending;
    this.chapterDescending = next;
    Library.get().setChapterDescending(next);
    this.scrollCatalogToCurrent();
  }

  private openSwitch(): void {
    if (this.detail === null) {
      return;
    }
    const params: SwitchParams = new SwitchParams();
    params.sourceId = this.detail.sourceId;
    params.comicId = this.detail.comicId;
    params.title = this.detail.title;
    params.chapterIndex = this.chapterIndex;
    const current = this.detail.chapters[this.chapterIndex];
    params.chapterTitle = current === undefined ? '' : current.title;
    router.pushUrl({ url: 'pages/SourceSwitchPage', params: params });
  }

  @Builder
  topBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([TEXT_MAIN])
          .margin({ right: 4 })
        Text('返回')
          .fontSize(Theme.fsBody)
          .fontColor(TEXT_MAIN)
      }
      .width(76)
      .height(44)
      .onClick(() => {
        router.back();
      })

      Column() {
        Text(this.detail === null ? '' : this.detail.title)
          .fontSize(Theme.fsBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detail === null || this.chapterIndex < 0 ||
          this.chapterIndex >= this.detail.chapters.length
          ? '' : this.detail.chapters[this.chapterIndex].title)
          .fontSize(Theme.fsCaption)
          .fontColor(TEXT_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Row() {
        Text('换源')
          .fontSize(Theme.fsLabel)
          .fontWeight(FontWeight.Medium)
          .fontColor(ACCENT)
          .height(32)
          .padding({ left: 15, right: 15 })
          .backgroundColor(Theme.accentDim)
          .borderRadius(Theme.radiusPill)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openSwitch();
          })
      }
      .width(76)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(58)
    .padding({ left: Theme.gapM, right: Theme.gapL })
    .backgroundColor(BAR)
  }

  @Builder
  barButton(icon: Resource, label: string, action: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([TEXT_MAIN])
      Text(label)
        .fontSize(Theme.fsMicro)
        .fontColor(TEXT_SUB)
        .margin({ top: 3 })
    }
    .layoutWeight(1)
    .height(62)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      action();
    })
  }

  /** 阅读进度条：贴在底栏上方，1px 的高度也能看出还剩多少 */
  @Builder
  pageProgress() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .height(2)
        .width(this.images.length === 0 ? '0%' :
          `${Math.round((this.currentPage + 1) / this.images.length * 100)}%`)
        .backgroundColor(ACCENT)
        .borderRadius(1)
    }
    .width('100%')
    .height(2)
    .backgroundColor('#232C38')
  }

  @Builder
  bottomBar() {
    Column() {
      this.pageProgress()
      Row() {
        this.barButton($r('sys.symbol.chevron_left'), '上一章', () => {
          this.loadChapter(this.chapterIndex - 1);
        })
        this.barButton($r('sys.symbol.list_bullet'), '目录', () => {
          this.openCatalog();
        })
        this.barButton($r('sys.symbol.arrow_clockwise'), '换源', () => {
          this.openSwitch();
        })
        this.barButton($r('sys.symbol.chevron_right'), '下一章', () => {
          this.loadChapter(this.chapterIndex + 1);
        })
      }
      .width('100%')
      .height(62)
    }
    .width('100%')
    // 必须给底栏底色：阅读页是沉浸式的，不铺底色的话漫画会透上来把图标糊掉
    .backgroundColor(BAR)
  }

  @Builder
  catalogOverlay() {
    Column() {
      Row() {
        Text('目录')
          .fontSize(Theme.fsHeadline)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Text(`${this.chapterIndex + 1} / ${this.detail === null ? 0 : this.detail.chapters.length}`)
          .fontSize(Theme.fsCaption)
          .fontColor(TEXT_SUB)
          .margin({ right: Theme.gapS })
        Text(this.chapterDescending ? '倒序 ↓' : '正序 ↑')
          .fontSize(Theme.fsLabel)
          .fontWeight(FontWeight.Medium)
          .fontColor(ACCENT)
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor(Theme.accentDim)
          .borderRadius(Theme.radiusPill)
          .margin({ right: Theme.gapM })
          .onClick(() => {
            this.toggleChapterOrder();
          })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([TEXT_SUB])
          .onClick(() => {
            this.showCatalog = false;
          })
      }
      .width('100%')
      .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapL, bottom: Theme.gapM })

      Divider().color(Theme.line)

      List({ scroller: this.catalogScroller }) {
        ForEach(this.orderedChapters(), (chapter: ChapterBrief) => {
          ListItem() {
            Row() {
              Text(chapter.title)
                .fontSize(chapter.index === this.chapterIndex ? Theme.fsBody : Theme.fsLabel + 1)
                .fontWeight(chapter.index === this.chapterIndex ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(chapter.index === this.chapterIndex ? ACCENT : TEXT_MAIN)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (chapter.time.length > 0) {
                Text(shortTime(chapter.time))
                  .fontSize(Theme.fsMicro)
                  .fontColor(Theme.textDim)
                  .margin({ left: 8 })
              }
              if (chapter.index === this.chapterIndex) {
                Text('阅读中')
                  .fontSize(Theme.fsMicro)
                  .fontColor(ACCENT)
                  .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                  .backgroundColor(Theme.accentDim)
                  .borderRadius(Theme.radiusS - 2)
                  .margin({ left: 8 })
              }
            }
            .width('100%')
            .height(48)
            .padding({ left: Theme.gapM, right: Theme.gapM })
            .borderRadius(Theme.radiusS)
            .backgroundColor(chapter.index === this.chapterIndex ? Theme.accentDim : Color.Transparent)
            .onClick(() => {
              this.showCatalog = false;
              this.loadChapter(chapter.index);
            })
          }
          .padding({ left: Theme.gapS, right: Theme.gapS })
        }, (chapter: ChapterBrief) => `c_${chapter.chapterId}_${chapter.index}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('92%')
    .height('100%')
    .backgroundColor('#141A22')
  }

  @Builder
  pageList() {
    List({ scroller: this.scroller }) {
      ForEach(this.images, (image: PageImage, index: number) => {
        ListItem() {
          Column() {
            RemoteImage({
              url: image.url,
              referer: image.referer,
              // 只保留当前页前后两页的 PixelMap，避免长章节一次占满内存。
              active: Math.abs(index - this.currentPage) <= 2,
              onReady: (ratio: number) => {
                this.onReaderImageReady(index, ratio);
              },
              natural: true
            })
          }
          .width('100%')
          .onClick(() => {
            this.showUi = !this.showUi;
          })
        }
      }, (image: PageImage, index: number) => `${index}_${image.url}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .onScrollIndex((first: number) => {
      // 恢复期间首屏仍可能报告旧索引，不能因此关闭目标页的图片加载。
      if (this.restoringPage) return;
      if (first !== this.currentPage) {
        this.currentPage = first;
        this.updatePageOffset(first);
        this.saveProgress();
      }
    })
    .onScroll(() => {
      if (!this.restoringPage) {
        // 以当前可见项的真实矩形为准，避免跨页时用 delta 累加造成漂移。
        this.updatePageOffset(this.currentPage);
        this.saveProgress();
      }
    })
  }

  private updatePageOffset(index: number): void {
    if (this.restoringPage) {
      return;
    }
    try {
      const rect = this.scroller.getItemRect(index);
      this.pageOffset = Math.max(0, -rect.y);
    } catch (error) {
      // 条目尚未完成布局时保留上次值，避免异常打断滚动。
    }
  }

  private onReaderImageReady(index: number, ratio: number): void {
    this.readyPages.add(index);
    if (this.targetPage < 0 || index > this.targetPage) {
      return;
    }
    if (ratio <= 0 && index === this.targetPage) {
      // 目标页加载失败时保留页面可用状态，用户点击重试后再重新恢复。
      this.targetPage = -1;
      this.targetPageOffset = 0;
      this.restoringPage = false;
      return;
    }
    // 目标页拿到真实比例后再校准，避免网络解码前按占位高度恢复产生偏移。
    this.scrollToTargetPage();
  }

  build() {
    Stack() {
      Column() {
        this.pageList()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)

      // 无头取图：Web 全屏渲染站点页面，被上层不透明的加载遮罩挡住，用户看不到
      if (this.harvesting && this.harvestUrl.length > 0) {
        Web({ src: this.harvestUrl, controller: this.webController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .zoomAccess(false)
          .width('100%')
          .height('100%')
          .onPageEnd(() => {
            const token = this.harvestToken;
            Trace.write('harvest', 'pageEnd done=' + this.harvestDone);
            if (this.harvestDone) {
              return;
            }
            setTimeout(() => {
              this.extractFromWeb(token);
            }, this.harvestSettle);
          })
      }

      if (this.loading || this.harvesting) {
        Column() {
          LoadingProgress().width(34).height(34).color(ACCENT)
          Text(this.loadingText)
            .fontSize(Theme.fsCaption)
            .fontColor(TEXT_SUB)
            .margin({ top: Theme.gapM })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(BG)
      } else if (this.error.length > 0) {
        Column() {
          Text(this.error)
            .fontSize(Theme.fsBody)
            .fontColor(TEXT_SUB)
            .textAlign(TextAlign.Center)
            .lineHeight(22)
            .padding({ left: 32, right: 32 })
          Row() {
            Button('重试')
              .fontSize(Theme.fsLabel)
              .height(40)
              .padding({ left: 24, right: 24 })
              .backgroundColor(Theme.surfaceHi)
              .fontColor(ACCENT)
              .borderRadius(Theme.radiusPill)
              .onClick(() => {
                this.loadChapter(this.chapterIndex);
              })
            Button('换源')
              .fontSize(Theme.fsLabel)
              .height(40)
              .padding({ left: 24, right: 24 })
              .margin({ left: Theme.gapM })
              .backgroundColor(Theme.surfaceHi)
              .fontColor(ACCENT)
              .borderRadius(Theme.radiusPill)
              .onClick(() => {
                this.openSwitch();
              })
          }
          .margin({ top: Theme.gapXl })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(BG)
      }

      if (this.showUi && !this.loading && !this.harvesting && this.images.length > 0) {
        // 控制栏铺满屏但设为 Transparent 命中测试：
        // 子节点（按钮）正常响应，同时不阻塞下层的列表滚动手势。
        Column() {
          this.topBar()
          Blank()
          Row() {
            Text(`第 ${this.chapterIndex + 1} / ${this.detail === null ? 0 : this.detail.chapters.length} 话`)
              .fontSize(Theme.fsCaption)
              .fontColor(TEXT_SUB)
              .margin({ left: Theme.gapL })
            Blank()
            Text(`${this.currentPage + 1} / ${this.images.length} 页`)
              .fontSize(Theme.fsCaption)
              .fontColor(TEXT_SUB)
              .margin({ right: Theme.gapL })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .backgroundColor(BAR)
          this.bottomBar()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      if (this.showCatalog && this.detail !== null) {
        Row() {
          Column()
            .width('8%')
            .height('100%')
            .backgroundColor('#99000000')
            .onClick(() => {
              this.showCatalog = false;
            })
          this.catalogOverlay()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
