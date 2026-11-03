/**
 * 远程图片组件：走 ImageLoader 带 Referer 下载，兼容开了防盗链的图源。
 * 两种布局模式：
 *   natural=true  —— 按图片原始比例铺满宽度（阅读页正文用）
 *   natural=false —— 固定宽高比（封面用，ratio = 宽/高）
 */

import { image } from '@kit.ImageKit';
import { ImageLoader } from '../net/ImageLoader';
import { HttpHeader } from '../net/Http';

@Component
export struct RemoteImage {
  @Prop @Watch('imageChanged') url: string = '';
  @Prop @Watch('imageChanged') referer: string = '';
  /** 阅读器懒加载开关；关闭时释放 PixelMap 但保留外层布局占位。 */
  @Prop @Watch('activeChanged') active: boolean = true;
  /** 自然图片真实尺寸就绪后通知阅读器，用于重新校准页内恢复位置。 */
  onReady: (ratio: number) => void = (_ratio: number) => {
  };
  ratio: number = 0.75;
  corner: number = 0;
  natural: boolean = false;
  @State pm: image.PixelMap | undefined = undefined;
  @State failed: boolean = false;
  @State failureText: string = '图片加载失败';
  /** 未取到真实尺寸前的保守比例，保证自然图片在懒加载时仍保留稳定高度。 */
  @State naturalRatio: number = 0.72;
  private token: number = 0;

  private imageChanged(): void {
    // 同一个列表节点被复用时，重新加载地址并清理上一张图的失败状态。
    this.naturalRatio = 0.72;
    this.fetch();
  }

  private activeChanged(): void {
    if (this.active) {
      this.fetch();
    } else {
      this.token++;
      this.release();
    }
  }

  aboutToAppear(): void {
    this.fetch();
  }

  aboutToDisappear(): void {
    this.token++;
    this.release();
  }

  private release(): void {
    const current = this.pm;
    this.pm = undefined;
    if (current !== undefined) {
      try {
        current.release();
      } catch (error) {
        // 已释放则忽略
      }
    }
  }

  private async fetch(): Promise<void> {
    if (!this.active) return;
    const current = ++this.token;
    this.failed = false;
    this.release();
    // 下载接口接收请求头集合；仅对有来源的图片附加防盗链 Referer。
    const headers: HttpHeader[] = [];
    if (this.referer.length > 0) {
      headers.push(new HttpHeader('Referer', this.referer));
    }
    const result = await ImageLoader.loadPixelMap(this.url, headers,
      () => current === this.token && this.active);
    if (current !== this.token) {
      if (result !== null) {
        try {
          result.release();
        } catch (error) {
          // 忽略
        }
      }
      return;
    }
    if (result === null) {
      if (current !== this.token || !this.active) return;
      this.failed = true;
      this.failureText = ImageLoader.failureOf(this.url);
      this.onReady(0);
      return;
    }
    try {
      const info = await result.getImageInfo();
      if (info.size.width > 0 && info.size.height > 0) {
        this.naturalRatio = info.size.width / info.size.height;
      }
    } catch (error) {
      // 尺寸读取失败时保留默认比例，图片本身仍可正常展示。
    }
    if (current !== this.token || !this.active) {
      try {
        result.release();
      } catch (error) {
        // 忽略
      }
      return;
    }
    this.release();
    this.pm = result;
    this.onReady(this.natural ? this.naturalRatio : this.ratio);
  }

  @Builder
  content() {
    if (!this.active) {
      // 关闭懒加载时保留尺寸，不显示转圈，避免长列表滚动时产生大量动画。
      Blank()
    } else if (this.pm !== undefined) {
      if (this.natural) {
        Image(this.pm)
          .width('100%')
          .objectFit(ImageFit.Contain)
      } else {
        Image(this.pm)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(this.corner)
      }
    } else if (this.failed) {
      Column() {
        Image($r('app.media.app_icon'))
          .width(28)
          .height(28)
          .opacity(0.35)
        Text(this.failureText + ' · 点击重试')
          .fontSize(11)
          .fontColor('#A7B2C1')
          .margin({ top: 6 })
      }
    } else {
      LoadingProgress()
        .width(20)
        .height(20)
        .color('#4C8DFF')
        .opacity(0.6)
    }
  }

  build() {
    if (this.natural) {
      Stack() {
        this.content()
      }
      .width('100%')
      .backgroundColor('#0B0E13')
      .aspectRatio(this.naturalRatio)
      // 仅失败占位接管点击；正常封面点击交给卡片，正文点击交给阅读器。
      .hitTestBehavior(this.failed ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.failed) this.fetch();
      })
    } else {
      Stack() {
        this.content()
      }
      .width('100%')
      .aspectRatio(this.ratio > 0 ? this.ratio : 0.75)
      .backgroundColor('#1E242D')
      .borderRadius(this.corner)
      .clip(true)
      .hitTestBehavior(this.failed ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.failed) this.fetch();
      })
    }
  }
}
