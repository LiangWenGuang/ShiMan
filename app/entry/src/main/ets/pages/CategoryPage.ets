/**
 * 排行榜页：参考 MyComic 的「左类型栏 + 右排行列表」排版。
 * 顶部可切换数据源，左侧是该源的排行/分类类型，右侧是带序号的排行列表。
 * 配色统一走 Theme（深色底 + 蓝调强调），与全局风格一致。
 */

import { router } from '@kit.ArkUI';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceApi } from '../source/SourceApi';
import { SourceRule } from '../rule/Rules';
import { ComicBrief } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { RemoteImage } from '../view/RemoteImage';
import { Theme } from '../theme/Theme';

@Entry
@Component
struct CategoryPage {
  @State sources: SourceRule[] = [];
  /** 本页选中的数据源（不影响全局当前源） */
  @State pageSourceId: string = '';
  @State browseNames: string[] = [];
  @State browseIndex: number = 0;
  @State comics: ComicBrief[] = [];
  @State loading: boolean = false;
  @State error: string = '';

  aboutToAppear(): void {
    const registry = SourceRegistry.get();
    this.sources = registry.enabled();
    this.pageSourceId = registry.currentSourceId();
    this.refreshTypes();
    this.loadBrowse(0);
  }

  /** 读取当前数据源提供的排行/分类类型 */
  private refreshTypes(): void {
    const rule = SourceRegistry.get().find(this.pageSourceId);
    const names: string[] = [];
    if (rule !== null) {
      for (let i = 0; i < rule.browse.length; i++) {
        names.push(rule.browse[i].name);
      }
    }
    this.browseNames = names;
    if (this.browseIndex >= names.length) {
      this.browseIndex = 0;
    }
  }

  private switchSource(id: string): void {
    if (id === this.pageSourceId) {
      return;
    }
    this.pageSourceId = id;
    this.browseIndex = 0;
    this.refreshTypes();
    this.loadBrowse(0);
  }

  private async loadBrowse(index: number): Promise<void> {
    const rule = SourceRegistry.get().find(this.pageSourceId);
    if (rule === null) {
      this.comics = [];
      this.error = '还没有可用图源，请到「我的 → 图源管理」启用';
      return;
    }
    if (rule.browse.length === 0) {
      this.comics = [];
      this.error = '当前图源未提供排行榜 / 分类\n可直接用「搜索」找漫画';
      return;
    }
    const safe = index < 0 || index >= rule.browse.length ? 0 : index;
    this.browseIndex = safe;
    this.loading = true;
    this.error = '';
    const entry = rule.browse[safe];
    const outcome = await SourceApi.browse(rule, entry, 1);
    this.loading = false;
    if (outcome.ok && outcome.value !== undefined) {
      this.comics = outcome.value;
    } else {
      this.comics = [];
      this.error = outcome.message;
    }
  }

  private refererOf(sourceId: string): string {
    const rule = SourceRegistry.get().find(sourceId);
    return rule === null ? '' : rule.baseUrl;
  }

  private openDetail(item: ComicBrief): void {
    const params = new DetailParams();
    params.sourceId = item.sourceId;
    params.comicId = item.comicId;
    params.url = item.url;
    params.title = item.title;
    router.pushUrl({ url: 'pages/DetailPage', params: params });
  }

  /**
   * 分类少于 4 个时，左侧竖栏只放一两条会留下大片空白、很难看，
   * 这种情况改成顶部横滑 chips；分类多的源（漫客栈 14 个）仍用左侧栏。
   */
  private useRail(): boolean {
    return this.browseNames.length >= 4;
  }

  /** 只有真正的榜单才显示名次；「首页推荐 / 最近更新」是流水列表，编号没意义 */
  private ranked(): boolean {
    if (this.browseIndex < 0 || this.browseIndex >= this.browseNames.length) {
      return false;
    }
    const name = this.browseNames[this.browseIndex];
    return name.indexOf('榜') >= 0 || name.indexOf('排行') >= 0;
  }

