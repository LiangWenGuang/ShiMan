import { router, promptAction } from '@kit.ArkUI';
import { Library } from '../store/Library';
import { Theme } from '../theme/Theme';
import { appVersionLabel } from '../util/AppInfo';

@Entry
@Component
struct SettingsPage {
  @State historyCount: number = 0;
  @State shelfCount: number = 0;

  aboutToAppear(): void {
    this.historyCount = Library.get().history().length;
    this.shelfCount = Library.get().shelf().length;
  }

  /** 设置项右侧数值，读 @State 保证随数据变化刷新（不能靠 @Builder 传值） */
  private settingValue(key: string): string {
    if (key === 'history') {
      return `${this.historyCount} 条`;
    }
    if (key === 'shelf') {
      return `${this.shelfCount} 本`;
    }
    return '';
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
      Text('设置')
        .fontSize(Theme.fsBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Blank()
      Text('返回')
        .fontSize(Theme.fsBody)
        .fontColor(Color.Transparent)
    }
    .width('100%')
    .height(56)
    .padding({ left: Theme.gapM, right: Theme.gapM })
  }

  @Builder
  sectionLabel(text: string) {
    Text(text)
      .fontSize(Theme.fsCaption)
      .fontColor(Theme.textDim)
      .width('100%')
      .padding({ left: Theme.gapXs, top: Theme.gapXl, bottom: Theme.gapS })
  }

  @Builder
  /**
   * 设置项一行。右侧数值按 valueKey 现算（读 @State），
   * 不能把 `${this.historyCount} 条` 直接当参数传 —— @Builder 按值传参不会更新。
   */
  row(title: string, valueKey: string, action: () => void) {
    Row() {
      Text(title)
        .fontSize(Theme.fsBody)
        .fontColor(Theme.text)
      Blank()
      Text(this.settingValue(valueKey))
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

  @Builder
  para(text: string) {
    Text(text)
      .fontSize(Theme.fsLabel)
      .fontColor(Theme.textSub)
      .lineHeight(22)
      .width('100%')
  }

  build() {
    Column() {
      this.navBar()
      Scroll() {
        Column() {
          this.sectionLabel('数据')
          Column() {
            this.row('阅读历史', 'history', () => {
              promptAction.showToast({ message: '在「书架」页顶部查看' });
            })
            Divider().color(Theme.line).margin({ left: Theme.gapL, right: Theme.gapL })
            this.row('书架', 'shelf', () => {
              promptAction.showToast({ message: '在「书架」页查看' });
            })
          }
          .width('100%')
          .backgroundColor(Theme.surface)
          .borderRadius(Theme.radiusL)

          this.sectionLabel('阅读')
          Column() {
            this.para('当前版本为竖向连续阅读，点击画面可显示或隐藏控制栏，' +
              '章节底部可切换上一章 / 下一章。横向翻页与双页模式在后续版本提供。')
          }
          .width('100%')
          .padding(Theme.gapL)
          .backgroundColor(Theme.surface)
          .borderRadius(Theme.radiusL)

          this.sectionLabel('关于')
          Column() {
            this.para(appVersionLabel())
            Text('纯 ArkTS 原生实现 · 无广告 · 无登录 · 无数据上传')
              .fontSize(Theme.fsCaption)
              .fontColor(Theme.textDim)
              .lineHeight(19)
              .margin({ top: 6 })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(Theme.gapL)
          .backgroundColor(Theme.surface)
          .borderRadius(Theme.radiusL)

          Blank().height(28)
        }
        .width('100%')
        .padding({ left: Theme.gapL, right: Theme.gapL })
        // 内容比一屏短时 Scroll 会把子组件垂直居中，这里钉回顶部
        .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
