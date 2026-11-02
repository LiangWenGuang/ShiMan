import { router, promptAction } from '@kit.ArkUI';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceApi } from '../source/SourceApi';
import { SourceRule } from '../rule/Rules';
import { Theme } from '../theme/Theme';

class SourceState {
  rule: SourceRule;
  enabled: boolean;
  checking: boolean = false;
  result: string = '';

  constructor(rule: SourceRule, enabled: boolean) {
    this.rule = rule;
    this.enabled = enabled;
  }
}

@Entry
@Component
struct SourceManagerPage {
  @State items: SourceState[] = [];
  @State currentId: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    const registry = SourceRegistry.get();
    const all = registry.all();
    const list: SourceState[] = [];
    for (let i = 0; i < all.length; i++) {
      list.push(new SourceState(all[i], registry.isEnabled(all[i].id)));
    }
    this.items = list;
    this.currentId = registry.currentSourceId();
  }

  private async toggle(item: SourceState): Promise<void> {
    const registry = SourceRegistry.get();
    const next = !item.enabled;
    await registry.setEnabled(item.rule.id, next);
    // 至少保留一个可用源
    if (registry.enabled().length === 0) {
      await registry.setEnabled(item.rule.id, true);
      promptAction.showToast({ message: '至少要保留一个图源' });
      this.reload();
      return;
    }
    this.reload();
    promptAction.showToast({ message: next ? `已启用 ${item.rule.name}` : `已停用 ${item.rule.name}` });
  }

  private async makeCurrent(item: SourceState): Promise<void> {
    if (!item.enabled) {
      promptAction.showToast({ message: '请先启用该图源' });
      return;
    }
    await SourceRegistry.get().setCurrent(item.rule.id);
    this.currentId = item.rule.id;
    promptAction.showToast({ message: `已切换到 ${item.rule.name}` });
  }

  private async selfCheck(item: SourceState): Promise<void> {
    item.checking = true;
    this.items = this.items.slice();
    const outcome = await SourceApi.search(item.rule, '漫画', 1);
    item.checking = false;
    if (outcome.ok && outcome.value !== undefined) {
      item.result = `可用 · 返回 ${outcome.value.length} 条`;
    } else {
      item.result = `不可用 · ${outcome.message}`;
    }
    this.items = this.items.slice();
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
      Text('图源管理')
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
  smallButton(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(Theme.fsCaption)
      .fontWeight(FontWeight.Medium)
      .fontColor(active ? Theme.accent : Theme.textSub)
      .height(32)
      .padding({ left: 14, right: 14 })
      .backgroundColor(Theme.surfaceHi)
      .borderRadius(Theme.radiusPill)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        action();
      })
  }

  @Builder
  card(item: SourceState) {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(item.rule.name)
              .fontSize(Theme.fsHeadline - 1)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
            if (item.rule.id === this.currentId) {
              Text('当前')
                .fontSize(Theme.fsMicro)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.onAccent)
                .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                .backgroundColor(Theme.accent)
                .borderRadius(Theme.radiusS - 2)
                .margin({ left: 8 })
            }
          }

          Text(item.rule.note.length > 0 ? item.rule.note : item.rule.baseUrl)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .margin({ top: 5 })
            .lineHeight(18)
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: item.enabled })
          .selectedColor(Theme.accent)
          .onChange(() => {
            this.toggle(item);
          })
      }
      .width('100%')

      Row() {
        this.smallButton(item.checking ? '检测中…' : '连通性自检', true, () => {
          this.selfCheck(item);
        })
        Text('设为当前源')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textSub)
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor(Theme.surfaceHi)
          .borderRadius(Theme.radiusPill)
          .textAlign(TextAlign.Center)
          .margin({ left: Theme.gapS })
          .onClick(() => {
            this.makeCurrent(item);
          })
        Blank()
        Text(item.rule.chapters.json.enabled() || item.rule.images.type === 'web' ? '需页面解析' : '接口直连')
          .fontSize(Theme.fsMicro)
          .fontColor(Theme.textDim)
      }
      .width('100%')
      .margin({ top: Theme.gapM })

      if (item.result.length > 0) {
        Text(item.result)
          .fontSize(Theme.fsCaption)
          .fontColor(item.result.startsWith('可用') ? Theme.ok : Theme.warn)
          .lineHeight(19)
          .width('100%')
          .margin({ top: Theme.gapS })
      }
    }
    .width('100%')
    .padding(Theme.gapL)
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.radiusL)
    .margin({ bottom: Theme.gapM })
  }

  build() {
    Column() {
      this.navBar()
      List() {
        ListItem() {
          Text('启用的图源会参与发现页、搜索与换源。关掉不用的源可以显著减少无效请求。')
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .lineHeight(20)
            .width('100%')
            .padding({ left: Theme.gapL + 4, right: Theme.gapL + 4, top: Theme.gapXs, bottom: Theme.gapL })
        }
        ForEach(this.items, (item: SourceState) => {
          ListItem() {
            this.card(item)
          }
          .padding({ left: Theme.gapL, right: Theme.gapL })
        }, (item: SourceState) => item.rule.id)
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
