/**
 * 通用漫画卡片：封面 + 标题 + 更新角标，网格与列表共用。
 * 角标改成叠在封面底部的渐变压边，比整条半透明色块更耐看，也不吃画面。
 */

import { RemoteImage } from './RemoteImage';
import { Theme } from '../theme/Theme';

@Component
export struct ComicCard {
  title: string = '';
  cover: string = '';
  subtitle: string = '';
  /** 封面下载时带的 Referer，用于绕过图源 CDN 的防盗链 */
  referer: string = '';
  /** 已收藏时在封面右上角打星。用 @Prop：ForEach 的 key 不变时子组件不会重建，
   *  普通成员变量收不到新值，星标就不会亮 */
  @Prop starred: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          RemoteImage({
            url: this.cover,
            referer: this.referer,
            ratio: 0.75,
            corner: Theme.radiusM
          })
          if (this.subtitle.length > 0) {
            Stack({ alignContent: Alignment.BottomStart }) {
              Text(this.subtitle)
                .fontSize(Theme.fsMicro)
                .fontColor('#EAF1FB')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 8, right: 8, top: 12, bottom: 6 })
                .width('100%')
            }
            .width('100%')
            .linearGradient({
              angle: 180,
              colors: [['#00000000', 0.0], ['#C4000000', 1.0]]
            })
            .borderRadius({ bottomLeft: Theme.radiusM, bottomRight: Theme.radiusM })
          }
        }
        .width('100%')

        if (this.starred) {
          Row() {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(11)
              .fontColor(['#FFC46B'])
          }
          .padding({ left: 5, right: 5, top: 3, bottom: 3 })
          .backgroundColor('#99000000')
          .borderRadius(Theme.radiusPill)
          .margin({ top: 6, right: 6 })
        }
      }
      .width('100%')

      Text(this.title)
        .fontSize(Theme.fsLabel + 1)
        .lineHeight(19)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
        .width('100%')
        // 固定两行高度：标题一行的卡片不会把整排压得高低不齐
        .height(38)
    }
    .width('100%')
    .onClick(() => {
      this.onTap();
    })
  }
}
