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
  private static bytesCache: Map<string, CacheEntry> = new Map();

  static clearCache(): void {
    ImageLoader.bytesCache.clear();
  }

  private static touch(url: string, bytes: ArrayBuffer): void {
    const now = Date.now();
    if (ImageLoader.bytesCache.has(url)) {
      const e = ImageLoader.bytesCache.get(url)!;
      e.bytes = bytes;
      e.lastAccess = now;
      return;
    }
    if (ImageLoader.bytesCache.size >= ImageLoader.MAX_ENTRIES) {
      let oldest = '';
      let oldestT = Number.MAX_VALUE;
      ImageLoader.bytesCache.forEach((v, k) => {
        if (v.lastAccess < oldestT) {
          oldestT = v.lastAccess;
          oldest = k;
        }
      });
      if (oldest.length > 0) {
        ImageLoader.bytesCache.delete(oldest);
      }
    }
    const e = new CacheEntry();
    e.url = url;
    e.bytes = bytes;
    e.lastAccess = now;
    ImageLoader.bytesCache.set(url, e);
  }

  static async loadPixelMap(url: string, headers: HttpHeader[]): Promise<image.PixelMap | null> {
    try {
      let bytes: ArrayBuffer | null = null;
      const cached = ImageLoader.bytesCache.get(url);
      if (cached !== undefined) {
        cached.lastAccess = Date.now();
        bytes = cached.bytes;
      } else {
        bytes = await Http.getBytes(url, headers);
      }
      if (bytes === null || bytes.byteLength === 0) {
        return null;
      }
      const source = image.createImageSource(bytes);
      try {
        const pixelMap = await source.createPixelMap();
        // 仅在解码成功后缓存，防止把 404/HTML/截断响应写进 LRU。
        ImageLoader.touch(url, bytes);
        return pixelMap;
      } finally {
        // PixelMap 独立持有解码结果，释放源对象避免长列表持续占用解码资源。
        source.release();
      }
    } catch (e) {
      // 解码失败时丢掉可能已污染的缓存条目
      ImageLoader.bytesCache.delete(url);
      return null;
    }
  }
}
