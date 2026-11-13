import { router, promptAction } from '@kit.ArkUI';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceApi } from '../source/SourceApi';
import { SourceRule } from '../rule/Rules';
import { ComicBrief, ComicDetail, ChapterBrief, SwitchCandidate } from '../model/Models';
import { SwitchParams } from '../model/RouteParams';
import { SwitchBus, SwitchPending } from '../store/SwitchBus';
import { chapterNumber } from '../util/Text';
import { RemoteImage } from '../view/RemoteImage';
import { Theme } from '../theme/Theme';

/** 标题相似度：去符号后取「包含关系 + 字符重合率」的较大值 */
function similarity(left: string, right: string): number {
  const normalize = (value: string): string =>
  value.replace(new RegExp('[\\s\\-_·:：!！?？()（）\\[\\]【】<>《》]', 'g'), '').toLowerCase();
  const a = normalize(left);
  const b = normalize(right);
  if (a.length === 0 || b.length === 0) {
    return 0;
  }
  if (a === b) {
    return 1;
  }
  if (a.indexOf(b) >= 0 || b.indexOf(a) >= 0) {
    const shorter = Math.min(a.length, b.length);
    const longer = Math.max(a.length, b.length);
    return 0.75 + 0.25 * (shorter / longer);
  }
  const pool: string[] = [];
  for (let i = 0; i < b.length; i++) {
    pool.push(b.charAt(i));
  }
  let hit = 0;
  for (let i = 0; i < a.length; i++) {
    const ch = a.charAt(i);
    const index = pool.indexOf(ch);
    if (index >= 0) {
      hit++;
      pool.splice(index, 1);
    }
  }
  return hit / Math.max(a.length, b.length);
}

/** 单源搜索命中的 top-N 结果（并行阶段用） */
class SearchHit {
  rule: SourceRule = new SourceRule();
  hits: ComicBrief[] = [];
  scores: number[] = [];
}

@Entry
@Component
struct SourceSwitchPage {
  @State candidates: SwitchCandidate[] = [];
  @State loading: boolean = true;
  @State message: string = '正在检索其他图源…';
  @State progressText: string = '';
  private params: SwitchParams = new SwitchParams();
  /** 失效会话不会覆盖切走之后的页面状态。 */
  private collectToken: number = 0;

  aboutToAppear(): void {
    const raw = router.getParams() as SwitchParams;
    if (raw !== undefined && raw !== null) {
      this.params = raw;
    }
    this.collect();
  }

  onPageHide(): void {
    this.collectToken++;
  }

  private async searchOne(rule: SourceRule): Promise<SearchHit | null> {
    const outcome = await SourceApi.search(rule, this.params.title, 1);
    if (!outcome.ok || outcome.value === undefined) {
      return null;
    }
    const ranked: ComicBrief[] = [];
    const scores: number[] = [];
    for (let k = 0; k < outcome.value.length; k++) {
      const hit = outcome.value[k];
      const score = similarity(this.params.title, hit.title);
      if (score < 0.6) {
        continue;
      }
      let pos = ranked.length;
      for (let a = 0; a < ranked.length; a++) {
        if (scores[a] < score) {
          pos = a;
          break;
        }
      }
      ranked.splice(pos, 0, hit);
      scores.splice(pos, 0, score);
    }
    const result = new SearchHit();
    result.rule = rule;
    result.hits = ranked.slice(0, 2);
    result.scores = scores.slice(0, 2);
    return result;
  }

  private async detailOne(rule: SourceRule, brief: ComicBrief, score: number): Promise<SwitchCandidate> {
    const candidate = new SwitchCandidate();
    candidate.sourceId = rule.id;
    candidate.sourceName = rule.name;
    candidate.comicId = brief.comicId;
    candidate.title = brief.title;
    candidate.cover = brief.cover;
    candidate.url = brief.url;
    candidate.similarity = score;
    const detailOutcome = await SourceApi.detail(rule, brief.comicId, brief.url);
    if (!detailOutcome.ok || detailOutcome.value === undefined) {
      candidate.error = detailOutcome.message;
      return candidate;
    }
    const detail: ComicDetail = detailOutcome.value;
    candidate.comicId = detail.comicId;
    candidate.title = detail.title;
    candidate.cover = detail.cover.length > 0 ? detail.cover : brief.cover;
    candidate.author = detail.author;
    candidate.url = detail.url;
    candidate.chapterCount = detail.chapters.length;
    candidate.similarity = similarity(this.params.title, detail.title);
    const latest = detail.chapters[detail.chapters.length - 1];
    candidate.latestTitle = latest === undefined ? '' : latest.title;
    candidate.alignedChapterIndex = this.alignChapter(detail.chapters, chapterNumber(this.params.chapterTitle));
    const aligned = detail.chapters[candidate.alignedChapterIndex];
    candidate.alignedChapterTitle = aligned === undefined ? '' : aligned.title;
    return candidate;
  }

