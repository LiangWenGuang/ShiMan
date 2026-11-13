/**
 * 本地库：书架、阅读进度、历史。
 *
 * 序列化刻意不用 JSON.stringify —— 类实例在 ArkTS 里序列化后再取字段
 * 需要反复强转，容易在类型检查阶段出问题。这里用「字段用 \t 分隔、
 * 每个字段先 encodeURIComponent」的紧凑格式，读写都是强类型，且天然容错。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ShelfItem, ReadProgress } from '../model/Models';

const STORE = 'manyu_library';
const KEY_SHELF = 'shelf';
const KEY_PROGRESS = 'progress';
const KEY_FAVORITE = 'favorite';
const KEY_CHAPTER_DESCENDING = 'chapter_descending';
const KEY_CHAPTER_COLUMNS = 'chapter_columns';
const KEY_SEARCH_HISTORY = 'search_history';

function enc(value: string): string {
  return encodeURIComponent(value.length > 0 ? value : '');
}

function dec(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    return value;
  }
}

export class Library {
  private static instance: Library | null = null;
  private store: preferences.Preferences | null = null;
  private shelfItems: ShelfItem[] = [];
  /** 星标收藏：和书架分开存，书架是「在追」，收藏是「想留着」 */
  private favoriteItems: ShelfItem[] = [];
  private progressItems: Map<string, ReadProgress> = new Map<string, ReadProgress>();
  /** 同一个 Preferences 键的写入必须串行，合并高频滚动产生的快照。 */
  private progressPersisting: boolean = false;
  private progressDirty: boolean = false;
  /** 详情页与阅读器共用的目录展示顺序，不影响章节原始索引 */
  private chapterDescending: boolean = false;
  /** 章节目录每行几列（1 或 2），详情页可切换并持久化 */
  private chapterColumnsValue: number = 2;
  /** 搜索历史（新在前，最多存 20 条，展示取前 10） */
  private searchHistoryItems: string[] = [];
  private ready: boolean = false;

  static get(): Library {
    if (Library.instance === null) {
      Library.instance = new Library();
    }
    return Library.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      this.store = await preferences.getPreferences(context, STORE);
      const shelfRaw = await this.store.get(KEY_SHELF, '');
      if (typeof shelfRaw === 'string' && shelfRaw.length > 0) {
        this.shelfItems = this.decodeShelf(shelfRaw);
      }
      const favoriteRaw = await this.store.get(KEY_FAVORITE, '');
      if (typeof favoriteRaw === 'string' && favoriteRaw.length > 0) {
        this.favoriteItems = this.decodeShelf(favoriteRaw);
      }
      const progressRaw = await this.store.get(KEY_PROGRESS, '');
      if (typeof progressRaw === 'string' && progressRaw.length > 0) {
        const list = this.decodeProgress(progressRaw);
        for (let i = 0; i < list.length; i++) {
          this.progressItems.set(this.keyOf(list[i].sourceId, list[i].comicId), list[i]);
        }
      }
      const chapterOrderRaw = await this.store.get(KEY_CHAPTER_DESCENDING, false);
      if (typeof chapterOrderRaw === 'boolean') {
        this.chapterDescending = chapterOrderRaw;
      }
      const chapterColumnsRaw = await this.store.get(KEY_CHAPTER_COLUMNS, 2);
      if (typeof chapterColumnsRaw === 'number') {
        this.chapterColumnsValue = chapterColumnsRaw === 1 ? 1 : 2;
      }
      const historyRaw = await this.store.get(KEY_SEARCH_HISTORY, '');
      if (typeof historyRaw === 'string' && historyRaw.length > 0) {
        this.searchHistoryItems = this.decodeSearchHistory(historyRaw);
      }
    } catch (error) {
      // 读取失败按空库处理，不影响使用
    }
    this.ready = true;
  }

  isChapterDescending(): boolean {
    return this.chapterDescending;
  }

  setChapterDescending(descending: boolean): void {
    if (this.chapterDescending === descending) {
      return;
    }
    this.chapterDescending = descending;
    if (this.store === null) {
      return;
    }
    this.store.put(KEY_CHAPTER_DESCENDING, descending).then(async () => {
      if (this.store !== null) {
        await this.store.flush();
      }
    }).catch(() => {
      // 内存中的偏好仍然生效，下次启动沿用上次成功写入的值
    });
  }

  chapterColumns(): number {
    return this.chapterColumnsValue === 1 ? 1 : 2;
  }

  setChapterColumns(columns: number): void {
    const next = columns === 1 ? 1 : 2;
    if (this.chapterColumnsValue === next) {
      return;
    }
    this.chapterColumnsValue = next;
    if (this.store === null) {
      return;
    }
    this.store.put(KEY_CHAPTER_COLUMNS, next).then(async () => {
      if (this.store !== null) {
        await this.store.flush();
      }
    }).catch(() => {
      // 内存偏好仍生效
    });
  }

  private keyOf(sourceId: string, comicId: string): string {
    return `${sourceId}|${comicId}`;
  }

  private decodeShelf(raw: string): ShelfItem[] {
    const out: ShelfItem[] = [];
    const lines = raw.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.length === 0) {
        continue;
      }
      const parts = line.split('\t');
      if (parts.length < 7) {
        continue;
      }
      const item = new ShelfItem();
      item.sourceId = dec(parts[0]);
      item.comicId = dec(parts[1]);
      item.title = dec(parts[2]);
      item.cover = dec(parts[3]);
      item.author = dec(parts[4]);
      item.url = dec(parts[5]);
      const stamp = parseInt(parts[6], 10);
      item.updatedAt = isNaN(stamp) ? 0 : stamp;
      out.push(item);
    }
    return out;
  }

  private decodeProgress(raw: string): ReadProgress[] {
    const out: ReadProgress[] = [];
    const lines = raw.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.length === 0) {
        continue;
      }
      const parts = line.split('\t');
      if (parts.length < 9) {
        continue;
      }
      const item = new ReadProgress();
      item.sourceId = dec(parts[0]);
      item.comicId = dec(parts[1]);
      item.title = dec(parts[2]);
      item.cover = dec(parts[3]);
      item.chapterId = dec(parts[4]);
      const chapterIndex = parseInt(parts[5], 10);
      item.chapterIndex = isNaN(chapterIndex) ? 0 : chapterIndex;
      item.chapterTitle = dec(parts[6]);
      const page = parseInt(parts[7], 10);
      item.page = isNaN(page) ? 0 : page;
      const stamp = parseInt(parts[8], 10);
      item.updatedAt = isNaN(stamp) ? 0 : stamp;
      // 第 10 列是后加的详情页地址；老记录没有这一列，留空由调用方兜底
      item.url = parts.length > 9 ? dec(parts[9]) : '';
      const offset = parts.length > 10 ? parseFloat(parts[10]) : 0;
      item.pageOffset = isNaN(offset) || offset < 0 ? 0 : offset;
      out.push(item);
    }
    return out;
  }

  shelf(): ShelfItem[] {
    return this.shelfItems.slice();
  }

  isOnShelf(sourceId: string, comicId: string): boolean {
    for (let i = 0; i < this.shelfItems.length; i++) {
      const item = this.shelfItems[i];
      if (item.sourceId === sourceId && item.comicId === comicId) {
        return true;
      }
    }
    return false;
  }

  async addShelf(item: ShelfItem): Promise<void> {
    for (let i = 0; i < this.shelfItems.length; i++) {
      const current = this.shelfItems[i];
      if (current.sourceId === item.sourceId && current.comicId === item.comicId) {
        this.shelfItems[i] = item;
        await this.persistShelf();
        return;
      }
    }
    this.shelfItems.unshift(item);
    await this.persistShelf();
  }

  async removeShelf(sourceId: string, comicId: string): Promise<void> {
    const kept: ShelfItem[] = [];
    for (let i = 0; i < this.shelfItems.length; i++) {
      const item = this.shelfItems[i];
      if (!(item.sourceId === sourceId && item.comicId === comicId)) {
        kept.push(item);
      }
    }
    this.shelfItems = kept;
    await this.persistShelf();
  }

  /** 批量移除书架条目，统一一次持久化，避免逐条写入造成 UI 卡顿。 */
  async removeShelfBatch(keys: string[]): Promise<void> {
    if (keys.length === 0 || this.shelfItems.length === 0) {
      return;
    }
    const removeSet = new Set<string>();
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].length > 0) {
        removeSet.add(keys[i]);
      }
    }
    if (removeSet.size === 0) {
      return;
    }
    const kept: ShelfItem[] = [];
    for (let i = 0; i < this.shelfItems.length; i++) {
      const item = this.shelfItems[i];
      if (!removeSet.has(this.keyOf(item.sourceId, item.comicId))) {
        kept.push(item);
      }
    }
    if (kept.length === this.shelfItems.length) {
      return;
    }
    this.shelfItems = kept;
    await this.persistShelf();
  }

  private async persistShelf(): Promise<void> {
    if (this.store === null) {
      return;
    }
    const lines: string[] = [];
    for (let i = 0; i < this.shelfItems.length; i++) {
      const item = this.shelfItems[i];
      lines.push([
        enc(item.sourceId), enc(item.comicId), enc(item.title), enc(item.cover),
        enc(item.author), enc(item.url), String(item.updatedAt)
      ].join('\t'));
    }
    try {
      await this.store.put(KEY_SHELF, lines.join('\n'));
      await this.store.flush();
    } catch (error) {
      // 忽略
    }
  }

  // ─────────────────────────── 星标收藏 ───────────────────────────

  favorites(): ShelfItem[] {
    return this.favoriteItems.slice();
  }

  isFavorite(sourceId: string, comicId: string): boolean {
    for (let i = 0; i < this.favoriteItems.length; i++) {
      const item = this.favoriteItems[i];
      if (item.sourceId === sourceId && item.comicId === comicId) {
        return true;
      }
    }
    return false;
  }

  async addFavorite(item: ShelfItem): Promise<void> {
    for (let i = 0; i < this.favoriteItems.length; i++) {
      const current = this.favoriteItems[i];
      if (current.sourceId === item.sourceId && current.comicId === item.comicId) {
        this.favoriteItems[i] = item;
        await this.persistFavorites();
        return;
      }
    }
    this.favoriteItems.unshift(item);
    await this.persistFavorites();
  }

  async removeFavorite(sourceId: string, comicId: string): Promise<void> {
    const kept: ShelfItem[] = [];
    for (let i = 0; i < this.favoriteItems.length; i++) {
      const item = this.favoriteItems[i];
      if (!(item.sourceId === sourceId && item.comicId === comicId)) {
        kept.push(item);
      }
    }
    this.favoriteItems = kept;
    await this.persistFavorites();
  }

  private async persistFavorites(): Promise<void> {
    if (this.store === null) {
      return;
    }
    const lines: string[] = [];
    for (let i = 0; i < this.favoriteItems.length; i++) {
      const item = this.favoriteItems[i];
      lines.push([
        enc(item.sourceId), enc(item.comicId), enc(item.title), enc(item.cover),
        enc(item.author), enc(item.url), String(item.updatedAt)
      ].join('\t'));
    }
    try {
      await this.store.put(KEY_FAVORITE, lines.join('\n'));
      await this.store.flush();
    } catch (error) {
      // 忽略
    }
  }

  progress(sourceId: string, comicId: string): ReadProgress | null {
    const found = this.progressItems.get(this.keyOf(sourceId, comicId));
    return found === undefined ? null : found;
  }

  /**
   * 找一本漫画的详情页地址：先看阅读进度，再看书架、收藏。
   * 老版本存下的进度没有 url，只能靠书架兜底 —— 用户基本都会先把书加进书架。
   */
  resolveComicUrl(sourceId: string, comicId: string): string {
    const recorded = this.progress(sourceId, comicId);
    if (recorded !== null && recorded.url.length > 0) {
      return recorded.url;
    }
    const pools: ShelfItem[][] = [this.shelfItems, this.favoriteItems];
    for (let p = 0; p < pools.length; p++) {
      const pool = pools[p];
      for (let i = 0; i < pool.length; i++) {
        const item = pool[i];
        if (item.sourceId === sourceId && item.comicId === comicId && item.url.length > 0) {
          return item.url;
        }
      }
    }
    return '';
  }

  saveProgress(item: ReadProgress): void {
    item.updatedAt = Date.now();
    this.progressItems.set(this.keyOf(item.sourceId, item.comicId), item);
    this.persistProgress();
  }

  removeProgress(sourceId: string, comicId: string): void {
    this.progressItems.delete(this.keyOf(sourceId, comicId));
    this.persistProgress();
  }

  history(): ReadProgress[] {
    const list: ReadProgress[] = [];
    this.progressItems.forEach((value: ReadProgress) => {
      list.push(value);
    });
    list.sort((left: ReadProgress, right: ReadProgress): number => right.updatedAt - left.updatedAt);
    return list;
  }

  private persistProgress(): void {
    if (this.store === null) {
      return;
    }
    this.progressDirty = true;
    if (this.progressPersisting) {
      return;
    }
    this.progressPersisting = true;
    this.flushProgressQueue();
  }

  /** 只保留最新进度快照；上一轮落盘完成前不启动并发写入。 */
  private async flushProgressQueue(): Promise<void> {
    try {
      while (this.progressDirty) {
        this.progressDirty = false;
        const store = this.store;
        if (store === null) {
          return;
        }
        const list = this.history();
        const lines: string[] = [];
        for (let i = 0; i < list.length; i++) {
          const item = list[i];
          lines.push([
            enc(item.sourceId), enc(item.comicId), enc(item.title), enc(item.cover),
            enc(item.chapterId), String(item.chapterIndex), enc(item.chapterTitle),
            String(item.page), String(item.updatedAt), enc(item.url),
            String(Math.max(0, item.pageOffset))
          ].join('\t'));
        }
        try {
          await store.put(KEY_PROGRESS, lines.join('\n'));
          await store.flush();
        } catch (error) {
          // 当前写入失败不应阻塞后续进度更新。
        }
      }
    } finally {
      this.progressPersisting = false;
    }
  }

  // ─────────────────────────── 搜索历史 ───────────────────────────

  private decodeSearchHistory(raw: string): string[] {
    const out: string[] = [];
    const parts = raw.split('\n');
    for (let i = 0; i < parts.length; i++) {
      const value = dec(parts[i]);
      if (value.length > 0) {
        out.push(value);
      }
    }
    return out;
  }

  searchHistory(): string[] {
    return this.searchHistoryItems.slice();
  }

  addSearchHistory(keyword: string): void {
    const kw = keyword.trim();
    if (kw.length === 0) {
      return;
    }
    // 去重：已有则移到最前
    const kept: string[] = [];
    for (let i = 0; i < this.searchHistoryItems.length; i++) {
      if (this.searchHistoryItems[i] !== kw) {
        kept.push(this.searchHistoryItems[i]);
      }
    }
    kept.unshift(kw);
    // 最多存 20 条
    while (kept.length > 20) {
      kept.pop();
    }
    this.searchHistoryItems = kept;
    this.persistSearchHistory();
  }

  removeSearchHistory(keyword: string): void {
    const kept: string[] = [];
    for (let i = 0; i < this.searchHistoryItems.length; i++) {
      if (this.searchHistoryItems[i] !== keyword) {
        kept.push(this.searchHistoryItems[i]);
      }
    }
    this.searchHistoryItems = kept;
    this.persistSearchHistory();
  }

  clearSearchHistory(): void {
    this.searchHistoryItems = [];
    this.persistSearchHistory();
  }

  private persistSearchHistory(): void {
    if (this.store === null) {
      return;
    }
    const lines: string[] = [];
    for (let i = 0; i < this.searchHistoryItems.length; i++) {
      lines.push(enc(this.searchHistoryItems[i]));
    }
    this.store.put(KEY_SEARCH_HISTORY, lines.join('\n')).then(async () => {
      if (this.store !== null) {
        await this.store.flush();
      }
    }).catch(() => {
      // 忽略写入失败
    });
  }
}