  // ─────────────────────────── 版式块 ───────────────────────────

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
      Text('排行榜')
        .fontSize(Theme.fsTitle)
        .fontWeight(FontWeight.Bold)
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

  /** 数据源横向切换栏 */
  @Builder
  sourceBar() {
    Scroll() {
      Row() {
        ForEach(this.sources, (rule: SourceRule) => {
          Text(rule.name)
            .fontSize(Theme.fsLabel)
            .fontWeight(rule.id === this.pageSourceId ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(rule.id === this.pageSourceId ? Theme.accent : Theme.textSub)
            .height(34)
            .padding({ left: 14, right: 14 })
            .backgroundColor(rule.id === this.pageSourceId ? Theme.accentDim : Color.Transparent)
            .borderRadius(Theme.radiusPill)
            .margin({ right: Theme.gapS })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.switchSource(rule.id);
            })
        }, (rule: SourceRule) => `rb_src_${rule.id}`)
      }
      .padding({ left: Theme.gapL, right: Theme.gapL })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ top: Theme.gapS, bottom: Theme.gapM })
  }

  /** 左侧类型栏 */
  @Builder
  typeColumn() {
    Scroll() {
      Column() {
        ForEach(this.browseNames, (name: string, index: number) => {
          Row() {
            if (index === this.browseIndex) {
              Column()
                .width(3)
                .height(16)
                .backgroundColor(Theme.accent)
                .borderRadius(2)
                .margin({ right: 6 })
            }
            Text(name)
              .fontSize(Theme.fsLabel)
              .fontWeight(index === this.browseIndex ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(index === this.browseIndex ? Theme.accent : Theme.textSub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .textAlign(index === this.browseIndex ? TextAlign.Start : TextAlign.Center)
          }
          .width('100%')
          .height(46)
          .padding({ left: index === this.browseIndex ? 10 : 6, right: 6 })
          .backgroundColor(index === this.browseIndex ? Theme.accentDim : Color.Transparent)
          .borderRadius(Theme.radiusS)
          .onClick(() => {
            this.loadBrowse(index);
          })
        }, (name: string, index: number) => `rb_type_${index}_${name}`)
      }
      .width('100%')
      .padding({ top: Theme.gapS, bottom: Theme.gapS })
    }
    .width(104)
    .height('100%')
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.radiusM)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /** 分类少时的顶部横滑 chips */
  @Builder
  typeChips() {
    Scroll() {
      Row() {
        ForEach(this.browseNames, (name: string, index: number) => {
          Text(name)
            .fontSize(Theme.fsLabel)
            .fontWeight(index === this.browseIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(index === this.browseIndex ? Theme.onAccent : Theme.textSub)
            .height(34)
            .padding({ left: 16, right: 16 })
            .backgroundColor(index === this.browseIndex ? Theme.accent : Theme.surface)
            .borderRadius(Theme.radiusPill)
            .margin({ right: Theme.gapS })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.loadBrowse(index);
            })
        }, (name: string, index: number) => `rb_chip_${index}_${name}`)
      }
      .padding({ left: Theme.gapL, right: Theme.gapL })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ bottom: Theme.gapM })
  }

  /** 单条排行卡片：序号 + 封面 + 标题/作者/最新章节 */
  @Builder
  rankCard(item: ComicBrief, index: number) {
    Row() {
      if (this.ranked()) {
        Text(`${index + 1}`)
          .fontSize(index < 3 ? Theme.fsLabel + 1 : Theme.fsLabel)
          .fontWeight(FontWeight.Bold)
          .fontColor(index < 3 ? Theme.onAccent : Theme.textDim)
          .width(26)
          .height(26)
          .textAlign(TextAlign.Center)
          .backgroundColor(index < 3 ? Theme.accent : Theme.surfaceHi)
          .borderRadius(Theme.radiusPill)
      }

      RemoteImage({
        url: item.cover,
        referer: this.refererOf(item.sourceId),
        ratio: 0.72,
        corner: Theme.radiusS + 2
      })
        .width(66)
        .margin({ left: this.ranked() ? Theme.gapM : 0 })

      Column() {
        Text(item.title)
          .fontSize(Theme.fsBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        // 站点没给作者/更新时宁可少一行，也不要满屏「作者未知」
        if (item.author.length > 0) {
          Text(item.author)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textSub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
            .width('100%')
        }
        if (item.latest.length > 0) {
          Text(item.latest)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Theme.gapM })
    }
    .width('100%')
    .padding(Theme.gapM)
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.radiusM)
    .margin({ bottom: Theme.gapM })
    .onClick(() => {
      this.openDetail(item);
    })
  }

  @Builder
  stateBlock(icon: Resource, title: string, hint: string, action: string, onAction: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(38)
        .fontColor([Theme.line])
      Text(title)
        .fontSize(Theme.fsBody)
        .fontColor(Theme.textSub)
        .textAlign(TextAlign.Center)
        .margin({ top: Theme.gapL })
        .padding({ left: 24, right: 24 })
      if (hint.length > 0) {
        Text(hint)
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .textAlign(TextAlign.Center)
          .lineHeight(19)
          .margin({ top: Theme.gapS })
          .padding({ left: 24, right: 24 })
      }
      if (action.length > 0) {
        Button(action)
          .fontSize(Theme.fsLabel)
          .fontWeight(FontWeight.Medium)
          .height(40)
          .padding({ left: 24, right: 24 })
          .margin({ top: Theme.gapXl })
          .backgroundColor(Theme.surfaceHi)
          .fontColor(Theme.accent)
          .borderRadius(Theme.radiusPill)
          .onClick(() => {
            onAction();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /** 右侧内容区（左侧栏模式与 chips 模式共用） */
  @Builder
  listArea() {
    if (this.loading) {
      Column() {
        LoadingProgress().width(34).height(34).color(Theme.accent)
        Text('正在加载…')
          .fontSize(Theme.fsCaption)
          .fontColor(Theme.textDim)
          .margin({ top: Theme.gapM })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.error.length > 0) {
      this.stateBlock($r('sys.symbol.exclamationmark_circle'), this.error, '', '重新加载', () => {
        this.loadBrowse(this.browseIndex);
      })
    } else if (this.comics.length === 0) {
      this.stateBlock($r('sys.symbol.list_bullet'), '这个榜单暂时没有内容', '换个榜单试试', '重新加载', () => {
        this.loadBrowse(this.browseIndex);
      })
    } else {
      List() {
        ForEach(this.comics, (item: ComicBrief, index: number) => {
          ListItem() {
            this.rankCard(item, index)
          }
        }, (item: ComicBrief, index: number) => `rb_${item.sourceId}_${item.comicId}_${index}`)
      }
      .layoutWeight(1)
      .padding({
        left: this.useRail() ? Theme.gapM : Theme.gapL,
        right: this.useRail() ? 0 : Theme.gapL,
        bottom: Theme.gapM
      })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  build() {
    Column() {
      this.navBar()
      this.sourceBar()

      if (this.loading && this.browseNames.length === 0) {
        Column() {
          LoadingProgress().width(34).height(34).color(Theme.accent)
          Text('正在加载排行榜…')
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .margin({ top: Theme.gapM })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.browseNames.length === 0) {
        this.stateBlock($r('sys.symbol.list_bullet'), this.error.length > 0 ? this.error : '当前图源没有排行榜',
          '换一个数据源试试', '重新加载', () => {
            this.loadBrowse(0);
          })
      } else if (this.useRail()) {
        Row() {
          this.typeColumn()
          this.listArea()
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
        .padding({ left: Theme.gapL, right: Theme.gapL, bottom: Theme.gapM })
      } else {
        Column() {
          this.typeChips()
          this.listArea()
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
