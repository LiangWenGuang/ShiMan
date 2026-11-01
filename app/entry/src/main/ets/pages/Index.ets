import { router, promptAction } from '@kit.ArkUI';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceApi } from '../source/SourceApi';
import { SourceRule, BrowseRule } from '../rule/Rules';
import { ComicBrief, ShelfItem, ReadProgress } from '../model/Models';
import { Library } from '../store/Library';
import { ComicCard } from '../view/ComicCard';
import { RemoteImage } from '../view/RemoteImage';
import { DetailParams, ReaderParams } from '../model/RouteParams';
import { Theme } from '../theme/Theme';

/** 网格每行卡片数 */
const COLUMNS: number = 3;

@Entry
@Component
struct Index {
  @State currentTab: number = 0;

  // 发现
  @State sources: SourceRule[] = [];
  @State currentSourceId: string = '';
  @State currentSourceName: string = '';
  @State browseNames: string[] = [];
  @State browseIndex: number = 0;
  @State discover: ComicBrief[] = [];
  @State discoverLoading: boolean = false;
  @State discoverError: string = '';

  // 搜索
  @State keyword: string = '';
  @State searchAll: boolean = false;
  @State searchResults: ComicBrief[] = [];
  @State searchLoading: boolean = false;
  @State searchError: string = '';
  @State searchDone: boolean = false;

  // 书架 / 收藏
  @State shelf: ShelfItem[] = [];
  @State favorites: ShelfItem[] = [];
  @State history: ReadProgress[] = [];

  aboutToAppear(): void {
    this.refreshSources();
    this.loadDiscover(0);
  }

  onPageShow(): void {
    // 记住切换前的源：从「图源管理」改了当前源回来时要重新拉发现页，
    // 否则分类标签换了、下面的漫画还是上一个源的内容
    const previousSourceId = this.currentSourceId;
    this.refreshSources();
    if (previousSourceId !== this.currentSourceId && this.currentSourceId.length > 0) {
      this.loadDiscover(0);
    }
    this.shelf = Library.get().shelf();
    this.favorites = Library.get().favorites();
    this.history = Library.get().history();
  }

  private refreshSources(): void {
    const registry = SourceRegistry.get();
    this.sources = registry.enabled();
    const currentId = registry.currentSourceId();
    this.currentSourceId = currentId;
    const rule = registry.find(currentId);
    this.currentSourceName = rule === null ? '未启用图源' : rule.name;
    const names: string[] = [];
    if (rule !== null) {
      for (let i = 0; i < rule.browse.length; i++) {
        names.push(rule.browse[i].name);
      }
    }
    this.browseNames = names;
    if (this.browseIndex >= names.length) {
      this.browseIndex = 0;
    }
  }

  private async loadDiscover(index: number): Promise<void> {
    const registry = SourceRegistry.get();
    const rule = registry.find(registry.currentSourceId());
    if (rule === null) {
      this.discover = [];
      this.discoverError = '还没有可用图源\n请到「我的 → 图源管理」启用';
      return;
    }
    if (rule.browse.length === 0) {
      this.discover = [];
      this.discoverError = '当前图源未提供分类入口\n可直接用「搜索」找漫画';
      return;
    }
    const safeIndex = index < 0 || index >= rule.browse.length ? 0 : index;
    this.browseIndex = safeIndex;
    this.discoverLoading = true;
    this.discoverError = '';
    const entry: BrowseRule = rule.browse[safeIndex];
    const outcome = await SourceApi.browse(rule, entry, 1);
    this.discoverLoading = false;
    if (outcome.ok && outcome.value !== undefined) {
      this.discover = outcome.value;
    } else {
      this.discover = [];
      this.discoverError = outcome.message;
    }
  }

