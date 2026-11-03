import { router, promptAction } from '@kit.ArkUI';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceApi } from '../source/SourceApi';
import { SourceRule } from '../rule/Rules';
import { ComicDetail, ChapterBrief, ShelfItem, ReadProgress } from '../model/Models';
import { Library } from '../store/Library';
import { DetailParams, ReaderParams, SwitchParams } from '../model/RouteParams';
import { SwitchBus, SwitchPending } from '../store/SwitchBus';
import { RemoteImage } from '../view/RemoteImage';
import { Theme } from '../theme/Theme';
import { shortTime } from '../util/Text';

/** 章节一次渲染多少条，避免上千章一次性铺开 */
const CHAPTER_WINDOW_STEP: number = 120;

@Entry
@Component
struct DetailPage {
  @State detail: ComicDetail | null = null;
  @State loading: boolean = true;
  @State error: string = '';
  @State onShelf: boolean = false;
  @State favorited: boolean = false;
  @State descExpanded: boolean = false;
  @State chapterWindow: number = CHAPTER_WINDOW_STEP;
  @State chapterDescending: boolean = false;
  /** 章节目录每行几列（1 或 2），可切换并持久化 */
  @State chapterColumns: number = 2;
  @State progressHint: string = '';
  @State resumeIndex: number = 0;
  /** 图源站点地址，作为封面下载 Referer */
  @State sourceBase: string = '';
  @State sourceName: string = '';
  private params: DetailParams = new DetailParams();
  /** 换源后要对齐到的章节下标（-1 表示无） */
  private switchAlignedIndex: number = -1;

  aboutToAppear(): void {
    const raw = router.getParams() as DetailParams;
    if (raw !== undefined && raw !== null) {
      this.params = raw;
    }
    this.chapterDescending = Library.get().isChapterDescending();
    this.chapterColumns = Library.get().chapterColumns();
    this.load();
  }

  /**
   * 从阅读器返回时刷新进度：详情页只在进入时读过一次进度，
   * 不刷新的话「继续阅读」会一直停在旧章节。
   */
  onPageShow(): void {
    this.chapterDescending = Library.get().isChapterDescending();
    this.chapterColumns = Library.get().chapterColumns();
    const pending = SwitchBus.take();
    if (pending !== null && pending.sourceId.length > 0 && pending.sourceId !== this.params.sourceId) {
      this.applySwitch(pending);
      return;
    }
    this.refreshProgress();
  }

  /** 从换源页返回：把新源带回来并重新加载 */
  private applySwitch(pending: SwitchPending): void {
    this.params.sourceId = pending.sourceId;
    this.params.comicId = pending.comicId;
    this.params.url = pending.url;
    this.params.title = pending.title;
    this.switchAlignedIndex = pending.chapterIndex >= 0 ? pending.chapterIndex : -1;
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    const registry = SourceRegistry.get();
    const rule: SourceRule | null = registry.find(this.params.sourceId);
    if (rule === null) {
      this.loading = false;
      this.error = '该图源已被移除，请换源重试';
      return;
    }
    this.sourceBase = rule.baseUrl;
    this.sourceName = rule.name;
    const outcome = await SourceApi.detail(rule, this.params.comicId, this.params.url);
    this.loading = false;
    if (!outcome.ok || outcome.value === undefined) {
      this.error = outcome.message;
      return;
    }
    this.detail = outcome.value;
    this.onShelf = Library.get().isOnShelf(this.params.sourceId, this.params.comicId);
    this.favorited = Library.get().isFavorite(this.params.sourceId, this.params.comicId);
    this.chapterWindow = Math.max(CHAPTER_WINDOW_STEP, Math.min(CHAPTER_WINDOW_STEP,
      (this.detail === null ? 0 : this.detail.chapters.length)));
    if (this.switchAlignedIndex >= 0) {
      // 换源后直接对齐到目标章，而不是沿用（新源可能没有的）旧进度
      const total = this.detail.chapters.length;
      const idx = this.switchAlignedIndex < total ? this.switchAlignedIndex : (total > 0 ? total - 1 : 0);
      this.resumeIndex = idx;
      this.progressHint = total > 0 ? `换源后对齐到 ${this.detail.chapters[idx].title}` : '';
      this.ensureChapterVisible(idx);
      this.switchAlignedIndex = -1;
    } else {
      this.refreshProgress();
    }
  }

