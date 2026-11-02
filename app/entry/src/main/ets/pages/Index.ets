import { router, promptAction } from '@kit.ArkUI';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceApi } from '../source/SourceApi';
import { SourceRule } from '../rule/Rules';
import { ComicBrief, ShelfItem, ReadProgress } from '../model/Models';
import { Library } from '../store/Library';
import { ComicCard } from '../view/ComicCard';
import { RemoteImage } from '../view/RemoteImage';
import { DetailParams, ReaderParams } from '../model/RouteParams';
import { Theme } from '../theme/Theme';

/** 网格每行卡片数 */
const COLUMNS: number = 3;

/** 首页聚合时每批并发的源数量：太多会被站点限流，太少又慢 */
const DISCOVER_BATCH: number = 4;

/**
 * 标题归一化，用于跨源去重。
 * 「一人之下」和「一人 之下！」在不同站写法不同，但其实是同一部。
 */
function normalizeTitle(value: string): string {
  return value.replace(new RegExp('[\\s\\-_·:：!！?？()（）\\[\\]【】<>《》]', 'g'), '').toLowerCase();
}

/**
 * 把各源的结果轮流交叉排：第一行能看到 3 个不同来源。
 * 不交叉的话首屏会被第一个源（漫客栈 40 本）整片占满，
 * 用户会以为「全部图源」其实只有一家。
 */
function interleave(buckets: ComicBrief[][]): ComicBrief[] {
  const out: ComicBrief[] = [];
  let maxLen: number = 0;
  for (let i = 0; i < buckets.length; i++) {
    maxLen = Math.max(maxLen, buckets[i].length);
  }
  for (let col = 0; col < maxLen; col++) {
    for (let i = 0; i < buckets.length; i++) {
      if (col < buckets[i].length) {
        out.push(buckets[i][col]);
      }
    }
  }
  return out;
}

@Entry
@Component
struct Index {
  @State currentTab: number = 0;

  // 发现（首页）
  @State sources: SourceRule[] = [];
  @State currentSourceId: string = '';
  @State currentSourceName: string = '';
  /** true = 只看当前图源（默认）；false = 全部图源聚合 */
  @State homeCurrentOnly: boolean = true;
  /** 当前图源提供的分类入口 */
  @State browseNames: string[] = [];
  @State browseIndex: number = 0;
  @State discover: ComicBrief[] = [];
  @State discoverLoading: boolean = false;
  @State discoverError: string = '';
  /** 下拉刷新/点刷新时的转圈状态 */
  @State refreshing: boolean = false;
  /** 本次加载是否由「手动刷新」触发（用来决定要不要弹提示） */
  private manualRefresh: boolean = false;
  /** 聚合进度文案，如 "8/22" */
  @State discoverProgress: string = '';
  /** 并发令牌：重新聚合时让上一轮的迟到结果作废 */
  private discoverToken: number = 0;

  // 搜索
  @State keyword: string = '';
  @State searchAll: boolean = false;
  @State searchResults: ComicBrief[] = [];
  @State searchLoading: boolean = false;
  @State searchError: string = '';
  @State searchDone: boolean = false;
  @State searchHistoryShown: boolean = false;
  @State searchHistoryItems: string[] = [];
  /** 切当前检索源的自定义深色弹窗 */
  @State sourceSheetShown: boolean = false;
  /** 搜索框失焦令牌：延迟隐藏历史，避免点历史项时先被 blur 隐藏 */
  private blurToken: number = 0;

  // 书架 / 收藏
  @State shelf: ShelfItem[] = [];
  @State favorites: ShelfItem[] = [];
  @State history: ReadProgress[] = [];

  aboutToAppear(): void {
    this.refreshSources();
    this.loadHome();
  }

