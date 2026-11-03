/**
 * 全局设计令牌。
 *
 * 之前每个页面各自复制一份 BG / SURFACE / TEXT_MAIN 常量，字号也各写各的，
 * 结果就是同一层级的信息在不同页面上大小不一。这里统一收口：
 * 颜色只从这里取，字号只用这七级，避免「11 和 12 混用」这类问题。
 */

export class Theme {
  // ── 底色：由深到浅四层，用来表达层级 ──
  static bg: string = '#0D1117';
  static nav: string = '#0F141B';
  static surface: string = '#171D26';
  static surfaceHi: string = '#1F2733';
  /** 浮层与卡片的轻背景，用于把可点击内容从页面底色中托起 */
  static surfaceRaised: string = '#202936';
  static line: string = '#242C38';

  // ── 文字：三级 ──
  static text: string = '#F4F7FB';
  static textSub: string = '#B4BFCE';
  static textDim: string = '#8290A2';

  // ── 强调色 ──
  static accent: string = '#67A0FF';
  static accentDim: string = '#203454';
  static onAccent: string = '#0A1220';
  static warn: string = '#E3A552';
  static ok: string = '#57C68A';

  // ── 字号：七级封顶 ──
  /** 页面主标题 */
  static fsDisplay: number = 26;
  /** 详情页作品名 */
  static fsTitle: number = 20;
  /** 分区标题、按钮 */
  static fsHeadline: number = 17;
  /** 正文、列表主文字 */
  static fsBody: number = 15;
  /** 次级标签、章节名 */
  static fsLabel: number = 13;
  /** 辅助说明 */
  static fsCaption: number = 12;
  /** 角标、极次要信息 */
  static fsMicro: number = 11;

  // ── 间距：8 的倍数为主 ──
  static gapXs: number = 4;
  static gapS: number = 8;
  static gapM: number = 12;
  static gapL: number = 16;
  static gapXl: number = 22;

  // ── 圆角 ──
  static radiusS: number = 8;
  static radiusM: number = 12;
  static radiusL: number = 18;
  /** 胶囊 */
  static radiusPill: number = 999;
}
