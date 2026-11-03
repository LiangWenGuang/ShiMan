/*
 * 图片加载与 LRU 字节缓存。
 * 只在 PixelMap 解码成功后才写入缓存，避免把损坏响应「毒化」后续请求。
 */
import { image } from '@kit.ImageKit';
import { Http, HttpHeader } from './Http';

class CacheEntry {
  url: string = '';
  bytes: ArrayBuffer = new ArrayBuffer(0);
  lastAccess: number = 0;
}

export class ImageLoader {
  private static readonly MAX_ENTRIES = 48;
  private static readonly MAX_CACHE_BYTES = 24 * 1024 * 1024;
  private static readonly MAX_CONCURRENT = 4;
  private static bytesCache: Map<string, CacheEntry> = new Map();
  private static cacheBytes: number = 0;
  private static activeLoads: number = 0;
  private static waiting: Array<() => void> = [];
  private static failures: Map<string, string> = new Map();

  static clearCache(): void {
    ImageLoader.bytesCache.clear();
    ImageLoader.cacheBytes = 0;
  }

  static failureOf(url: string): string {
    return ImageLoader.failures.get(url) ?? '图片加载失败';
  }

  private static async acquire(): Promise<void> {
    if (ImageLoader.activeLoads < ImageLoader.MAX_CONCURRENT) {
      ImageLoader.activeLoads++;
      return;
    }
    await new Promise<void>((resolve: () => void) => ImageLoader.waiting.push(resolve));
  }

  private static releaseLoad(): void {
    const next = ImageLoader.waiting.shift();
    if (next !== undefined) {
      // 槽位直接交接给队首任务，activeLoads 保持不变，避免新请求插队导致超额并发。
      next();
      return;
    }
    ImageLoader.activeLoads = Math.max(0, ImageLoader.activeLoads - 1);
  }

  private static touch(url: string, bytes: ArrayBuffer): void {
    const now = Date.now();
    if (ImageLoader.bytesCache.has(url)) {
      const e = ImageLoader.bytesCache.get(url)!;
      ImageLoader.cacheBytes -= e.bytes.byteLength;
      e.bytes = bytes;
      e.lastAccess = now;
      ImageLoader.cacheBytes += bytes.byteLength;
      return;
    }
    while (ImageLoader.bytesCache.size >= ImageLoader.MAX_ENTRIES ||
      ImageLoader.cacheBytes + bytes.byteLength > ImageLoader.MAX_CACHE_BYTES) {
      let oldest = '';
      let oldestT = Number.MAX_VALUE;
      ImageLoader.bytesCache.forEach((v, k) => {
        if (v.lastAccess < oldestT) {
          oldestT = v.lastAccess;
          oldest = k;
        }
      });
      if (oldest.length > 0) {
        const removed = ImageLoader.bytesCache.get(oldest);
        if (removed !== undefined) ImageLoader.cacheBytes -= removed.bytes.byteLength;
        ImageLoader.bytesCache.delete(oldest);
      } else {
        break;
      }
    }
    const e = new CacheEntry();
    e.url = url;
    e.bytes = bytes;
    e.lastAccess = now;
    ImageLoader.bytesCache.set(url, e);
    ImageLoader.cacheBytes += bytes.byteLength;
  }

  static async loadPixelMap(url: string, headers: HttpHeader[],
    isCurrent?: () => boolean): Promise<image.PixelMap | null> {
    if (url.length === 0) {
      ImageLoader.failures.set(url, '空图片地址');
      return null;
    }
    await ImageLoader.acquire();
    try {
      // 长列表快速滚动时，排队任务可能已经失效；拿到槽位后立即取消，避免无效下载。
      if (isCurrent !== undefined && !isCurrent()) return null;
      let bytes: ArrayBuffer | null = null;
      const cached = ImageLoader.bytesCache.get(url);
      if (cached !== undefined) {
        cached.lastAccess = Date.now();
        bytes = cached.bytes;
      } else {
        const response = await Http.getBytesDetailed(url, headers);
        bytes = response.bytes;
        if (isCurrent !== undefined && !isCurrent()) return null;
        if (bytes === null) ImageLoader.failures.set(url, response.error);
      }
      if (bytes === null || bytes.byteLength === 0) {
        return null;
      }
      const source = image.createImageSource(bytes);
      try {
        if (isCurrent !== undefined && !isCurrent()) return null;
        const pixelMap = await source.createPixelMap();
        // 仅在解码成功后缓存，防止把 404/HTML/截断响应写进 LRU。
        ImageLoader.touch(url, bytes);
        ImageLoader.failures.delete(url);
        return pixelMap;
      } finally {
        // PixelMap 独立持有解码结果，释放源对象避免长列表持续占用解码资源。
        source.release();
      }
    } catch (e) {
      // 解码失败时丢掉可能已污染的缓存条目
      const removed = ImageLoader.bytesCache.get(url);
      if (removed !== undefined) ImageLoader.cacheBytes -= removed.bytes.byteLength;
      ImageLoader.bytesCache.delete(url);
      if (!ImageLoader.failures.has(url)) ImageLoader.failures.set(url, '图片解码失败');
      return null;
    } finally {
      ImageLoader.releaseLoad();
    }
  }
}