  private async collect(): Promise<void> {
    const token = ++this.collectToken;
    this.loading = true;
    this.candidates = [];
    const registry = SourceRegistry.get();
    const all = registry.enabled();
    const found: SwitchCandidate[] = [];

    // 阶段一：最多 3 个并发请求，避免开启大量图源时打满网络连接。
    const targetRules: SourceRule[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].id !== this.params.sourceId) {
        targetRules.push(all[i]);
      }
    }
    this.progressText = `正在检索 ${targetRules.length} 个源…`;
    const searchOutcomes: (SearchHit | null)[] = [];
    for (let i = 0; i < targetRules.length; i++) {
      searchOutcomes.push(null);
    }
    let searchNext = 0;
    const searchWorker = async (): Promise<void> => {
      while (token === this.collectToken && searchNext < targetRules.length) {
        const index = searchNext++;
        try {
          searchOutcomes[index] = await this.searchOne(targetRules[index]);
        } catch (error) {
          // 单个图源抛出异常时继续检查剩余图源。
          searchOutcomes[index] = null;
        }
      }
    };
    const searchWorkers: Promise<void>[] = [];
    for (let i = 0; i < Math.min(3, targetRules.length); i++) {
      searchWorkers.push(searchWorker());
    }
    await Promise.all(searchWorkers);
    if (token !== this.collectToken) return;

    // 阶段二：最多 3 个并发详情请求，防止同名候选过多时资源耗尽。
    const detailRules: SourceRule[] = [];
    const detailBriefs: ComicBrief[] = [];
    const detailScores: number[] = [];
    for (let i = 0; i < searchOutcomes.length; i++) {
      const hit = searchOutcomes[i];
      if (hit === null) continue;
      for (let k = 0; k < hit.hits.length; k++) {
        detailRules.push(hit.rule);
        detailBriefs.push(hit.hits[k]);
        detailScores.push(hit.scores[k]);
      }
    }
    this.progressText = `正在比对 ${detailRules.length} 个候选…`;
    let detailNext = 0;
    const detailWorker = async (): Promise<void> => {
      while (token === this.collectToken && detailNext < detailRules.length) {
        const index = detailNext++;
        try {
          const candidate = await this.detailOne(detailRules[index], detailBriefs[index], detailScores[index]);
          if (token !== this.collectToken) return;
          found.push(candidate);
        } catch (error) {
          // 单本详情失败不应终止整批换源搜索。
        }
      }
    };
    const detailWorkers: Promise<void>[] = [];
    for (let i = 0; i < Math.min(3, detailRules.length); i++) {
      detailWorkers.push(detailWorker());
    }
    await Promise.all(detailWorkers);
    if (token !== this.collectToken) return;

    // 按相似度降序
    for (let a = 1; a < found.length; a++) {
      let b = a;
      while (b > 0 && found[b].similarity > found[b - 1].similarity) {
        const tmp = found[b];
        found[b] = found[b - 1];
        found[b - 1] = tmp;
        b--;
      }
    }

    this.candidates = found;
    this.loading = false;
    if (found.length === 0) {
      this.message = '其他图源没有找到同名漫画';
    } else {
      this.message = `共 ${found.length} 个候选`;
    }
  }

  /** 章节对齐：优先按章节号匹配，否则按原索引夹取 */
  private alignChapter(chapters: ChapterBrief[], targetNumber: number): number {
    if (chapters.length === 0) {
      return 0;
    }
    if (targetNumber > 0) {
      for (let i = 0; i < chapters.length; i++) {
        if (Math.abs(chapterNumber(chapters[i].title) - targetNumber) < 0.01) {
          return i;
        }
      }
    }
    const index = this.params.chapterIndex;
    if (index < 0) {
      return 0;
    }
    return index >= chapters.length ? chapters.length - 1 : index;
  }

  private async hop(candidate: SwitchCandidate): Promise<void> {
    if (candidate.error.length > 0) {
      promptAction.showToast({ message: `该源详情读取失败：${candidate.error}` });
      return;
    }
    // 记下当前源（持久化到下次切换），并让详情页/阅读器接管新源，退回作品界面
    await SourceRegistry.get().setCurrent(candidate.sourceId);
    const pending = new SwitchPending();
    pending.sourceId = candidate.sourceId;
    pending.comicId = candidate.comicId;
    pending.url = candidate.url;
    pending.title = candidate.title;
    pending.chapterIndex = candidate.alignedChapterIndex;
    SwitchBus.put(pending);
    router.back();
  }

  private refererOf(sourceId: string): string {
    const rule = SourceRegistry.get().find(sourceId);
    return rule === null ? '' : rule.baseUrl;
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
      Text('切换图源')
        .fontSize(Theme.fsBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Blank()
      // 与左侧等宽的占位，保证标题居中
      Text('返回')
        .fontSize(Theme.fsBody)
        .fontColor(Color.Transparent)
    }
    .width('100%')
    .height(56)
    .padding({ left: Theme.gapM, right: Theme.gapM })
  }

  @Builder
  candidateCard(item: SwitchCandidate) {
    Row() {
      RemoteImage({
        url: item.cover,
        referer: this.refererOf(item.sourceId),
        ratio: 0.73,
        corner: Theme.radiusS + 2
      })
        .width(62)

      Column() {
        Row() {
          Text(item.sourceName)
            .fontSize(Theme.fsMicro)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.accent)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(Theme.accentDim)
            .borderRadius(Theme.radiusS)
          Text(`${Math.round(item.similarity * 100)}% 匹配`)
            .fontSize(Theme.fsMicro)
            .fontColor(item.similarity >= 0.9 ? Theme.ok : Theme.textDim)
            .margin({ left: Theme.gapS })
        }

        Text(item.title)
          .fontSize(Theme.fsBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 7 })
          .width('100%')

        if (item.error.length > 0) {
          Text(item.error)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.warn)
            .maxLines(2)
            .margin({ top: 5 })
            .width('100%')
        } else {
          Text(`${item.chapterCount} 话 · 最新 ${item.latestTitle}`)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .margin({ top: 5 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(`从「${item.alignedChapterTitle}」继续`)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.accent)
            .margin({ top: 5 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Theme.gapM })

      Text('›')
        .fontSize(22)
        .fontColor(Theme.textDim)
        .margin({ left: Theme.gapS })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(Theme.gapM)
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.radiusL)
    .margin({ bottom: Theme.gapM })
    .onClick(() => {
      this.hop(item);
    })
  }

  build() {
    Column() {
      this.navBar()
      if (this.loading) {
        Column() {
          LoadingProgress().width(34).height(34).color(Theme.accent)
          Text(this.message)
            .fontSize(Theme.fsBody)
            .fontColor(Theme.textSub)
            .margin({ top: Theme.gapL })
          Text(this.progressText)
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .margin({ top: Theme.gapS })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.candidates.length === 0) {
        Column() {
          Text(this.params.title)
            .fontSize(Theme.fsHeadline)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text('会按章节号自动对齐到你正在看的那一话')
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .margin({ top: 6 })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapXs })

        Column() {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
            .fontSize(42)
            .fontColor([Theme.line])
          Text(this.message)
            .fontSize(Theme.fsBody)
            .fontColor(Theme.textSub)
            .margin({ top: Theme.gapL })
          Text('可以到「图源管理」启用更多源，或先用原名搜索')
            .fontSize(Theme.fsCaption)
            .fontColor(Theme.textDim)
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            .margin({ top: Theme.gapS })
            .padding({ left: 32, right: 32 })
          Button('去图源管理')
            .fontSize(Theme.fsLabel)
            .fontWeight(FontWeight.Medium)
            .height(40)
            .padding({ left: 24, right: 24 })
            .margin({ top: Theme.gapXl })
            .backgroundColor(Theme.surfaceHi)
            .fontColor(Theme.accent)
            .borderRadius(Theme.radiusPill)
            .onClick(() => {
              router.pushUrl({ url: 'pages/SourceManagerPage' });
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ListItem() {
            Column() {
              Text(this.params.title)
                .fontSize(Theme.fsHeadline)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text('会按章节号自动对齐到你正在看的那一话')
                .fontSize(Theme.fsCaption)
                .fontColor(Theme.textDim)
                .margin({ top: 6 })
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ left: Theme.gapL, right: Theme.gapL, top: Theme.gapXs, bottom: Theme.gapL })
          }

          ListItem() {
            Text(this.message)
              .fontSize(Theme.fsCaption)
              .fontColor(Theme.textDim)
              .width('100%')
              .padding({ left: Theme.gapL, right: Theme.gapL, bottom: Theme.gapM })
          }

          ForEach(this.candidates, (item: SwitchCandidate) => {
            ListItem() {
              this.candidateCard(item)
            }
            .padding({ left: Theme.gapL, right: Theme.gapL })
          }, (item: SwitchCandidate) => `${item.sourceId}_${item.comicId}`)
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
