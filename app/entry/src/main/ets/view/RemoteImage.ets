/**
 * 远程图片组件：走 ImageLoader 带 Referer 下载，兼容开了防盗链的图源。
 * 两种布局模式：
 *   natural=true  —— 按图片原始比例铺满宽度（阅读页正文用）
 *   natural=false —— 固定宽高比（封面用，ratio = 宽/高）
 */

import { image } from '@kit.ImageKit';
import { ImageLoader } from '../net/ImageLoader';

@Component
export struct RemoteImage {
  url: string = '';
  referer: string = '';
  ratio: number = 0.75;
  corner: number = 0;
  natural: boolean = false;
  @State pm: image.PixelMap | undefined = undefined;
  @State failed: boolean = false;
  private token: number = 0;

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
    const current = ++this.token;
    const result = await ImageLoader.load(this.url, this.referer);
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
      this.failed = true;
      return;
    }
    this.release();
    this.pm = result;
  }

  @Builder
  content() {
    if (this.pm !== undefined) {
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
      Image($r('app.media.app_icon'))
        .width(28)
        .height(28)
        .opacity(0.35)
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
    } else {
      Stack() {
        this.content()
      }
      .width('100%')
      .aspectRatio(this.ratio > 0 ? this.ratio : 0.75)
      .backgroundColor('#1E242D')
      .borderRadius(this.corner)
      .clip(true)
    }
  }
}