  private async doSearch(): Promise<void> {
    const kw = this.keyword.trim();
    if (kw.length === 0) {
      promptAction.showToast({ message: '先输入关键词' });
      return;
    }
    this.searchLoading = true;
    this.searchError = '';
    this.searchDone = false;
    const registry = SourceRegistry.get();
    const merged: ComicBrief[] = [];
    const errors: string[] = [];

    if (this.searchAll) {
      const list = registry.enabled();
      for (let i = 0; i < list.length; i++) {
        const outcome = await SourceApi.search(list[i], kw, 1);
        if (outcome.ok && outcome.value !== undefined) {
          for (let k = 0; k < outcome.value.length; k++) {
            merged.push(outcome.value[k]);
          }
        } else {
          errors.push(outcome.message);
        }
      }
    } else {
      const rule = registry.find(registry.currentSourceId());
      if (rule === null) {
        this.searchLoading = false;
        this.searchError = '还没有启用任何图源';
        return;
      }
      const outcome = await SourceApi.search(rule, kw, 1);
      if (outcome.ok && outcome.value !== undefined) {
        for (let k = 0; k < outcome.value.length; k++) {
          merged.push(outcome.value[k]);
        }
      } else {
        errors.push(outcome.message);
      }
    }

    this.searchLoading = false;
    this.searchDone = true;
    this.searchResults = merged;
    if (merged.length === 0) {
      this.searchError = errors.length > 0 ? errors.join('\n') : '没有找到结果，换个关键词试试';
    } else if (errors.length > 0) {
      this.searchError = `部分图源失败：${errors.join('；')}`;
    }
  }

  /** 取图源站点地址，作为封面下载的 Referer（部分 CDN 有防盗链） */
  private refererOf(sourceId: string): string {
    const rule = SourceRegistry.get().find(sourceId);
    return rule === null ? '' : rule.baseUrl;
  }

  private openDetail(item: ComicBrief): void {
    const params: DetailParams = new DetailParams();
    params.sourceId = item.sourceId;
    params.comicId = item.comicId;
    params.url = item.url;
    params.title = item.title;
    router.pushUrl({ url: 'pages/DetailPage', params: params });
  }

  private isFavorite(sourceId: string, comicId: string): boolean {
    return Library.get().isFavorite(sourceId, comicId);
  }

  /** 长按卡片直接收藏 / 取消收藏，不用先进详情页 */
  private async toggleFavorite(item: ComicBrief): Promise<void> {
    const library = Library.get();
    if (library.isFavorite(item.sourceId, item.comicId)) {
      await library.removeFavorite(item.sourceId, item.comicId);
      this.favorites = library.favorites();
      promptAction.showToast({ message: '已取消收藏' });
      return;
    }
    const favorite = new ShelfItem();
    favorite.sourceId = item.sourceId;
    favorite.comicId = item.comicId;
    favorite.title = item.title;
    favorite.cover = item.cover;
    favorite.author = item.author;
    favorite.url = item.url;
    favorite.updatedAt = Date.now();
    await library.addFavorite(favorite);
    this.favorites = library.favorites();
    promptAction.showToast({ message: '已收藏' });
  }

  private openFavorites(): void {
    router.pushUrl({ url: 'pages/FavoritesPage' });
  }

  private openSourceManager(): void {
    router.pushUrl({ url: 'pages/SourceManagerPage' });
  }

  /** 每行三张卡，避免 Grid 嵌在滚动容器里的高度问题 */
  private rows(items: ComicBrief[]): ComicBrief[][] {
    const out: ComicBrief[][] = [];
    let current: ComicBrief[] = [];
    for (let i = 0; i < items.length; i++) {
      current.push(items[i]);
      if (current.length === COLUMNS) {
        out.push(current);
        current = [];
      }
    }
    if (current.length > 0) {
      out.push(current);
    }
    return out;
  }

  private shelfRows(): ShelfItem[][] {
    const out: ShelfItem[][] = [];
    let current: ShelfItem[] = [];
    for (let i = 0; i < this.shelf.length; i++) {
      current.push(this.shelf[i]);
      if (current.length === COLUMNS) {
        out.push(current);
        current = [];
      }
    }
    if (current.length > 0) {
      out.push(current);
    }
    return out;
  }

  // ─────────────────────────── 通用版式块 ───────────────────────────