  onPageShow(): void {
    // 记住切换前的源：从「图源管理」改了当前源回来时要重拉，
    // 否则首页还是上一个源的内容
    const previousSourceId = this.currentSourceId;
    this.refreshSources();
    if (previousSourceId !== this.currentSourceId && this.homeCurrentOnly) {
      this.loadHome();
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

  /** 按当前模式加载首页 */
  private loadHome(): void {
    if (this.homeCurrentOnly) {
      this.loadDiscoverForCurrent(0);
    } else {
      this.loadDiscoverAll();
    }
  }

  /** 下拉 / 点刷新 / 换模式都走这里：统一把 refreshing 打开，数据回来再关 */
  private refreshHome(): void {
    this.refreshing = true;
    this.manualRefresh = true;
    this.loadHome();
  }

  /** 手动刷新完成后给个明确反馈，否则数据没变化时用户以为按钮没生效 */
  private finishManualRefresh(): void {
    if (!this.manualRefresh) {
      return;
    }
    this.manualRefresh = false;
    promptAction.showToast({
      message: this.discover.length > 0 ? `已刷新 · ${this.discover.length} 部` : '没取到内容，检查网络后重试'
    });
  }

  private switchHomeScope(currentOnly: boolean): void {
    if (this.homeCurrentOnly === currentOnly) {
      return;
    }
    this.homeCurrentOnly = currentOnly;
    // 换模式先清空，避免上一种模式的列表残留一瞬
    this.discover = [];
    this.discoverError = '';
    this.loadHome();
  }

  /**
   * 只看当前图源：直接拉它的第一个入口（各站的「首页 / 全部更新」）。
   * 首页不跟分类挂钩 —— 分类/榜单在「排行榜」页里看，首页只负责把当前源的东西铺开。
   */
  private async loadDiscoverForCurrent(index: number): Promise<void> {
    const registry = SourceRegistry.get();
    const rule = registry.find(registry.currentSourceId());
    // 令聚合那一路的迟到结果作废
    this.discoverToken++;
    if (rule === null) {
      this.discover = [];
      this.discoverError = '还没有可用图源\n请到「我的 → 图源管理」启用';
      this.refreshing = false;
      this.manualRefresh = false;
      return;
    }
    if (rule.browse.length === 0) {
      this.discover = [];
      this.discoverError = `${rule.name} 没提供首页入口\n可以到「搜索」或「排行榜」找漫画`;
      this.refreshing = false;
      this.manualRefresh = false;
      return;
    }
    const safeIndex = index < 0 || index >= rule.browse.length ? 0 : index;
    this.browseIndex = safeIndex;
    this.discoverLoading = true;
    this.discoverError = '';
    const outcome = await SourceApi.browse(rule, rule.browse[safeIndex], 1);
    this.discoverLoading = false;
    this.refreshing = false;
    if (outcome.ok && outcome.value !== undefined) {
      // 换一个新数组，确保 ForEach 能感知到变化
      this.discover = outcome.value.slice(0);
    } else {
      this.discover = [];
      this.discoverError = outcome.message;
    }
    this.finishManualRefresh();
  }

  /**
   * 首页 = 全部图源聚合。
   *
   * 每个源取它自己的第一个 browse 入口（各站的「首页 / 最近更新」），分批并发拉，
   * 边拉到边渲染，用户不用等 20 多个源全回来才看到东西。
   * 同名漫画只留第一次出现的（跨源去重），保留来源标签方便用户挑。
   */
  private async loadDiscoverAll(): Promise<void> {
    const list = SourceRegistry.get().enabled();
    const token = ++this.discoverToken;
    this.discoverLoading = true;
    this.discoverError = '';
    this.discover = [];
    this.discoverProgress = `0/${list.length}`;
    if (list.length === 0) {
      this.discoverLoading = false;
      this.refreshing = false;
      this.manualRefresh = false;
      this.discoverError = '还没有可用图源\n请到「我的 → 图源管理」启用';
      return;
    }

    const buckets: ComicBrief[][] = [];
    const seenTitles: string[] = [];
    for (let start = 0; start < list.length; start += DISCOVER_BATCH) {
      const end = Math.min(list.length, start + DISCOVER_BATCH);
      const tasks: Promise<void>[] = [];
      for (let k = start; k < end; k++) {
        const rule: SourceRule = list[k];
        if (rule.browse.length === 0) {
          continue;
        }
        tasks.push(this.collectSource(rule, buckets, seenTitles));
      }
      await Promise.all(tasks);
      // 上一轮聚合还没结束就又被触发了，直接把这一轮丢弃
      if (token !== this.discoverToken) {
        return;
      }
      this.discoverProgress = `${end}/${list.length}`;
      this.discover = interleave(buckets);
    }

    this.discoverLoading = false;
    this.refreshing = false;
    if (this.discover.length === 0) {
      this.discoverError = '暂时没取到内容\n检查网络后重试，或到「搜索」里找漫画';
    }
    this.finishManualRefresh();
  }

  /** 拉单个源的首页入口，结果按源分桶（同名去重） */
  private async collectSource(rule: SourceRule, buckets: ComicBrief[][], seenTitles: string[]): Promise<void> {
    const outcome = await SourceApi.browse(rule, rule.browse[0], 1);
    if (!outcome.ok || outcome.value === undefined) {
      return;
    }
    const items: ComicBrief[] = outcome.value;
    const bucket: ComicBrief[] = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const key = normalizeTitle(item.title);
      if (key.length === 0 || seenTitles.indexOf(key) >= 0) {
        continue;
      }
      seenTitles.push(key);
      bucket.push(item);
    }
    if (bucket.length > 0) {
      buckets.push(bucket);
    }
  }

  private async doSearch(): Promise<void> {
    const kw = this.keyword.trim();
    if (kw.length === 0) {
      promptAction.showToast({ message: '先输入关键词' });
      return;
    }
    // 记录搜索历史
    Library.get().addSearchHistory(kw);
    this.searchHistoryShown = false;
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

  private openCategory(): void {
    router.pushUrl({ url: 'pages/CategoryPage' });
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

  /** 首页顶部的范围切换：只看当前图源 / 全部图源 */
  @Builder
  scopeToggle(label: string, currentOnly: boolean) {
    Text(label)
      .fontSize(Theme.fsLabel)
      .fontWeight(this.homeCurrentOnly === currentOnly ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.homeCurrentOnly === currentOnly ? Theme.onAccent : Theme.textSub)
      .height(30)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.homeCurrentOnly === currentOnly ? Theme.accent : Color.Transparent)
      .borderRadius(Theme.radiusPill)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.switchHomeScope(currentOnly);
      })
  }

