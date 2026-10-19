/**
 * AnalysisHeroCard · 工作台「本次评估」hero（本轮主页重构的核心卡片）
 *
 * 它把旧工作台「当前任务」卡片与旧分析详情页的「素材状态 / 分数 / 进度 / 动作」
 * 合并成一张卡，承担三件事：
 *   ① **一眼可读**：首帧照片 + 文件名 + 图片/视频 + 来源标签 + 状态胶囊；
 *   ② **结果摘要**：BDI 分数环 + 严重度 + 分数区间 + 帧数/耗时；
 *   ③ **就地操作**：当前任务显示「上传→逐帧推理→汇总评分」与分析进度；
 *      历史素材显示「重新分析该素材」；运行中显示「取消分析」；
 *      在查看历史且后台有当前任务时，显示「回到当前任务」chip。
 *
 * ────────────────── 数据流 ──────────────────
 * 本组件**不 import store**：所有展示值由工作台算成 `WorkbenchHeroModel`
 * 传入（扁平只读投影）。因此：
 *   · 异步逐帧更新不会因为"@Builder 按值传参"而停在旧值（BUG-19）；
 *   · hero 可以脱离整个 App 单独预览。
 *
 * ★ 所有 @Builder 一律无参，值全部读 `@Computed` 或 `this.model.*`。
 * ★ 卡片本身不可点（避免误触），只有明确的动作按钮 / chip 可点，且点击区 ≥44vp。
 * ★ 左侧 4vp 竖条用 border-left 画（高度天然等于内容高度，零测量风险）；
 *   有分数时用严重度色，未出分时用 divider —— 没有数据就不该有颜色暗示档位。
 */

import { UiTheme } from '../../common/UiTheme';
import {
  BDI_MAX_SCORE, MediaType, TaskStatus, WorkbenchHeroModel, emptyWorkbenchHeroModel
} from '../../types/Index';
import { RippleCard } from '../RippleCard';
import { ProgressBar } from '../common/ProgressBar';
import { ScoreRing } from '../common/ScoreRing';
import { MediaTypeBadge } from '../common/MediaTypeBadge';
import { StatusDot } from './StatusDot';
import { AnalysisStageRail } from './AnalysisStageRail';

/** 首帧照片边长（vp）· 比列表缩略图略小，hero 的重心是分数环 */
const HERO_THUMB_SIZE: number = 48;

/** 左侧严重度竖条宽度（与旧当前任务卡、AuthAlert 撞击条同宽） */
const RAIL_WIDTH: number = 4;

/** 状态胶囊：高 22 / 圆角取高度一半 / 左右内边距 8 */
const CAPSULE_HEIGHT: number = 22;
const CAPSULE_RADIUS: number = 11;

/** 空态圆底图标块直径 */
const EMPTY_ICON_SIZE: number = 64;

/** 首帧照片缺失时的占位字形 */
const IMAGE_GLYPH: string = '图';
const VIDEO_GLYPH: string = '视';

/** 空态字形 */
const EMPTY_GLYPH: string = '析';

/** 分数环边长 */
const RING_SIZE: number = 120;

@ComponentV2
export struct AnalysisHeroCard {
  /** 只读展示投影 · 由 `WorkbenchPage` 计算 */
  @Param model: WorkbenchHeroModel = emptyWorkbenchHeroModel();

  /** 点「重新分析该素材」· 页面把 mediaId/name/type 转交窗口层 */
  @Param onReanalyze: () => void = () => {};

  /** 点「取消分析」· 页面转交窗口层 */
  @Param onCancel: () => void = () => {};

  // ══════════════════ 派生值（★ 无参 builder 的取值来源）══════════════════

  /** 素材是否视频 */
  @Computed
  get isVideo(): boolean {
    return this.model.mediaType === MediaType.video;
  }

  /** 首帧缺失时的占位字形 */
  @Computed
  get mediaGlyph(): string {
    return this.isVideo ? VIDEO_GLYPH : IMAGE_GLYPH;
  }

  /** 是否运行中 */
  @Computed
  get isRunning(): boolean {
    return this.model.status === TaskStatus.running;
  }

