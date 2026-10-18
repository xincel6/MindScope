/**
 * AnalysisStageRail · 「上传 → 逐帧推理 → 汇总评分」三阶段指示器
 *
 * 从原 `CurrentTaskCard` 抽出：工作台 hero 仍需要一眼看出"这次分析推进到哪一步"，
 * 但 hero 自己已经很长，把这段纯视觉逻辑收进独立组件，页面只传阶段下标/失败标志。
 *
 * 视觉规则（与原卡片逐值一致）：
 *   · 未到达：空心圆（`fillSoft` 描边 + 白填充），文字次要色；
 *   · 已走过：实心主色圆，透明度 0.6（"走过但不再是焦点"）；
 *   · 当前：实心主色圆 + 正文色文字；当前段失败时圆点与文字改染 `danger`；
 *   · 段与段之间是 1vp 的 `divider` 细线，用 `layoutWeight(1)` 吸收剩余宽度。
 *
 * ★ 入参只有 `stageIndex` / `failed`，阶段判定（progress/status → 下标）在
 *   `WorkbenchPage` 的 hero 投影里完成；本组件不读 store、不判断业务。
 * ★ 所有 builder 无参，色值/文字全部来自 `@Computed`（BUG-19：@Builder 参数按值传递）。
 */

import { UiTheme } from '../../common/UiTheme';

/** 阶段圆点直径 / 连接线高度 */
const STAGE_DOT_SIZE: number = 8;
const STAGE_LINK_HEIGHT: number = 1;

/** 阶段下标（语义化，避免 builder 里出现魔法数字 0/1/2） */
const STAGE_UPLOAD: number = 0;
const STAGE_INFERENCE: number = 1;
const STAGE_SUMMARY: number = 2;

/** 某个阶段的视觉状态：还没到 / 已走过 / 正卡在这一段 */
const VIS_PENDING: number = 0;
const VIS_PASSED: number = 1;
const VIS_CURRENT: number = 2;

@ComponentV2
export struct AnalysisStageRail {
  /** 当前阶段下标：0 上传 / 1 推理 / 2 汇总评分 */
  @Param stageIndex: number = STAGE_UPLOAD;

  /** 当前阶段是否已经失败（决定当前段是否改染 danger） */
  @Param failed: boolean = false;

  /**
   * 中间阶段的文案
   * ★ 图片只做一次推理，写「逐帧推理」会与"1 帧（单次推理）"自相矛盾；
   *   工作台按素材类型传「单次推理 / 逐帧推理」，本组件不判断业务。
   */
  @Param middleLabel: string = '逐帧推理';

  /**
   * 某一段处在哪一态
   * ★ 抽成方法而不是三段各写一遍 if：三段必须共用**同一套**规则，
   *   分开写迟早出现"第一段已过、第三段还算当前"这种自相矛盾的显示。
   */
  private stageVisualAt(index: number): number {
    if (index === this.stageIndex) {
      return VIS_CURRENT;
    }
    return index < this.stageIndex ? VIS_PASSED : VIS_PENDING;
  }

  /** 圆点描边色：未达 = fillSoft（"空心"的那一圈）；其余 = 主色，当前段失败时染 danger */
  private stageRingAt(index: number): string {
    const visual: number = this.stageVisualAt(index);
    if (visual === VIS_PENDING) {
      return UiTheme.fillSoft;
    }
    if (visual === VIS_CURRENT && this.failed) {
      return UiTheme.danger;
    }
    return UiTheme.primary;
  }

  /** 圆点填充色：未达 = 卡片白（配 fillSoft 描边即"空心"）；其余与描边同色 → 实心 */
  private stageFillAt(index: number): string {
    const visual: number = this.stageVisualAt(index);
    return visual === VIS_PENDING ? UiTheme.cardBackground : this.stageRingAt(index);
  }

  /** 圆点透明度：已过 60%（"走过但不再是焦点"），当前/未达都保持 1 */
  private stageOpacityAt(index: number): number {
    return this.stageVisualAt(index) === VIS_PASSED ? 0.6 : 1;
  }