  /** 重新读取阅读进度，并同步「上次读到」与当前章高亮 */
  private refreshProgress(): void {
    if (this.detail === null) {
      return;
    }
    const total = this.detail.chapters.length;
    const progress: ReadProgress | null = Library.get().progress(this.params.sourceId, this.params.comicId);
    if (progress === null) {
      this.resumeIndex = 0;
      this.progressHint = '';
      return;
    }
    const rawIndex = progress.chapterIndex;
    const safeIndex = rawIndex >= 0 && rawIndex < total ? rawIndex : 0;
    this.resumeIndex = safeIndex;
    this.progressHint = `上次读到 ${this.detail.chapters[safeIndex].title}`;
    this.ensureChapterVisible(safeIndex);
  }

  /** 目录按当前排序显示；只翻转副本，绝不改动原始 chapters 顺序 */
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

  /** 正序时把当前章纳入已展开窗口；倒序时当前章靠后，强行展开会一次性铺完整个列表 */
  private ensureChapterVisible(index: number): void {
    if (this.detail === null || this.chapterDescending) {
      return;
    }
    const position = index;
    if (this.chapterWindow < position + 1) {
      this.chapterWindow = position + 1;
    }
  }

  private toggleChapterOrder(): void {
    const next = !this.chapterDescending;
    this.chapterDescending = next;
    Library.get().setChapterDescending(next);
    if (next) {
      // 切到倒序：只保留一个窗口，避免上千章一次铺开
      this.chapterWindow = Math.max(CHAPTER_WINDOW_STEP,
        Math.min(CHAPTER_WINDOW_STEP, this.detail === null ? 0 : this.detail.chapters.length));
      return;
    }
    this.ensureChapterVisible(this.resumeIndex);
  }

  private openReader(index: number): void {
    if (this.detail === null) {
      return;
    }
    const params: ReaderParams = new ReaderParams();
    params.sourceId = this.params.sourceId;
    params.comicId = this.params.comicId;
    params.comicUrl = this.detail.url;
    params.chapterIndex = index;
    // 显式点选章节时携带章节 ID，阅读器不会被旧的续读记录重定向到另一章。
    const chapter = this.detail.chapters[index];
    params.chapterId = chapter === undefined ? '' : chapter.chapterId;
    const saved = Library.get().progress(this.params.sourceId, this.params.comicId);
    params.page = saved !== null && saved.chapterIndex === index ? saved.page : 0;
    params.pageOffset = saved !== null && saved.chapterIndex === index ? saved.pageOffset : 0;
    router.pushUrl({ url: 'pages/ReaderPage', params: params });
  }

  private async toggleShelf(): Promise<void> {
    if (this.detail === null) {
      return;
    }
    const library = Library.get();
    if (this.onShelf) {
      await library.removeShelf(this.params.sourceId, this.params.comicId);
      this.onShelf = false;
      promptAction.showToast({ message: '已移出书架' });
      return;
    }
    const item = new ShelfItem();
    item.sourceId = this.params.sourceId;
    item.comicId = this.params.comicId;
    item.title = this.detail.title;
    item.cover = this.detail.cover;
    item.author = this.detail.author;
    item.url = this.detail.url;
    item.updatedAt = Date.now();
    await library.addShelf(item);
    this.onShelf = true;
    promptAction.showToast({ message: '已加入书架' });
  }

