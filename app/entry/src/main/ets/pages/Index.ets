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
import { appVersionLabel } from '../util/AppInfo';

/** 网格每行卡片数 */


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

/** 图源搜索状态与结果独立展示，避免跨源混排。 */
@Observed
class SearchGroup {
  sourceId: string = '';
  name: string = '';
  items: ComicBrief[] = [];
  status: string = '等待搜索';
}

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  // 以可用宽度决定网格列数，兼容窄屏和横屏。
  @State gridColumns: number = 3;

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
  @State searchGroups: SearchGroup[] = [];
  @State searchCompleted: number = 0;
  @State shelfFilter: string = '';
  @State shelfSort: number = 0;
  @State shelfEditing: boolean = false;
  @State shelfSelected: string[] = [];
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
  // 每次搜索独立编号，只允许最近一次请求更新页面。
  private searchToken: number = 0;

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
    if (previousSourceId !== this.currentSourceId && !this.searchAll) {
      this.resetSearch();
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
    const token = ++this.discoverToken;
    this.discoverLoading = false;
    this.discoverProgress = '';
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
    // 切源或切换聚合模式后，旧请求不能覆盖新列表和加载状态。
    if (token !== this.discoverToken) {
      return;
    }
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
    this.resetSearch();
    const token = this.searchToken;
    Library.get().addSearchHistory(kw);
    this.searchHistoryShown = false;
    const registry = SourceRegistry.get();
    const current = registry.find(registry.currentSourceId());
    const list: SourceRule[] = this.searchAll ? registry.enabled() : (current === null ? [] : [current]);
    this.searchGroups = list.map((rule: SourceRule): SearchGroup => {
      const group = new SearchGroup();
      group.sourceId = rule.id;
      group.name = rule.name;
      return group;
    });
    if (list.length === 0) {
      this.searchDone = true;
      this.searchError = '还没有启用任何图源';
      return;
    }
    this.searchLoading = true;
    // 三个工作协程共享游标，先完成的源立即展示；取消后不再领取后续源。
    let next: number = 0;
    const worker = async (): Promise<void> => {
      while (token === this.searchToken && next < list.length) {
        const index = next++;
        this.searchGroups[index].status = '正在搜索…';
        this.searchGroups = this.searchGroups.slice();
        try {
          const result = await SourceApi.search(list[index], kw, 1);
          if (token !== this.searchToken) return;
          const group = this.searchGroups[index];
          group.items = result.ok && result.value !== undefined ? result.value : [];
          group.status = group.items.length > 0 ? group.items.length + ' 部' : result.message || '暂无匹配结果';
        } catch (error) {
          if (token !== this.searchToken) return;
          this.searchGroups[index].status = '请求失败，可重新搜索';
        }
        this.searchCompleted++;
        this.searchGroups = this.searchGroups.slice();
        this.searchResults = [];
        this.searchGroups.forEach((group: SearchGroup) => {
          this.searchResults = this.searchResults.concat(group.items);
        });
      }
    };
    const workers: Promise<void>[] = [];
    for (let i = 0; i < Math.min(3, list.length); i++) workers.push(worker());
    await Promise.all(workers);
    if (token !== this.searchToken) return;
    this.searchLoading = false;
    this.searchDone = true;
  }

  private cancelSearch(): void {
    // 已发出的网络请求由超时回收，令牌使其结果失效并阻止排队图源继续请求。
    this.searchToken++;
    this.searchLoading = false;
    this.searchDone = true;
    this.searchGroups.forEach((group: SearchGroup) => {
      if (group.status === '等待搜索' || group.status === '正在搜索…') group.status = '已取消';
    });
    this.searchGroups = this.searchGroups.slice();
  }

  private resetSearch(): void {
    // 搜索范围改变后同时清空旧结果并使在途请求失效，避免标签与内容不一致。
    this.searchToken++;
    this.searchLoading = false;
    this.searchDone = false;
    this.searchResults = [];
    this.searchGroups = [];
    this.searchCompleted = 0;
    this.searchError = '';
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
      if (current.length === this.gridColumns) {
        out.push(current);
        current = [];
      }
    }
    if (current.length > 0) {
      out.push(current);
    }
    return out;
  }

  private paddingSlots(count: number): number[] {
    const slots: number[] = [];
    for (let i = 0; i < count; i++) slots.push(i);
    return slots;
  }

  private shelfRows(): ShelfItem[][] {
    const out: ShelfItem[][] = [];
    let current: ShelfItem[] = [];
    // 按名称筛选并排序副本，不改原始持久化顺序。
    const filtered = this.shelf.filter((item: ShelfItem) => item.title.toLowerCase().indexOf(this.shelfFilter.trim().toLowerCase()) >= 0);
    filtered.sort((left: ShelfItem, right: ShelfItem): number => this.shelfSort === 0 ? right.updatedAt - left.updatedAt : left.title.localeCompare(right.title));
    for (let i = 0; i < filtered.length; i++) {
      current.push(filtered[i]);
      if (current.length === this.gridColumns) {
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
  /**
   * 分组标题。
   * hint 由调用方按 key 传入、**在 builder 里现算**，不能直接把
   * `${this.history.length} 条记录` 这种字符串当参数传 —— @Builder 按值传参，
   * 传进去那一刻的字符串就固定了，条数变了标题不会跟着变。
   */
  @Builder
  sectionTitle(title: string, hintKey: string) {
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
      if (this.sectionHint(hintKey).length > 0) {
        Text(this.sectionHint(hintKey))
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
      }
    }
    .width('100%')
    .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapXl, bottom: Theme.gapM })
  }

  /** 分组标题右侧的副文案，读 @State 保证随数据变化更新 */
  private sectionHint(key: string): string {
    if (key === 'history') {
      return this.history.length > 0 ? `${this.history.length} 条记录` : '';
    }
    if (key === 'shelf') {
      return this.shelf.length > 0 ? `${this.shelf.length} 本` : '';
    }
    return '';
  }

  /** 占位块正文：stateKey 非空时读对应 @State，保证错误文案能随状态更新 */
  private stateText(key: string, fallback: string): string {
    if (key === 'homeError') {
      return this.discoverError.length > 0 ? this.discoverError : fallback;
    }
    if (key === 'searchError') {
      return this.searchError.length > 0 ? this.searchError : fallback;
    }
    return fallback;
  }

  /**
   * 居中占位：图标 + 主文案 + 副文案 + 可选按钮。
   * 错误文案通过 stateKey 传「哪个状态」，在 builder 内部现读 —— 
   * 直接把 this.discoverError 当参数传会被冻结在第一次渲染的字符串上。
   */
  @Builder
  emptyBlock(title: string, hint: string, action: string, onAction: () => void, stateKey: string) {
    Column() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(38)
        .fontColor([Theme.line])
      Text(this.stateText(stateKey, title))
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

  /** 单张卡片。item 由 ForEach 提供，随行 key 变化一起重建，不存在「参数不刷新」问题 */
  @Builder
  comicCell(item: ComicBrief, showSource: boolean) {
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
  }

  /** 行 key 必须带内容，否则换源后条数一样时 ForEach 认为「行没变」 */
  private rowKey(row: ComicBrief[], index: number): string {
    const head = row.length > 0 ? `${row[0].sourceId}_${row[0].comicId}` : 'empty';
    return `row_${index}_${row.length}_${head}`;
  }

  /** 书架行的 key，同样要带内容，否则增删后条数相同时不重排 */
  private shelfRowKey(row: ShelfItem[], index: number): string {
    const head = row.length > 0 ? `${row[0].sourceId}_${row[0].comicId}` : 'empty';
    return `srow_${index}_${row.length}_${head}`;
  }

  /**
   * 首页网格。
   *
   * ★ 这里必须直接读 `this.discover`，不能像以前那样写成
   * `comicGrid(this.discover)` 把数组当 @Builder 参数传进去 ——
   * ArkUI 的 @Builder 是**按值传参**，参数变了不会触发内部刷新，
   * 表现就是「换数据源后源名变了、下面还是上一家的漫画」。
   * 只有 builder 体内直接读状态变量，依赖才会被记录、才会重渲染。
   */
  @Builder
  homeGrid() {
    ForEach(this.rows(this.discover), (row: ComicBrief[]) => {
      Row() {
        ForEach(row, (item: ComicBrief) => {
          this.comicCell(item, !this.homeCurrentOnly)
        }, (item: ComicBrief) => `${item.sourceId}_${item.comicId}`)
        if (row.length < this.gridColumns) {
          ForEach(this.paddingSlots(this.gridColumns - row.length), (pad: number) => {
            Column().layoutWeight(1)
          }, (pad: number) => `pad_${pad}`)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ bottom: 18 })
    }, (row: ComicBrief[], index: number) => this.rowKey(row, index))
  }

  /** 搜索结果网格，同样直接读 this.searchResults */
  @Builder
  searchGrid() {
    ForEach(this.rows(this.searchResults), (row: ComicBrief[]) => {
      Row() {
        ForEach(row, (item: ComicBrief) => {
          this.comicCell(item, true)
        }, (item: ComicBrief) => `${item.sourceId}_${item.comicId}`)
        if (row.length < this.gridColumns) {
          ForEach(this.paddingSlots(this.gridColumns - row.length), (pad: number) => {
            Column().layoutWeight(1)
          }, (pad: number) => `pad_${pad}`)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ bottom: 18 })
    }, (row: ComicBrief[], index: number) => this.rowKey(row, index))
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
        this.emptyBlock('', '', '重新加载', () => {
          this.refreshHome();
        }, 'homeError')
      } else if (this.discover.length === 0) {
        this.emptyBlock('暂时没有内容', '到「搜索」里找找，或下拉刷新', '重新加载', () => {
          this.refreshHome();
        }, '')
      } else {
        // 下拉刷新：Refresh 的子树必须是可滚动组件，List 正好
        Refresh({ refreshing: this.refreshing }) {
          List() {
            ListItem() {
              Column() {
                // 只看当前图源时不重复标注来源；聚合模式才加来源标签
                this.homeGrid()
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
        if (this.searchAll !== all) {
          this.resetSearch();
        }
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
    if (!this.searchAll) {
      this.resetSearch();
    }
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
      } else if (this.searchGroups.length > 0) {
        Column() {
          Row() {
            Text('已完成 ' + this.searchCompleted + '/' + this.searchGroups.length + ' 个图源 · ' + this.searchResults.length + ' 部')
              .fontSize(Theme.fsCaption).fontColor(Theme.textSub).layoutWeight(1)
            if (this.searchLoading) {
              Button('取消').fontSize(Theme.fsLabel).onClick(() => { this.cancelSearch(); })
            }
          }.width('100%').padding(Theme.gapL)
          List({ space: Theme.gapL }) {
            ForEach(this.searchGroups, (group: SearchGroup) => {
              ListItem() {
                Column({ space: Theme.gapM }) {
                  Row() {
                    Text(group.name).fontSize(Theme.fsHeadline).fontWeight(FontWeight.Medium).fontColor(Theme.text)
                    Blank()
                    Text(group.status).fontSize(Theme.fsCaption).fontColor(Theme.textSub)
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '55%' })
                  }.width('100%').padding({ left: Theme.gapL, right: Theme.gapL })
                  if (group.items.length > 0) {
                    List({ space: Theme.gapM }) {
                      ForEach(group.items, (item: ComicBrief) => {
                        ListItem() {
                          ComicCard({ title: item.title, cover: item.cover, subtitle: item.latest,
                            referer: this.refererOf(item.sourceId), starred: this.isFavorite(item.sourceId, item.comicId),
                            onTap: () => { this.openDetail(item); } })
                        }.width(112)
                      }, (item: ComicBrief) => item.sourceId + '|' + item.comicId)
                    }.listDirection(Axis.Horizontal).height(250).width('100%').scrollBar(BarState.Off)
                      .padding({ left: Theme.gapL, right: Theme.gapL })
                  }
                }.width('100%').padding({ top: Theme.gapM, bottom: Theme.gapM })
                  .backgroundColor(Theme.surface).borderRadius(Theme.radiusM)
              }
            }, (group: SearchGroup) => group.sourceId + '|' + group.status + '|' + group.items.length)
          }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        }.layoutWeight(1).width('100%')
      } else {
        this.emptyBlock(this.searchDone ? '没有可用结果' : '搜索漫画',
          this.searchError.length > 0 ? this.searchError : '输入关键词，按图源分别浏览搜索结果', '', () => {}, '')
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
      params.pageOffset = item.pageOffset;
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

  private async removeSelectedShelf(): Promise<void> {
    // 删除以用户确认的快照为准，不影响收藏和阅读记录。
    const keys = this.shelfSelected.slice();
    try {
      const result = await promptAction.showDialog({ title: '移出书架', message: '移除所选 ' + keys.length + ' 部作品？收藏与阅读记录会保留。',
        buttons: [{ text: '取消', color: Theme.textSub }, { text: '移除', color: Theme.warn }] });
      if (result.index !== 1) return;
      await Library.get().removeShelfBatch(keys);
      this.shelf = Library.get().shelf(); this.shelfSelected = [];
    } catch (error) {
      // 对话框取消时不改变书架。
    }
  }

  @Builder
  shelfCard(item: ShelfItem) {
    Column() {
      if (this.shelfEditing) {
        Text(this.shelfSelected.indexOf(item.sourceId + '|' + item.comicId) >= 0 ? '已选择 ✓' : '点击选择')
          .fontSize(Theme.fsCaption).fontColor(Theme.accent)
      }
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
      if (this.shelfEditing) {
        const key = item.sourceId + '|' + item.comicId;
        this.shelfSelected = this.shelfSelected.indexOf(key) >= 0 ? this.shelfSelected.filter((value: string) => value !== key) : this.shelfSelected.concat([key]);
        return;
      }
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
      ListItem() {
        Column({ space: Theme.gapS }) {
          TextInput({ placeholder: '筛选书架作品', text: this.shelfFilter })
            .fontColor(Theme.text).backgroundColor(Theme.surface).onChange((value: string) => { this.shelfFilter = value; })
          Row({ space: Theme.gapS }) {
            Button(this.shelfSort === 0 ? '最近加入' : '名称排序').fontSize(Theme.fsLabel)
              .onClick(() => { this.shelfSort = this.shelfSort === 0 ? 1 : 0; })
            Blank()
            if (this.shelfEditing) {
              Button('移除 ' + this.shelfSelected.length).fontSize(Theme.fsLabel)
                .enabled(this.shelfSelected.length > 0).onClick(() => { this.removeSelectedShelf(); })
            }
            Button(this.shelfEditing ? '完成' : '整理').fontSize(Theme.fsLabel).onClick(() => {
              this.shelfEditing = !this.shelfEditing; this.shelfSelected = [];
            })
          }.width('100%')
        }.padding(Theme.gapL)
      }
      if (this.history.length > 0) {
        ListItem() {
          this.sectionTitle('继续阅读', 'history')
        }
        ListItem() {
          Scroll() {
            Row() {
              ForEach(this.history.slice(0, 8), (item: ReadProgress) => {
                this.historyCard(item)
              }, (item: ReadProgress) => `h_${item.sourceId}_${item.comicId}_${item.chapterIndex}_${item.page}`)
            }
            .padding({ left: Theme.gapL })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
      }

      ListItem() {
        this.sectionTitle('我的书架', 'shelf')
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
              if (row.length < this.gridColumns) {
                ForEach(this.paddingSlots(this.gridColumns - row.length), (pad: number) => {
                  Column().layoutWeight(1)
                }, (pad: number) => `spad_${pad}`)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ left: Theme.gapM, right: Theme.gapM, bottom: 18 })
          }
        }, (row: ShelfItem[], index: number) => this.shelfRowKey(row, index))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  // ─────────────────────────── 我的 ───────────────────────────

  /**
   * 「我的」页的一行。右侧数值按 valueKey **现算**（读 @State），
   * 否则收藏/书架/历史数量变了这里不会跟着变。
   */
  @Builder
  settingRow(title: string, valueKey: string, action: () => void) {
    Row() {
      Text(title)
        .fontSize(Theme.fsBody)
        .fontColor(Theme.text)
      Blank()
      Text(this.mineValue(valueKey))
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

  /** 「我的」页各行的数值，读 @State 保证随数据变化刷新 */
  private mineValue(key: string): string {
    if (key === 'favorites') {
      return this.favorites.length > 0 ? `${this.favorites.length} 部` : '暂无';
    }
    if (key === 'shelf') {
      return this.shelf.length > 0 ? `${this.shelf.length} 本` : '暂无';
    }
    if (key === 'sources') {
      return `${this.sources.length} 个已启用`;
    }
    if (key === 'history') {
      return `${this.history.length} 条`;
    }
    return '';
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
          this.settingRow('我的收藏', 'favorites', () => {
            this.openFavorites();
          })
          Divider().color(Theme.line).margin({ left: Theme.gapL, right: Theme.gapL })
          this.settingRow('书架', 'shelf', () => {
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
          this.settingRow('图源管理', 'sources', () => {
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
          this.settingRow('阅读历史', 'history', () => {
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

        Text(appVersionLabel())
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
    .onAreaChange((oldArea: Area, area: Area) => {
      const width = Number(area.width);
      this.gridColumns = Math.max(2, Math.min(6, Math.floor(width / 112)));
    })
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