  /** 阶段文字色：当前段 = 正文色（失败染 danger），其余 = 次要文字色 */
  private stageTextAt(index: number): string {
    const visual: number = this.stageVisualAt(index);
    if (visual === VIS_CURRENT) {
      return this.failed ? UiTheme.danger : UiTheme.textPrimary;
    }
    return UiTheme.textSecondary;
  }

  // ── 阶段 0「上传」──

  @Computed
  get stage0Ring(): string {
    return this.stageRingAt(STAGE_UPLOAD);
  }

  @Computed
  get stage0Fill(): string {
    return this.stageFillAt(STAGE_UPLOAD);
  }

  @Computed
  get stage0Opacity(): number {
    return this.stageOpacityAt(STAGE_UPLOAD);
  }

  @Computed
  get stage0Text(): string {
    return this.stageTextAt(STAGE_UPLOAD);
  }

  // ── 阶段 1「逐帧推理」──

  @Computed
  get stage1Ring(): string {
    return this.stageRingAt(STAGE_INFERENCE);
  }

  @Computed
  get stage1Fill(): string {
    return this.stageFillAt(STAGE_INFERENCE);
  }

  @Computed
  get stage1Opacity(): number {
    return this.stageOpacityAt(STAGE_INFERENCE);
  }

  @Computed
  get stage1Text(): string {
    return this.stageTextAt(STAGE_INFERENCE);
  }

  // ── 阶段 2「汇总评分」──

  @Computed
  get stage2Ring(): string {
    return this.stageRingAt(STAGE_SUMMARY);
  }

  @Computed
  get stage2Fill(): string {
    return this.stageFillAt(STAGE_SUMMARY);
  }

  @Computed
  get stage2Opacity(): number {
    return this.stageOpacityAt(STAGE_SUMMARY);
  }

  @Computed
  get stage2Text(): string {
    return this.stageTextAt(STAGE_SUMMARY);
  }

  // ══════════════════ 片段（★ 无参 builder）══════════════════

  /** 阶段 0 · 上传（圆点 + 段名，尺寸三段一致，只有颜色/透明度不同） */
  @Builder
  stageUpload() {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(STAGE_DOT_SIZE)
        .height(STAGE_DOT_SIZE)
        .borderRadius(STAGE_DOT_SIZE / 2)
        .backgroundColor(this.stage0Fill)
        .border({ width: 1, color: this.stage0Ring })
        .opacity(this.stage0Opacity)

      Text('上传')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(this.stage0Text)
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 阶段 1 · 逐帧推理 */
  @Builder
  stageInference() {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(STAGE_DOT_SIZE)
        .height(STAGE_DOT_SIZE)
        .borderRadius(STAGE_DOT_SIZE / 2)
        .backgroundColor(this.stage1Fill)
        .border({ width: 1, color: this.stage1Ring })
        .opacity(this.stage1Opacity)

      Text(this.middleLabel)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(this.stage1Text)
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 阶段 2 · 汇总评分 */
  @Builder
  stageSummary() {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(STAGE_DOT_SIZE)
        .height(STAGE_DOT_SIZE)
        .borderRadius(STAGE_DOT_SIZE / 2)
        .backgroundColor(this.stage2Fill)
        .border({ width: 1, color: this.stage2Ring })
        .opacity(this.stage2Opacity)

      Text('汇总评分')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(this.stage2Text)
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 阶段之间的连接细线（1vp · divider）
   * ★ 用 `layoutWeight(1)` 而不是写死宽度：卡片宽度随屏幕变，
   *   写死的连线会在窄屏上把「逐帧推理」挤成两行；权重分配由布局引擎算。
   */
  @Builder
  stageLink() {
    Row()
      .layoutWeight(1)
      .height(STAGE_LINK_HEIGHT)
      .backgroundColor(UiTheme.divider)
      .margin({ left: UiTheme.gapS, right: UiTheme.gapS })
  }

  build() {
    Row() {
      this.stageUpload()
      this.stageLink()
      this.stageInference()
      this.stageLink()
      this.stageSummary()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