  private async toggleFavorite(): Promise<void> {
    if (this.detail === null) {
      return;
    }
    const library = Library.get();
    if (this.favorited) {
      await library.removeFavorite(this.params.sourceId, this.params.comicId);
      this.favorited = false;
      promptAction.showToast({ message: '已取消收藏' });
      return;
    }
    const favorite = new ShelfItem();
    favorite.sourceId = this.params.sourceId;
    favorite.comicId = this.params.comicId;
    favorite.title = this.detail.title;
    favorite.cover = this.detail.cover;
    favorite.author = this.detail.author;
    favorite.url = this.detail.url;
    favorite.updatedAt = Date.now();
    await library.addFavorite(favorite);
    this.favorited = true;
    promptAction.showToast({ message: '已收藏' });
  }

  private openSwitch(): void {
    if (this.detail === null) {
      return;
    }
    const params: SwitchParams = new SwitchParams();
    params.sourceId = this.detail.sourceId;
    params.comicId = this.detail.comicId;
    params.title = this.detail.title;
    params.chapterIndex = this.resumeIndex;
    const chapter = this.detail.chapters[this.resumeIndex];
    params.chapterTitle = chapter === undefined ? '' : chapter.title;
    router.pushUrl({ url: 'pages/SourceSwitchPage', params: params });
  }

  /** 章节按 1/2 列切行，行内用 SpaceBetween 保证间距均匀 */
  private chapterRows(items: ChapterBrief[]): ChapterBrief[][] {
    const visible = items.slice(0, this.chapterWindow);
    const cols = this.chapterColumns === 1 ? 1 : 2;
    const rows: ChapterBrief[][] = [];
    let current: ChapterBrief[] = [];
    for (let i = 0; i < visible.length; i++) {
      current.push(visible[i]);
      if (current.length === cols) {
        rows.push(current);
        current = [];
      }
    }
    if (current.length > 0) {
      rows.push(current);
    }
    return rows;
  }

  /** 切换 1 列 / 2 列并持久化 */
  private toggleChapterColumns(): void {
    const next = this.chapterColumns === 1 ? 2 : 1;
    this.chapterColumns = next;
    Library.get().setChapterColumns(next);
  }

  // ─────────────────────────── 版式块 ───────────────────────────