  /** 是否有可操作的按钮（否则整行不渲染，避免空行占位） */
  @Computed
  get showActions(): boolean {
    return this.model.canReanalyze || this.model.canCancel;
  }

  /**
   * 状态胶囊底色 · 只表达"属于哪一类状态"，文字色另由 `model.statusColor` 负责
   * ★ 完成态复用统计页浅薄荷渐变起点（`kpiGradientStart`）；本轮不新增颜色令牌。
   */
  @Computed
  get capsuleBg(): string {
    if (this.model.status === TaskStatus.failed) {
      return UiTheme.dangerSoft;
    }
    if (this.model.status === TaskStatus.done) {
      return UiTheme.kpiGradientStart;
    }
    if (this.model.status === TaskStatus.running) {
      return UiTheme.cardPressTint;
    }
    return UiTheme.fillSoft;
  }

  /** 左侧竖条 · 有分数用严重度色；未出分用中性分隔色 */
  @Computed
  get railColor(): string {
    return this.model.score > 0 ? this.model.severityColor : UiTheme.divider;
  }

  /** 空态标题（加载中与真的没有记录要分开说） */
  @Computed
  get emptyTitle(): string {
    return this.model.loading ? '正在加载评估记录…' : '还没有评估记录';
  }

  /** 空态说明 */
  @Computed
  get emptyBody(): string {
    if (this.model.loading) {
      return '正在读取本机的分析数据';
    }
    return '从下方选择一张图片或一段视频，开始第一次辅助评估';
  }

  /** 右栏一句话说明：有错误优先显示错误，否则显示模型给的提示 */
  @Computed
  get bodyHint(): string {
    return this.model.errorMsg.length > 0 ? this.model.errorMsg : this.model.hintText;
  }

  /** 一句话说明的颜色 */
  @Computed
  get bodyHintColor(): string {
    return this.model.errorMsg.length > 0 ? UiTheme.danger : UiTheme.textSecondary;
  }

  /** 动作行左侧的小字提示（只说明边界，不承载主信息） */
  @Computed
  get actionHint(): string {
    if (this.model.canCancel) {
      return this.model.isImage
        ? '图片推理很快，通常几秒内完成'
        : '视频分析在服务端处理得很快，取消可能不会生效';
    }
    if (this.model.canReanalyze) {
      return '重新分析会覆盖这条素材自己的结果';
    }
    return '';
  }

  // ══════════════════ 片段（★ 无参 builder）══════════════════