  /** 首页范围行：分段控件 + 当前源（可点换源）+ 刷新 */
  @Builder
  homeScopeBar() {
    Row() {
      Row() {
        this.scopeToggle('当前图源', true)
        this.scopeToggle('全部图源', false)
      }
      .padding(3)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusPill)

      if (this.homeCurrentOnly) {
        Row() {
          Text(this.currentSourceName)
            .fontSize(Theme.fsLabel)
            .fontColor(Theme.textSub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(13)
            .fontColor([Theme.textDim])
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 16, right: 14 })
        .backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusPill)
        .margin({ left: Theme.gapS })
        .onClick(() => {
          this.pickCurrentSource();
        })
      }

      Blank()

      Row() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(15)
          .fontColor([this.refreshing ? Theme.textDim : Theme.accent])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusPill)
      .onClick(() => {
        this.refreshHome();
      })
    }
    .width('100%')
    .padding({ left: Theme.gapL, right: Theme.gapL, bottom: Theme.gapM })
  }

  /** 首页副栏：加载中显示进度，加载完显示总数 */
  @Builder
  discoverStatusBar() {
    if (this.discoverLoading) {
      Row() {
        LoadingProgress()
          .width(13)
          .height(13)
          .color(Theme.accent)
        Text(this.homeCurrentOnly
          ? '正在加载当前图源…'
          : `正在聚合全部图源 ${this.discoverProgress}…`)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: Theme.gapL, right: Theme.gapL, bottom: Theme.gapM })
    } else if (this.discover.length > 0) {
      Row() {
        Text(this.homeCurrentOnly
          ? `${this.currentSourceName} · ${this.discover.length} 部`
          : `全部图源 · ${this.discover.length} 部`)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
      }
      .width('100%')
      .padding({ left: Theme.gapL, right: Theme.gapL, bottom: Theme.gapM })
    }
  }

  @Builder
  comicGrid(items: ComicBrief[], showSource: boolean = false) {
    ForEach(this.rows(items), (row: ComicBrief[]) => {
      Row() {
        ForEach(row, (item: ComicBrief) => {
          Column() {
            ComicCard({
              title: item.title,
              cover: item.cover,
              subtitle: item.latest,
              referer: this.refererOf(item.sourceId),
              sourceTag: showSource ? this.sourceNameOf(item.sourceId) : '',
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
    }, (row: ComicBrief[], index: number) => {
      // key 必须带上该行首条漫画：只写 index+length 的话，
      // 换分类后如果条数和行长一样（比如都是 24 条 3 列），
      // ForEach 会认为行没变化，界面就完全不动 —— 这就是「切分类没反应」的原因
      const head = row.length > 0 ? `${row[0].sourceId}_${row[0].comicId}` : 'empty';
      return `row_${index}_${row.length}_${head}`;
    })
  }

  /** 图源显示名；找不到就用 sourceId 兜底，避免空标签 */
  private sourceNameOf(sourceId: string): string {
    const rule = SourceRegistry.get().find(sourceId);
    return rule === null ? sourceId : rule.name;
  }

  @Builder
  discoverTab() {
    Column() {
      this.appHeader()
      this.homeScopeBar()
      this.discoverStatusBar()
      if (this.discover.length === 0 && this.discoverLoading) {
        this.loadingBlock(this.homeCurrentOnly ? '正在加载当前图源…' : '正在聚合全部图源…')
      } else if (this.discover.length === 0 && this.discoverError.length > 0) {
        this.emptyBlock(this.discoverError, '', '重新加载', () => {
          this.refreshHome();
        })
      } else if (this.discover.length === 0) {
        this.emptyBlock('暂时没有内容', '到「搜索」里找找，或下拉刷新', '重新加载', () => {
          this.refreshHome();
        })
      } else {
        // 下拉刷新：Refresh 的子树必须是可滚动组件，List 正好
        Refresh({ refreshing: this.refreshing }) {
          List() {
            ListItem() {
              Column() {
                // 只看当前图源时不重复标注来源；聚合模式才加来源标签
                this.comicGrid(this.discover, !this.homeCurrentOnly)
              }
              .padding({ left: Theme.gapM, right: Theme.gapM, top: Theme.gapS })
            }
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .onRefreshing(() => {
          this.refreshHome();
        })
        .layoutWeight(1)
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
          .onFocus(() => {
            this.blurToken++;
            this.searchHistoryItems = Library.get().searchHistory().slice(0, 10);
            this.searchHistoryShown = true;
          })
          .onBlur(() => {
            // 失焦后延迟一小会再退出历史，给「点历史项」留出触发时间
            const token = ++this.blurToken;
            setTimeout(() => {
              if (token === this.blurToken) {
                this.searchHistoryShown = false;
              }
            }, 200);
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

      Row() {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(18)
          .fontColor([Theme.accent])
      }
      .width(46)
      .height(46)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusM)
      .margin({ left: Theme.gapS })
      .onClick(() => {
        this.openCategory();
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
          this.scopePill('全部图源', true)
          this.scopePill('仅当前源', false)
        }
        .padding(3)
        .backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusPill)
      }
      .alignItems(HorizontalAlign.Start)

      if (!this.searchAll) {
        Row() {
          Text(this.currentSourceName)
            .fontSize(Theme.fsLabel)
            .fontColor(Theme.textSub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(13)
            .fontColor([Theme.textDim])
            .margin({ left: 6 })
        }
        // 左侧是「30 内高 + 3 上下内边距 = 36」的分段控件，
        // 这里必须也是 36，否则右边这颗看起来会小一号
        .height(36)
        .padding({ left: 16, right: 14 })
        .backgroundColor(Theme.surface)
        .borderRadius(Theme.radiusPill)
        .margin({ left: Theme.gapS })
        .onClick(() => {
          this.pickCurrentSource();
        })
      }

      Blank()

      Text(this.searchAll ? `${this.sources.length} 个源参与` : '单源检索')
        .fontSize(Theme.fsCaption)
        .fontColor(Theme.textDim)
    }
    .width('100%')
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapM })
  }

  /** 弹出深色源列表，切当前检索源 */
  private pickCurrentSource(): void {
    if (this.sources.length === 0) {
      return;
    }
    this.sourceSheetShown = true;
  }

  private async switchCurrentSource(id: string): Promise<void> {
    await SourceRegistry.get().setCurrent(id);
    this.refreshSources();
    // 「只看当前图源」模式下换源必须重拉首页；聚合模式不受影响
    if (this.homeCurrentOnly) {
      this.browseIndex = 0;
      this.loadDiscoverForCurrent(0);
    }
    promptAction.showToast({ message: `已切换到 ${this.currentSourceName}` });
  }

  /** 深色底部的「选择当前检索图源」弹窗，替代系统白色 ActionSheet */
  @Builder
  sourceSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 半透明遮罩，点击关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.sourceSheetShown = false;
        })

      Column() {
        Row()
          .width(36)
          .height(4)
          .backgroundColor(Theme.line)
          .borderRadius(2)
          .margin({ top: 10, bottom: 2 })

        Row() {
          Text('选择当前检索图源')
            .fontSize(Theme.fsHeadline)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .layoutWeight(1)
          Text(`${this.sources.length} 个源`)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
        }
        .width('100%')
        .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapM })

        Text('仅对「仅当前源」的搜索与发现页生效')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .width('100%')
          .padding({ left: Theme.gapL, right: Theme.gapL, top: 4 })

        List() {
          ForEach(this.sources, (rule: SourceRule) => {
            ListItem() {
              Row() {
                Text(rule.name)
                  .fontSize(Theme.fsBody)
                  .fontWeight(rule.id === this.currentSourceId ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(rule.id === this.currentSourceId ? Theme.accent : Theme.text)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (rule.id === this.currentSourceId) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(17)
                    .fontColor([Theme.accent])
                    .margin({ left: Theme.gapS })
                }
              }
              .width('100%')
              .height(56)
              .padding({ left: Theme.gapL, right: Theme.gapL })
              .backgroundColor(rule.id === this.currentSourceId ? Theme.accentDim : Theme.surfaceHi)
              .borderRadius(Theme.radiusM)
              .onClick(() => {
                this.sourceSheetShown = false;
                this.switchCurrentSource(rule.id);
              })
            }
            .margin({ left: Theme.gapL, right: Theme.gapL, bottom: Theme.gapS })
          }, (rule: SourceRule) => `srcpick_${rule.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .margin({ top: Theme.gapS })

        Button('取消')
          .width('100%')
          .height(50)
          .fontSize(Theme.fsBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textSub)
          .backgroundColor(Theme.surfaceHi)
          .borderRadius(Theme.radiusM)
          .margin({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapS, bottom: Theme.gapL })
          .onClick(() => {
            this.sourceSheetShown = false;
          })
      }
      .width('100%')
      .height('64%')
      .backgroundColor(Theme.surface)
      .borderRadius({ topLeft: Theme.radiusL, topRight: Theme.radiusL })
      .onClick(() => {
        // 占位：阻止点击弹窗空白处冒泡到遮罩
      })
    }
    .width('100%')
    .height('100%')
  }

  /** 点历史项：回填关键词并搜索 */
  private searchFromHistory(kw: string): void {
    this.keyword = kw;
    this.searchHistoryShown = false;
    this.doSearch();
  }

  @Builder
  searchHistoryPanel() {
    Column() {
      Row() {
        Text('搜索历史')
          .fontSize(Theme.fsHeadline)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Blank()
        Text('清空')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .onClick(() => {
            Library.get().clearSearchHistory();
            this.searchHistoryItems = [];
            this.searchHistoryShown = false;
          })
      }
      .width('100%')
      .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapL, bottom: Theme.gapS })

      List() {
        ForEach(this.searchHistoryItems, (item: string) => {
          ListItem() {
            Row() {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(14)
                .fontColor([Theme.textDim])
              Text(item)
                .fontSize(Theme.fsBody)
                .fontColor(Theme.text)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .margin({ left: Theme.gapM })
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(14)
                .fontColor([Theme.textDim])
                .padding(6)
                .onClick(() => {
                  Library.get().removeSearchHistory(item);
                  this.searchHistoryItems = Library.get().searchHistory().slice(0, 10);
                })
            }
            .width('100%')
            .height(48)
            .padding({ left: Theme.gapL, right: Theme.gapL })
            .onClick(() => {
              this.searchFromHistory(item);
            })
          }
        }, (item: string) => `sh_${item}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(Theme.bg)
  }

  @Builder
  searchTab() {
    Column() {
      this.searchBar()
      this.scopeRow()

      if (this.searchHistoryShown && this.searchHistoryItems.length > 0) {
        this.searchHistoryPanel()
      } else if (this.searchLoading) {
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
              this.comicGrid(this.searchResults, true)
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
      Text(this.sourceNameOf(item.sourceId))
        .fontSize(Theme.fsMicro)
        .fontColor(Theme.accent)
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
      params.comicUrl = item.url;
      params.chapterIndex = item.chapterIndex;
      params.chapterId = item.chapterId;
      params.page = item.page;
      router.pushUrl({ url: 'pages/ReaderPage', params: params });
    })
    .gesture(LongPressGesture().onAction(() => {
      this.confirmDeleteHistory(item);
    }))
  }

  /** 长按继续阅读卡删除该条记录 */
  private confirmDeleteHistory(item: ReadProgress): void {
    promptAction.showDialog({
      title: '删除阅读记录',
      message: `确定删除「${item.title}」的阅读记录吗？`,
      buttons: [
        { text: '取消', color: Theme.textSub },
        { text: '删除', color: '#E5493C' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        Library.get().removeProgress(item.sourceId, item.comicId);
        this.history = Library.get().history();
      }
    }).catch(() => {
      // 用户取消或对话框异常，忽略
    });
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

        Text('拾漫 1.0.2')
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
    Stack() {
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

      if (this.sourceSheetShown) {
        this.sourceSheet()
      }
    }
    .width('100%')
    .height('100%')
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
