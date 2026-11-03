/**
 * 带 Referer 的图片加载器。
 *
 * 为什么需要：部分图源 CDN 开了防盗链（实测松子漫画不带 Referer 直接 403），
 * 而 ArkUI 的 Image(url) 不会带 Referer。只能自己 DOWN 字节流再解成 PixelMap。
 *
 * 内存策略：不做全局 PixelMap 缓存 —— 组件各自持有、卸载时释放，
 * 避免「缓存里的图被 release 了但还在显示」这类黑屏问题。
 * 字节层做了小容量 LRU，滚动回来不用重新下载。
 */

import { image } from '@kit.ImageKit';
import { Http, HttpHeader, defaultHeaders } from './Http';

const MAX_BYTES_ENTRIES: number = 24;

export class ImageLoader {
  private static bytesCache: Map<string, ArrayBuffer> = new Map<string, ArrayBuffer>();
  private static order: string[] = [];

  private static remember(key: string, data: ArrayBuffer): void {
    if (ImageLoader.bytesCache.has(key)) {
      return;
    }
    ImageLoader.bytesCache.set(key, data);
    ImageLoader.order.push(key);
    while (ImageLoader.order.length > MAX_BYTES_ENTRIES) {
      const oldest = ImageLoader.order.shift();
      if (oldest !== undefined) {
        ImageLoader.bytesCache.delete(oldest);
      }
    }
  }

  /** 下载并解码为 PixelMap；失败返回 null */
  static async load(url: string, referer: string): Promise<image.PixelMap | null> {
    if (url.length === 0) {
      return null;
    }
    try {
      let buffer = ImageLoader.bytesCache.get(url);
      if (buffer === undefined) {
        const headers: HttpHeader[] = defaultHeaders(referer);
        headers.push(new HttpHeader('Accept', 'image/webp,image/jpeg,image/png,image/*,*/*'));
        let data = await Http.getBytes(url, headers);
        // 两种 CDN 策略是相反的：
        //   松子漫画 —— 不带 Referer 直接 403，必须带；
        //   云北漫画用的 oss.mkzcdn.com —— 带外站 Referer 反而 403，不带才给。
        // 所以带 Referer 失败时再用「不带 Referer」重试一次，比给每个源加开关省事。
        if (data === null && referer.length > 0) {
          const plain: HttpHeader[] = defaultHeaders('');
          plain.push(new HttpHeader('Accept', 'image/webp,image/jpeg,image/png,image/*,*/*'));
          data = await Http.getBytes(url, plain);
        }
        if (data === null) {
          return null;
        }
        buffer = data;
      }
      const source = image.createImageSource(buffer);
      const pixelMap = await source.createPixelMap();
      source.release();
      // 解码成功后再进缓存，避免把错误页 HTML 当图片锁死 LRU
      ImageLoader.remember(url, buffer);
      return pixelMap;
    } catch (error) {
      ImageLoader.bytesCache.delete(url);
      const orderIndex = ImageLoader.order.indexOf(url);
      if (orderIndex >= 0) {
        ImageLoader.order.splice(orderIndex, 1);
      }
      return null;
    }
  }
}