  /** 分区标题：左侧竖条 + 标题 + 右侧计数 */
  @Builder
  sectionTitle(title: string, hint: string) {
    Row() {
      Column()
        .width(3)
        .height(15)
        .backgroundColor(Theme.accent)
        .borderRadius(2)
      Text(title)
        .fontSize(Theme.fsHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .margin({ left: 8 })
      Blank()
      if (hint.length > 0) {
        Text(hint)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
      }
    }
    .width('100%')
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapXl, bottom: Theme.gapM })
  }

  /** 居中占位：图标 + 主文案 + 副文案 + 可选按钮 */
  @Builder
  emptyBlock(title: string, hint: string, action: string, onAction: () => void) {
    Column() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(38)
        .fontColor([Theme.line])
      Text(title)
        .fontSize(Theme.fsBody)
        .fontColor(Theme.textSub)
        .textAlign(TextAlign.Center)
        .margin({ top: Theme.gapL })
        .padding({ left: 32, right: 32 })
      if (hint.length > 0) {
        Text(hint)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .textAlign(TextAlign.Center)
          .lineHeight(19)
          .margin({ top: Theme.gapS })
          .padding({ left: 32, right: 32 })
      }
      if (action.length > 0) {
        Button(action)
          .fontSize(Theme.fsLabel)
          .fontWeight(FontWeight.Medium)
          .height(40)
          .padding({ left: 24, right: 24 })
          .margin({ top: Theme.gapXl })
          .backgroundColor(Theme.surfaceHi)
          .fontColor(Theme.accent)
          .borderRadius(Theme.radiusPill)
          .onClick(() => {
            onAction();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  loadingBlock(text: string) {
    Column() {
      LoadingProgress().width(34).height(34).color(Theme.accent)
      Text(text)
        .fontSize(Theme.fsCaption)
        .fontColor(Theme.textDim)
        .margin({ top: Theme.gapM })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  // ─────────────────────────── 发现 ───────────────────────────

  @Builder
  appHeader() {
    Row() {
      Column() {
        Text('拾漫')
          .fontSize(Theme.fsDisplay)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .letterSpacing(0.5)
        Row() {
          Text(this.currentSourceName)
            .fontSize(Theme.fsLabel)
            .fontColor(Theme.textSub)
          Text('·')
            .fontSize(Theme.fsLabel)
            .fontColor(Theme.textDim)
            .margin({ left: 6, right: 6 })
          Text('无广告 · 免登录')
            .fontSize(Theme.fsLabel)
            .fontColor(Theme.textDim)
        }
        .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row() {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(15)
          .fontColor([Theme.accent])
        Text(`${this.sources.length} 个源`)
          .fontSize(Theme.fsLabel)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.accent)
          .margin({ left: 6 })
      }
      .height(34)
      .padding({ left: 13, right: 15 })
      .backgroundColor(Theme.accentDim)
      .borderRadius(Theme.radiusPill)
      .onClick(() => {
        this.openSourceManager();
      })
    }
    .width('100%')
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapM, bottom: Theme.gapL })
  }

  @Builder
  chipRow() {
    Scroll() {
      Row() {
        ForEach(this.browseNames, (name: string, index: number) => {
          Text(name)
            .fontSize(Theme.fsLabel + 1)
            .fontWeight(index === this.browseIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(index === this.browseIndex ? Theme.onAccent : Theme.textSub)
            .height(34)
            .padding({ left: 16, right: 16 })
            .backgroundColor(index === this.browseIndex ? Theme.accent : Theme.surface)
            .borderRadius(Theme.radiusPill)
            .margin({ right: Theme.gapS + 2 })
            .onClick(() => {
              this.loadDiscover(index);
            })
        }, (name: string, index: number) => `${name}_${index}`)
      }
      .padding({ left: Theme.gapL, right: Theme.gapL })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  comicGrid(items: ComicBrief[]) {
    ForEach(this.rows(items), (row: ComicBrief[]) => {
      Row() {
        ForEach(row, (item: ComicBrief) => {
          Column() {
            ComicCard({
              title: item.title,
              cover: item.cover,
              subtitle: item.latest,
              referer: this.refererOf(item.sourceId),
              starred: this.isFavorite(item.sourceId, item.comicId),
              onTap: () => {
                this.openDetail(item);
              }
            })
          }
          .layoutWeight(1)
          .padding({ left: Theme.gapXs, right: Theme.gapXs })
          .gesture(LongPressGesture().onAction(() => {
            this.toggleFavorite(item);
          }))
        }, (item: ComicBrief) => `${item.sourceId}_${item.comicId}`)
        if (row.length < COLUMNS) {
          ForEach([1, 2].slice(0, COLUMNS - row.length), (pad: number) => {
            Column().layoutWeight(1)
          }, (pad: number) => `pad_${pad}`)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ bottom: 18 })
    }, (row: ComicBrief[], index: number) => `row_${index}_${row.length}`)
  }

  @Builder
  discoverTab() {
    Column() {
      this.appHeader()
      this.chipRow()
      if (this.discoverLoading) {
        this.loadingBlock('正在加载分类…')
      } else if (this.discoverError.length > 0) {
        this.emptyBlock(this.discoverError, '', '重新加载', () => {
          this.loadDiscover(this.browseIndex);
        })
      } else if (this.discover.length === 0) {
        this.emptyBlock('这个分类暂时没有内容', '换个分类试试，或到「搜索」里找找', '重新加载', () => {
          this.loadDiscover(this.browseIndex);
        })
      } else {
        List() {
          ListItem() {
            Column() {
              this.comicGrid(this.discover)
            }
            .padding({ left: Theme.gapM, right: Theme.gapM, top: Theme.gapL })
          }
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

  // ─────────────────────────── 搜索 ───────────────────────────

  @Builder
  scopePill(label: string, all: boolean) {
    Text(label)
      .fontSize(Theme.fsLabel)
      .fontWeight(this.searchAll === all ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.searchAll === all ? Theme.onAccent : Theme.textSub)
      .height(30)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.searchAll === all ? Theme.accent : Color.Transparent)
      .borderRadius(Theme.radiusPill)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.searchAll = all;
      })
  }

  @Builder
  searchBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([Theme.textDim])
          .margin({ left: 14, right: 10 })
        TextInput({ placeholder: '搜索漫画名 / 作者', text: this.keyword })
          .placeholderColor(Theme.textDim)
          .placeholderFont({ size: Theme.fsBody })
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.text)
          .fontSize(Theme.fsBody)
          .height('100%')
          .padding(0)
          .layoutWeight(1)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => {
            this.keyword = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })
      }
      .height(46)
      .layoutWeight(1)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusM)

      Button('搜索')
        .width(74)
        .height(46)
        .fontSize(Theme.fsBody)
        .fontWeight(FontWeight.Medium)
        .margin({ left: Theme.gapM })
        .backgroundColor(Theme.accent)
        .fontColor(Theme.onAccent)
        .borderRadius(Theme.radiusM)
        .onClick(() => {
          this.doSearch();
        })
    }
    .width('100%')
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapL })
  }

  @Builder
  scopeRow() {
    Row() {
      Column() {
        Row() {
          this.scopePill('仅当前源', false)
          this.scopePill('全部图源', true)
        }
        .padding(3)
        .backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusPill)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.searchAll ? `${this.sources.length} 个源参与` : '单源检索')
        .fontSize(Theme.fsCaption)
        .fontColor(Theme.textDim)
    }
    .width('100%')
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapM })
  }

  @Builder
  searchTab() {
    Column() {
      this.searchBar()
      this.scopeRow()

      if (this.searchLoading) {
        this.loadingBlock('正在各源检索…')
      } else if (this.searchResults.length === 0) {
        if (this.searchDone && this.searchError.length > 0) {
          this.emptyBlock(this.searchError, '', '清空重来', () => {
            this.keyword = '';
            this.searchDone = false;
            this.searchResults = [];
            this.searchError = '';
          })
        } else {
          this.emptyBlock('还没有搜索', '输入关键词，可在全部图源中一次找完', '', () => {
          })
        }
      } else {
        List() {
          ListItem() {
            Row() {
              Text(`找到 ${this.searchResults.length} 部`)
                .fontSize(Theme.fsCaption)
                .fontColor(Theme.textSub)
              Blank()
              if (this.searchError.length > 0) {
                Text(this.searchError)
                  .fontSize(Theme.fsCaption)
                  .fontColor(Theme.warn)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .textAlign(TextAlign.End)
              }
            }
            .width('100%')
            .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapL, bottom: Theme.gapM })
          }
          ListItem() {
            Column() {
              this.comicGrid(this.searchResults)
            }
            .padding({ left: Theme.gapM, right: Theme.gapM })
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  // ─────────────────────────── 书架 ───────────────────────────

  @Builder
  historyCard(item: ReadProgress) {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        RemoteImage({
          url: item.cover,
          referer: this.refererOf(item.sourceId),
          ratio: 0.72,
          corner: Theme.radiusM
        })
        Text(`${item.page + 1} 页`)
          .fontSize(Theme.fsMicro)
          .fontColor(Theme.onAccent)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor('#E8EEF8')
          .borderRadius(Theme.radiusPill)
          .margin({ right: 7, bottom: 7 })
      }
      .width('100%')

      Text(item.title)
        .fontSize(Theme.fsLabel + 1)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: Theme.gapS })
        .width('100%')
      Text(item.chapterTitle)
        .fontSize(Theme.fsMicro)
        .fontColor(Theme.textDim)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 3 })
        .width('100%')
    }
    .width(104)
    .margin({ right: Theme.gapM })
    .onClick(() => {
      const params: ReaderParams = new ReaderParams();
      params.sourceId = item.sourceId;
      params.comicId = item.comicId;
      params.chapterIndex = item.chapterIndex;
      params.chapterId = item.chapterId;
      router.pushUrl({ url: 'pages/ReaderPage', params: params });
    })
  }

  @Builder
  shelfCard(item: ShelfItem) {
    Column() {
      RemoteImage({
        url: item.cover,
        referer: this.refererOf(item.sourceId),
        ratio: 0.75,
        corner: Theme.radiusM
      })
      Text(item.title)
        .fontSize(Theme.fsLabel + 1)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: Theme.gapS })
        .width('100%')
      Text(item.author.length > 0 ? item.author : '未知作者')
        .fontSize(Theme.fsMicro)
        .fontColor(Theme.textDim)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 3 })
        .width('100%')
    }
    .layoutWeight(1)
    .padding({ left: Theme.gapXs, right: Theme.gapXs })
    .onClick(() => {
      const params: DetailParams = new DetailParams();
      params.sourceId = item.sourceId;
      params.comicId = item.comicId;
      params.url = item.url;
      params.title = item.title;
      router.pushUrl({ url: 'pages/DetailPage', params: params });
    })
  }

  @Builder
  shelfTab() {
    List() {
      if (this.history.length > 0) {
        ListItem() {
          this.sectionTitle('继续阅读', `${this.history.length} 条记录`)
        }
        ListItem() {
          Scroll() {
            Row() {
              ForEach(this.history.slice(0, 8), (item: ReadProgress) => {
                this.historyCard(item)
              }, (item: ReadProgress) => `h_${item.sourceId}_${item.comicId}`)
            }
            .padding({ left: Theme.gapL })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
      }

      ListItem() {
        this.sectionTitle('我的书架', this.shelf.length > 0 ? `${this.shelf.length} 本` : '')
      }

      if (this.shelf.length === 0) {
        ListItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.book_pages'))
              .fontSize(36)
              .fontColor([Theme.line])
            Text('书架还是空的')
              .fontSize(Theme.fsBody)
              .fontColor(Theme.textSub)
              .margin({ top: Theme.gapL })
            Text('在漫画详情页点「加入书架」即可收藏')
              .fontSize(Theme.fsCaption)
              .fontColor(Theme.textDim)
              .margin({ top: Theme.gapS })
          }
          .width('100%')
          .padding({ top: 48, bottom: 56 })
          .justifyContent(FlexAlign.Center)
        }
      } else {
        ForEach(this.shelfRows(), (row: ShelfItem[]) => {
          ListItem() {
            Row() {
              ForEach(row, (item: ShelfItem) => {
                this.shelfCard(item)
              }, (item: ShelfItem) => `s_${item.sourceId}_${item.comicId}`)
              if (row.length < COLUMNS) {
                ForEach([1, 2].slice(0, COLUMNS - row.length), (pad: number) => {
                  Column().layoutWeight(1)
                }, (pad: number) => `spad_${pad}`)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ left: Theme.gapM, right: Theme.gapM, bottom: 18 })
          }
        }, (row: ShelfItem[], index: number) => `srow_${index}_${row.length}`)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  // ─────────────────────────── 我的 ───────────────────────────

  @Builder
  settingRow(title: string, value: string, action: () => void) {
    Row() {
      Text(title)
        .fontSize(Theme.fsBody)
        .fontColor(Theme.text)
      Blank()
      Text(value)
        .fontSize(Theme.fsLabel)
        .fontColor(Theme.textDim)
      Text('›')
        .fontSize(20)
        .fontColor(Theme.textDim)
        .margin({ left: 6 })
    }
    .width('100%')
    .height(52)
    .padding({ left: Theme.gapL, right: Theme.gapL })
    .onClick(() => {
      action();
    })
  }

  @Builder
  mineTab() {
    Scroll() {
      Column() {
        // 头部
        Row() {
          Image($r('app.media.app_icon'))
            .width(58)
            .height(58)
            .borderRadius(Theme.radiusM)
          Column() {
            Text('拾漫')
              .fontSize(Theme.fsTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text)
            Text('拾漫 · 多源聚合阅读')
              .fontSize(Theme.fsLabel)
              .fontColor(Theme.textSub)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: Theme.gapM })
        }
        .width('100%')
        .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapXl, bottom: Theme.gapL })

        Text('我的')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .width('100%')
          .padding({ left: Theme.gapL + 4, bottom: Theme.gapS })

        Column() {
          this.settingRow('我的收藏', this.favorites.length > 0 ? `${this.favorites.length} 部` : '暂无', () => {
            this.openFavorites();
          })
          Divider().color(Theme.line).margin({ left: Theme.gapL, right: Theme.gapL })
          this.settingRow('书架', this.shelf.length > 0 ? `${this.shelf.length} 本` : '暂无', () => {
            this.currentTab = 2;
            this.shelf = Library.get().shelf();
            this.favorites = Library.get().favorites();
            this.history = Library.get().history();
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusL)

        Text('图源')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .width('100%')
          .padding({ left: Theme.gapL + 4, top: Theme.gapXl, bottom: Theme.gapS })

        Column() {
          this.settingRow('图源管理', `${this.sources.length} 个已启用`, () => {
            this.openSourceManager();
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusL)

        Text('通用')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .width('100%')
          .padding({ left: Theme.gapL + 4, top: Theme.gapXl, bottom: Theme.gapS })

        Column() {
          this.settingRow('阅读设置', '', () => {
            router.pushUrl({ url: 'pages/SettingsPage' });
          })
          Divider().color(Theme.line).margin({ left: Theme.gapL, right: Theme.gapL })
          this.settingRow('阅读历史', `${this.history.length} 条`, () => {
            this.currentTab = 2;
            this.shelf = Library.get().shelf();
            this.history = Library.get().history();
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusL)

        Text('关于')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .width('100%')
          .padding({ left: Theme.gapL + 4, top: Theme.gapXl, bottom: Theme.gapS })

        Column() {
          Text('拾漫是一个纯 ArkTS 实现的鸿蒙原生漫画聚合阅读器。图源规则开放可扩展，' +
            '不内置任何广告、不要求登录、不上传任何个人数据。')
            .fontSize(Theme.fsCaption + 1)
            .fontColor(Theme.textSub)
            .lineHeight(21)
            .width('100%')
          Text('漫画版权归原作者与发布平台所有，请支持正版。')
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .lineHeight(19)
            .margin({ top: Theme.gapM })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(Theme.gapL)
        .backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusL)

        Text('拾漫 1.0.0')
          .fontSize(Theme.fsMicro)
          .fontColor(Theme.textDim)
          .margin({ top: Theme.gapXl + 8, bottom: 28 })
      }
      .width('100%')
      .padding({ left: Theme.gapL, right: Theme.gapL })
      // 内容比一屏短时 Scroll 会把子组件垂直居中，这里钉回顶部
      .constraintSize({ minHeight: '100%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  // ─────────────────────────── 骨架 ───────────────────────────

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
        TabContent() {
          this.discoverTab()
        }.tabBar(this.tabLabel('发现', $r('sys.symbol.house'), $r('sys.symbol.house_fill'), 0))

        TabContent() {
          this.searchTab()
        }.tabBar(this.tabLabel('搜索', $r('sys.symbol.magnifyingglass'),
          $r('sys.symbol.magnifyingglass'), 1))

        TabContent() {
          this.shelfTab()
        }.tabBar(this.tabLabel('书架', $r('sys.symbol.book_pages'), $r('sys.symbol.book_pages_fill'), 2))

        TabContent() {
          this.mineTab()
        }.tabBar(this.tabLabel('我的', $r('sys.symbol.person'), $r('sys.symbol.person_fill'), 3))
      }
      .barBackgroundColor(Theme.nav)
      .barHeight(62)
      .onChange((index: number) => {
        this.currentTab = index;
        if (index === 2) {
          this.shelf = Library.get().shelf();
          this.history = Library.get().history();
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  @Builder
  tabLabel(text: string, icon: Resource, iconActive: Resource, index: number) {
    Column() {
      SymbolGlyph(this.currentTab === index ? iconActive : icon)
        .fontSize(23)
        .fontColor([this.currentTab === index ? Theme.accent : Theme.textDim])
      Text(text)
        .fontSize(Theme.fsMicro)
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTab === index ? Theme.accent : Theme.textDim)
        .margin({ top: 3 })
    }
    .width('100%')
    .height(62)
    .justifyContent(FlexAlign.Center)
  }
}