  /** 首帧照片 · 空串时画「图/视」占位块（不拿 .mp4 直链喂 Image） */
  @Builder
  thumbnail() {
    if (this.model.firstFrameUrl.length > 0) {
      Image(this.model.firstFrameUrl)
        .width(HERO_THUMB_SIZE)
        .height(HERO_THUMB_SIZE)
        .objectFit(ImageFit.Cover)
        .borderRadius(UiTheme.gapM)
        .backgroundColor(UiTheme.fillSoft)
        .border({ width: 1, color: UiTheme.divider })
    } else {
      Column() {
        Text(this.mediaGlyph)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
      }
      .width(HERO_THUMB_SIZE)
      .height(HERO_THUMB_SIZE)
      .borderRadius(UiTheme.gapM)
      .backgroundColor(UiTheme.fillSoft)
      .border({ width: 1, color: UiTheme.divider })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /** 状态胶囊（右上角）· 颜色 + 文字双通道，不只靠颜色表达状态 */
  @Builder
  statusCapsule() {
    Row({ space: UiTheme.gapXs }) {
      StatusDot({ dotColor: this.model.statusColor, dotSize: 6 })

      Text(this.model.statusLabel)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(this.model.statusColor)
        .maxLines(1)
    }
    .height(CAPSULE_HEIGHT)
    .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
    .borderRadius(CAPSULE_RADIUS)
    .backgroundColor(this.capsuleBg)
    .alignItems(VerticalAlign.Center)
  }

  /** 素材身份行：照片 ｜ 文件名 + 类型/来源/时间 ｜ 状态胶囊 */
  @Builder
  headerRow() {
    Row({ space: UiTheme.gapM }) {
      this.thumbnail()

      Column({ space: UiTheme.gapXs }) {
        Text(this.model.mediaName)
          .fontSize(UiTheme.fontSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)

        Row({ space: UiTheme.gapXs }) {
          MediaTypeBadge({ mediaType: this.model.mediaType })

          Text(this.model.sourceLabel)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .maxLines(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.model.timeText.length > 0) {
          Text(this.model.timeText)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.statusCapsule()
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 分数环 + 右侧结果摘要 */
  @Builder
  scoreRow() {
    Row({ space: UiTheme.gapL }) {
      ScoreRing({
        score: this.model.score,
        maxScore: BDI_MAX_SCORE,
        color: this.model.severityColor,
        ringSize: RING_SIZE,
        strokeWidth: 10
      })

      Column({ space: UiTheme.gapXs }) {
        Text(
          this.model.severityLabel.length > 0 ? this.model.severityLabel : '等待评分'
        )
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(
            this.model.severityLabel.length > 0 ? this.model.severityColor : UiTheme.textSecondary
          )
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)

        Text(`BDI ${this.model.scoreText} / ${BDI_MAX_SCORE}`)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)

        if (this.model.frameCountText.length > 0) {
          Text(this.model.frameCountText)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Text(this.bodyHint)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(this.bodyHintColor)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.model.inferenceText.length > 0) {
          Text(this.model.inferenceText)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 阶段轨 · 只有当前任务显示（历史归档不画"正在走流程"） */
  @Builder
  stageBlock() {
    AnalysisStageRail({
      stageIndex: this.model.stageIndex,
      failed: this.model.stageFailed,
      middleLabel: this.model.isImage ? '单次推理' : '逐帧推理'
    })
  }

  /** 分析进度条 · 仅在运行中显示；条只表达"跑了多少"，不与 BDI 混用 */
  @Builder
  progressBlock() {
    Column({ space: UiTheme.gapXs }) {
      ProgressBar({
        ratio: this.model.progress,
        barColor: UiTheme.primary,
        barHeight: 6,
        trackColor: UiTheme.fillSoft
      })

      Row() {
        Text('分析进度')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        Text(this.model.progressText)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.primary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 动作行：左侧边界说明 + 右侧文字按钮（44vp 点击区） */
  @Builder
  actionsRow() {
    Row({ space: UiTheme.gapS }) {
      Text(this.actionHint)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)

      if (this.model.canReanalyze) {
        Text('重新分析该素材')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.accent)
          .height(44)
          .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
          .onClick(() => {
            this.onReanalyze();
          })
      }

      if (this.model.canCancel) {
        Text('取消分析')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .height(44)
          .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
          .onClick(() => {
            this.onCancel();
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 有分析目标时的完整内容 */
  @Builder
  focusContent() {
    Column({ space: UiTheme.gapM }) {
      this.headerRow()

      this.scoreRow()

      if (this.model.showStageRail) {
        this.stageBlock()
      }

      if (this.isRunning) {
        this.progressBlock()
      }

      if (this.showActions) {
        this.actionsRow()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 档位色竖条：用 border-left 表达（高度天然等于内容高度，见文件头说明）
    .padding({ left: RAIL_WIDTH + UiTheme.gapM })
    .borderRadius(RAIL_WIDTH / 2)
    .border({ width: { left: RAIL_WIDTH }, color: { left: this.railColor } })
  }

  /** 无分析目标时的空态 · 不重复放 CTA（下方「开始新的辅助评估」卡就是入口） */
  @Builder
  emptyContent() {
    Column({ space: UiTheme.gapM }) {
      Column() {
        Text(EMPTY_GLYPH)
          .fontSize(24)
          .fontColor(UiTheme.textSecondary)
      }
      .width(EMPTY_ICON_SIZE)
      .height(EMPTY_ICON_SIZE)
      .borderRadius(EMPTY_ICON_SIZE / 2)
      .backgroundColor(UiTheme.skeletonFill)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(this.emptyTitle)
        .fontSize(UiTheme.fontSizeSection)
        .fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(this.emptyBody)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    RippleCard({ _enabled: false, _clickable: false }) {
      if (this.model.hasFocus) {
        this.focusContent()
      } else {
        this.emptyContent()
      }
    }
  }
}