  @Builder
  navBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([Theme.text])
          .margin({ right: 4 })
        Text('返回')
          .fontSize(Theme.fsBody)
          .fontColor(Theme.text)
      }
      .height(44)
      .onClick(() => {
        router.back();
      })

      Blank()
      Text('作品详情')
        .fontSize(Theme.fsBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Blank()

      Row() {
        Row() {
          SymbolGlyph(this.favorited ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(18)
            .fontColor([this.favorited ? '#FFC46B' : Theme.textSub])
        }
        .width(34)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.favorited ? '#3A2E1E' : Theme.surfaceHi)
        .borderRadius(Theme.radiusPill)
        .margin({ right: Theme.gapS })
        .onClick(() => {
          this.toggleFavorite();
        })

        Text('换源')
          .fontSize(Theme.fsLabel)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.accent)
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor(Theme.accentDim)
          .borderRadius(Theme.radiusPill)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openSwitch();
          })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: Theme.gapM, right: Theme.gapL })
  }

  @Builder
  tagChip(label: string) {
    Text(label)
      .fontSize(Theme.fsMicro)
      .fontColor(Theme.textSub)
      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
      .backgroundColor(Theme.surfaceHi)
      .borderRadius(Theme.radiusS)
      .margin({ right: 6, top: 6 })
  }

  @Builder
  infoBlock() {
    Row() {
      RemoteImage({
        url: this.detail!.cover,
        referer: this.sourceBase,
        ratio: 0.747,
        corner: Theme.radiusM
      })
        .width(112)
        .shadow({ radius: 18, color: '#66000000', offsetX: 0, offsetY: 6 })

      Column() {
        Text(this.detail!.title)
          .fontSize(Theme.fsTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .lineHeight(27)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.detail!.author.length > 0 ? this.detail!.author : '未知作者')
          .fontSize(Theme.fsLabel)
          .fontColor(Theme.textSub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })
          .width('100%')

        // 有些源把「题材 / 收藏 / 人气」塞进 status，这种长文本当标签会显得很怪，
        // 按普通说明文字处理；短的（已完结之类）才用标签样式
        if (this.detail!.status.length > 14) {
          Text(this.detail!.status)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
            .width('100%')
        } else {
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.detail!.status.length > 0) {
              Text(this.detail!.status)
                .fontSize(Theme.fsMicro)
                .fontColor(Theme.accent)
                .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                .backgroundColor(Theme.accentDim)
                .borderRadius(Theme.radiusS)
                .margin({ right: 6, top: 6 })
            }
            ForEach(this.detail!.tags.slice(0, 3), (tag: string) => {
              this.tagChip(tag)
            }, (tag: string) => `tag_${tag}`)
          }
          .width('100%')
        }

        Text(`${this.detail!.chapters.length} 话 · ${this.sourceName}`)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 10 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Theme.gapL })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapS })
  }

  @Builder
  descBlock() {
    Column() {
      Text(this.detail!.description.length > 0 ? this.detail!.description : '暂无简介')
        .fontSize(Theme.fsLabel + 1)
        .fontColor(Theme.textSub)
        .lineHeight(22)
        .maxLines(this.descExpanded ? 60 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (this.detail!.description.length > 60) {
        Text(this.descExpanded ? '收起' : '展开全部')
          .fontSize(Theme.fsCaption)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.accent)
          .margin({ top: Theme.gapS })
          .onClick(() => {
            this.descExpanded = !this.descExpanded;
          })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(Theme.gapM + 2)
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.radiusL)
    .margin({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapL })
  }

  @Builder
  actionBlock() {
    Column() {
      Row() {
        Button(this.progressHint.length > 0 ? '继续阅读' : '开始阅读')
          .layoutWeight(1)
          .height(48)
          .fontSize(Theme.fsBody)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(Theme.accent)
          .fontColor(Theme.onAccent)
          .borderRadius(Theme.radiusM)
          .onClick(() => {
            this.openReader(this.resumeIndex);
          })
        Button(this.onShelf ? '已在书架' : '加入书架')
          .layoutWeight(1)
          .height(48)
          .fontSize(Theme.fsBody)
          .fontWeight(FontWeight.Medium)
          .margin({ left: Theme.gapM })
          .backgroundColor(this.onShelf ? Theme.surfaceHi : Theme.accentDim)
          .fontColor(this.onShelf ? Theme.textSub : Theme.accent)
          .borderRadius(Theme.radiusM)
          .onClick(() => {
            this.toggleShelf();
          })
      }
      .width('100%')

      if (this.progressHint.length > 0) {
        Text(this.progressHint)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapL })
  }

  @Builder
  chapterBlock() {
    Column() {
      Row() {
        Column()
          .width(3)
          .height(15)
          .backgroundColor(Theme.accent)
          .borderRadius(2)
        Text('章节目录')
          .fontSize(Theme.fsHeadline)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .margin({ left: 8 })
        Blank()
        Text(this.chapterDescending ? '倒序 ↓' : '正序 ↑')
          .fontSize(Theme.fsLabel)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.accent)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.accentDim)
          .borderRadius(Theme.radiusPill)
          .margin({ right: Theme.gapS })
          .onClick(() => {
            this.toggleChapterOrder();
          })
        Text(this.chapterColumns === 1 ? '单列' : '双列')
          .fontSize(Theme.fsLabel)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textSub)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.surfaceHi)
          .borderRadius(Theme.radiusPill)
          .margin({ right: Theme.gapM })
          .onClick(() => {
            this.toggleChapterColumns();
          })
        Text(`${this.detail!.chapters.length} 话`)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
      }
      .width('100%')
      .padding({ bottom: Theme.gapM })

      ForEach(this.chapterRows(this.orderedChapters()), (row: ChapterBrief[]) => {
        Row() {
          ForEach(row, (chapter: ChapterBrief) => {
            Column() {
              Text(chapter.title)
                .fontSize(Theme.fsLabel)
                .fontWeight(chapter.index === this.resumeIndex ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(chapter.index === this.resumeIndex ? Theme.accent : Theme.textSub)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Center)
              // 有更新时间就补一行小字，没有就保持原来的单行高度
              if (chapter.time.length > 0) {
                Text(shortTime(chapter.time))
                  .fontSize(Theme.fsMicro)
                  .fontColor(Theme.textDim)
                  .maxLines(1)
                  .margin({ top: 3 })
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
            }
            .width(this.chapterColumns === 1 ? '100%' : '48.5%')
            .height(chapter.time.length > 0 ? 56 : 44)
            .justifyContent(FlexAlign.Center)
            .padding({ left: 8, right: 8 })
            .backgroundColor(chapter.index === this.resumeIndex ? Theme.accentDim : Theme.surface)
            .borderRadius(Theme.radiusS + 2)
            .onClick(() => {
              this.openReader(chapter.index);
            })
          }, (chapter: ChapterBrief) => `${chapter.chapterId}_${chapter.index}`)
          if (row.length < this.chapterColumns) {
            Column().width(this.chapterColumns === 1 ? '100%' : '48.5%')
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: Theme.gapS })
      }, (row: ChapterBrief[], index: number) => {
        // 行 key 必须带上该行首章：倒序后行数不变，只靠 index 的话 ForEach
        // 认为 key 没变化，界面不会真正重排
        if (row.length === 0) {
          return `crow_${index}_empty`;
        }
        return `crow_${row[0].chapterId}_${row[0].index}_${row.length}`;
      })

      if (this.chapterWindow < this.detail!.chapters.length) {
        Text(`显示更多（${this.chapterWindow} / ${this.detail!.chapters.length}）`)
          .fontSize(Theme.fsLabel)
          .fontColor(Theme.accent)
          .width('100%')
          .height(44)
          .textAlign(TextAlign.Center)
          .backgroundColor(Theme.surface)
          .borderRadius(Theme.radiusS + 2)
          .margin({ top: Theme.gapXs })
          .onClick(() => {
            this.chapterWindow += CHAPTER_WINDOW_STEP;
          })
      }
    }
    .width('100%')
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapXl, bottom: 32 })
  }

  build() {
    Column() {
      this.navBar()
      if (this.loading) {
        Column() {
          LoadingProgress().width(34).height(34).color(Theme.accent)
          Text('正在读取详情…')
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .margin({ top: Theme.gapM })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.error.length > 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(38)
            .fontColor([Theme.line])
          Text(this.error)
            .fontSize(Theme.fsBody)
            .fontColor(Theme.textSub)
            .textAlign(TextAlign.Center)
            .lineHeight(22)
            .margin({ top: Theme.gapL })
            .padding({ left: 32, right: 32 })
          Row() {
            Button('重试')
              .fontSize(Theme.fsLabel)
              .height(40)
              .padding({ left: 24, right: 24 })
              .backgroundColor(Theme.surfaceHi)
              .fontColor(Theme.accent)
              .borderRadius(Theme.radiusPill)
              .onClick(() => {
                this.load();
              })
            Button('换个源')
              .fontSize(Theme.fsLabel)
              .height(40)
              .padding({ left: 24, right: 24 })
              .margin({ left: Theme.gapM })
              .backgroundColor(Theme.surfaceHi)
              .fontColor(Theme.accent)
              .borderRadius(Theme.radiusPill)
              .onClick(() => {
                this.openSwitch();
              })
          }
          .margin({ top: Theme.gapXl })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.detail !== null) {
        Scroll() {
          Column() {
            this.infoBlock()
            this.descBlock()
            this.actionBlock()
            this.chapterBlock()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
