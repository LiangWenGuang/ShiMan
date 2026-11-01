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
    } catch (error) {
      // 读取失败按空库处理，不影响使用
    }
    this.ready = true;
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
    const list = this.history();
    const lines: string[] = [];
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      lines.push([
        enc(item.sourceId), enc(item.comicId), enc(item.title), enc(item.cover),
        enc(item.chapterId), String(item.chapterIndex), enc(item.chapterTitle),
        String(item.page), String(item.updatedAt)
      ].join('\t'));
    }
    this.store.put(KEY_PROGRESS, lines.join('\n')).then(() => {
      if (this.store !== null) {
        this.store.flush();
      }
    }).catch(() => {
      // 忽略写入失败
    });
  }
}
