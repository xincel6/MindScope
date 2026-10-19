/**
 * ScoreRing · 工作台 hero 的 **BDI 分数环**
 *
 * ────────────────── 它回答什么问题 ──────────────────
 * 工作台要在一屏内说清"这次评估有多严重"，一个 120vp 的环 + 中心大分数
 * 比一行数字更有视觉重量，也不占太多纵向空间。
 *
 * ────────────────── 为什么用 Canvas 而不是现成组件 ──────────────────
 *   · `Progress(ProgressType.Ring)` 只能画整圆，环的轨道颜色不可控；
 *   · `Gauge` 的 `colors` 表达的是"刻度分段"，不是"按比例填充"；
 *   · 这里只需要一条 270° 的轨道 + 一条按 `score / 63` 填充的弧，
 *     用 Canvas 画两段 `arc` 即可，结果确定、参数可控。
 *
 * ★ 硬约束：**只画渲染，不参与测量**。
 *   画布尺寸由 `ringSize` 固定，组件内不做 `onAreaChange`、不根据内容回写尺寸
 *   （那会形成"测量 → 状态 → 尺寸 → 布局 → 测量"的反馈环，见 `RippleCard` 的踩坑记录）。
 * ★ 首次绘制必须等 `onReady`：节点未挂载时 `arc/stroke` 没有画布可画。
 * ★ 数据变化（分数 / 颜色）通过 `@Monitor` 重绘；重绘前先 `clearRect`，避免叠加。
 */

import { UiTheme } from '../../common/UiTheme';
import { BDI_MAX_SCORE } from '../../types/Index';

/** 起始角：135°（左下），顺时针扫 270° 到 45°（右下），底部留 90° 缺口 */
const START_ANGLE: number = Math.PI * 0.75;

/** 扫描角 270° */
const SWEEP_ANGLE: number = Math.PI * 1.5;

/** 值弧与轨道离画布边的余量（vp）· 留一点避免圆头被裁 */
const EDGE_INSET: number = 2;

@ComponentV2
export struct ScoreRing {
  /** 当前分数（0 = 未出分） */
  @Param score: number = 0;

  /** 量表满分（BDI-II 为 63） */
  @Param maxScore: number = BDI_MAX_SCORE;

  /** 值弧颜色 · 由调用方按严重度档位传入 */
  @Param color: string = UiTheme.primary;

  /** 画布边长（vp）· 默认 120，hero 里正好和右侧说明并排 */
  @Param ringSize: number = 120;

  /** 弧线粗细（vp） */
  @Param strokeWidth: number = 10;

  /** 画布是否已完成首次布局（onReady 之后才能画） */
  private ready: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  /** 填充比例 0–1（夹紧；maxScore <= 0 时按 0 处理） */
  @Computed
  get ratio(): number {
    if (!Number.isFinite(this.score) || !Number.isFinite(this.maxScore) || this.maxScore <= 0) {
      return 0;
    }
    if (this.score <= 0) {
      return 0;
    }
    const value: number = this.score / this.maxScore;
    return value >= 1 ? 1 : value;
  }

  /** 分数文案 · 未出分给 `--`，不显示 0.0（会被误读成"分数是零"） */
  @Computed
  get scoreText(): string {
    return this.score > 0 ? this.score.toFixed(1) : '--';
  }

  /** 中心文字颜色 · 未出分用中性色，避免用绿色暗示"结果正常" */
  @Computed
  get scoreColor(): string {
    return this.score > 0 ? this.color : UiTheme.textSecondary;
  }

  /** 分数 / 颜色 / 尺寸变化时重绘（尺寸一般固定，一并监听无副作用） */
  @Monitor('score', 'color', 'ringSize', 'strokeWidth')
  private onVisualChanged(): void {
    if (!this.ready) {
      return;
    }
    this.draw();
  }

  /**
   * 画两段弧：先画整条轨道，再画按比例的值弧
   * ★ 值弧的终点 = `START_ANGLE + SWEEP_ANGLE * ratio`，ratio 已经夹在 0–1。
   */
  private draw(): void {
    const size: number = this.ringSize;
    if (size <= 0) {
      return;
    }
    const center: number = size / 2;
    const radius: number = center - this.strokeWidth / 2 - EDGE_INSET;
    if (radius <= 0) {
      return;
    }

    this.ctx.clearRect(0, 0, size, size);
    this.ctx.lineWidth = this.strokeWidth;
    this.ctx.lineCap = 'round';

    // ① 轨道（无论有没有分数都画，保持环的"量表"形状）
    this.ctx.beginPath();
    this.ctx.arc(center, center, radius, START_ANGLE, START_ANGLE + SWEEP_ANGLE);
    this.ctx.strokeStyle = UiTheme.fillSoft;
    this.ctx.stroke();

    // ② 值弧（0 分不画，避免圆头在起点留下一个点）
    const ratio: number = this.ratio;
    if (ratio <= 0) {
      return;
    }
    this.ctx.beginPath();
    this.ctx.arc(center, center, radius, START_ANGLE, START_ANGLE + SWEEP_ANGLE * ratio);
    this.ctx.strokeStyle = this.color;
    this.ctx.stroke();
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width(this.ringSize)
        .height(this.ringSize)
        .onReady(() => {
          this.ready = true;
          this.draw();
        })

      // 中心分数：环已经表达"离满分多远"，这里只强调具体数值
      Column({ space: UiTheme.gapXs }) {
        Text(this.scoreText)
          .fontSize(UiTheme.fontSizeMetric)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.scoreColor)
          .maxLines(1)

        Text('BDI')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .maxLines(1)
      }
      .width(this.ringSize)
      .height(this.ringSize)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.ringSize)
    .height(this.ringSize)
  }
}
