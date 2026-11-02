import { router, promptAction } from '@kit.ArkUI';
import { SourceRegistry } from '../source/SourceRegistry';
import { ShelfItem } from '../model/Models';
import { Library } from '../store/Library';
import { DetailParams } from '../model/RouteParams';
import { RemoteImage } from '../view/RemoteImage';
import { Theme } from '../theme/Theme';

const COLUMNS: number = 3;

/**
 * 我的收藏。
 *
 * 和「书架」的区别：书架是「在追的」，带阅读进度；收藏是「想留着的」，
 * 只做星标，不参与追更。两者互不影响，可以同时存在。
 */
@Entry
@Component
struct FavoritesPage {
  @State items: ShelfItem[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  onPageShow(): void {
    this.reload();
  }

  private reload(): void {
    this.items = Library.get().favorites().slice();
  }

  private refererOf(sourceId: string): string {
    const rule = SourceRegistry.get().find(sourceId);
    return rule === null ? '' : rule.baseUrl;
  }

  private openDetail(item: ShelfItem): void {
    const params: DetailParams = new DetailParams();
    params.sourceId = item.sourceId;
    params.comicId = item.comicId;
    params.url = item.url;
    params.title = item.title;
    router.pushUrl({ url: 'pages/DetailPage', params: params });
  }

  private async unfavorite(item: ShelfItem): Promise<void> {
    await Library.get().removeFavorite(item.sourceId, item.comicId);
    this.reload();
    promptAction.showToast({ message: `已取消收藏《${item.title}》` });
  }

  private rows(): ShelfItem[][] {
    const out: ShelfItem[][] = [];
    let current: ShelfItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      current.push(this.items[i]);
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

  @Builder
  navBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([Theme.text])
          .margin({ right: 4 })
        Text('返回')
          .fontSize(Theme.fsBody)
          .fontColor(Theme.text)
      }
      .height(44)
      .onClick(() => {
        router.back();
      })
      Blank()
      Text('我的收藏')
        .fontSize(Theme.fsBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Blank()
      Text(`${this.items.length} 部`)
        .fontSize(Theme.fsLabel)
        .fontColor(Theme.textDim)
    }
    .width('100%')
    .height(56)
    .padding({ left: Theme.gapM, right: Theme.gapL })
  }

  @Builder
  card(item: ShelfItem) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        RemoteImage({
          url: item.cover,
          referer: this.refererOf(item.sourceId),
          ratio: 0.75,
          corner: Theme.radiusM
        })
        Row() {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(12)
            .fontColor(['#FFC46B'])
        }
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .backgroundColor('#99000000')
        .borderRadius(Theme.radiusPill)
        .margin({ top: 6, right: 6 })
      }
      .width('100%')

      Text(item.title)
        .fontSize(Theme.fsLabel + 1)
        .lineHeight(19)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
        .height(38)
        .width('100%')

      Text(item.author.length > 0 ? item.author : '未知作者')
        .fontSize(Theme.fsMicro)
        .fontColor(Theme.textDim)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
        .width('100%')
    }
    .layoutWeight(1)
    .padding({ left: Theme.gapXs, right: Theme.gapXs })
    .onClick(() => {
      this.openDetail(item);
    })
    .gesture(LongPressGesture().onAction(() => {
      this.unfavorite(item);
    }))
  }

  build() {
    Column() {
      this.navBar()
      if (this.items.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.star'))
            .fontSize(42)
            .fontColor([Theme.line])
          Text('还没有收藏')
            .fontSize(Theme.fsBody)
            .fontColor(Theme.textSub)
            .margin({ top: Theme.gapL })
          Text('在漫画详情页点右上角的星标，或长按封面即可收藏')
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            .margin({ top: Theme.gapS })
            .padding({ left: 40, right: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rows(), (row: ShelfItem[]) => {
            ListItem() {
              Row() {
                ForEach(row, (item: ShelfItem) => {
                  this.card(item)
                }, (item: ShelfItem) => `f_${item.sourceId}_${item.comicId}`)
                if (row.length < COLUMNS) {
                  ForEach([1, 2].slice(0, COLUMNS - row.length), (pad: number) => {
                    Column().layoutWeight(1)
                  }, (pad: number) => `fpad_${pad}`)
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .padding({ left: Theme.gapM, right: Theme.gapM, bottom: 18 })
            }
          }, (row: ShelfItem[], index: number) => `frow_${index}_${row.length}`)

          ListItem() {
            Text('长按封面可以取消收藏')
              .fontSize(Theme.fsCaption)
              .fontColor(Theme.textDim)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: Theme.gapS, bottom: 28 })
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
