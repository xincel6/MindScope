/**
 * SeverityDistributionCard · 分析详情页「严重度分布」卡片（原占位块 ②）
 *
 * ══════════════════ 这个组件回答的是用户的原问题 ══════════════════
 * 用户原话：「我不知道怎么在一段视频或者照片中使用饼图，如果你没有思路，
 * 这个组件可以直接删除」。
 *
 * 思路（本轮采用）：
 *   · **视频**：饼图**是有意义的** —— 统计**这一段视频的所有帧**分别落在四个档位的
 *     数量占比（例：60 帧中 正常 5 / 轻度 30 / 中度 20 / 重度 5，环心写「60 帧」）。
 *     它回答"这段素材里情绪稳定的比例"，正是"一段视频里怎么用饼图"的正确答案。
 *   · **图片**：一张图只有一次推理，饼图必然是"100% 一个颜色"的整圆，零信息量 →
 *     换成**档位刻度尺**（`SeverityMode.scale`）：0–63 的四档色段 + 当前分数指针 +
 *     档位文字。既不删组件，也不摆烂画个全色圆环。
 *
 * ★ 饼图直接复用统计页那套 `SeverityPieChart`（环形 + 自绘图例 + 环心文案），
 *   只多传一个 `centerText` 把环心从「N 例」改成「N 帧」——统计页零影响。
 * ★ 刻度尺是纯 ArkUI 节点（四段色带 + 指针），不引入新的图表依赖，结果确定可推演。
 */

import {
  SeverityMode, SeverityView, emptySeverityView, bandSpan
} from './AnalysisChartModel';
import { SeverityPieChart } from './SeverityPieChart';
import { UiTheme } from '../../common/UiTheme';
import { BDI_MAX_SCORE, SeverityLevel, UiConstant } from '../../types/Index';

/** 色带高度（vp） */
const BAND_HEIGHT: number = 10;

/** 指针高度（vp）· 比色带高，才像"标尺上的游标" */
const MARKER_HEIGHT: number = 16;

/** 指针宽度（vp） */
const MARKER_WIDTH: number = 3;

@ComponentV2
export struct SeverityDistributionCard {
  /** 取数结果（由 `AnalysisChartModel.buildSeverityView()` 算出） */
  @Param view: SeverityView = emptySeverityView();

  @Computed
  get isPie(): boolean {
    return this.view.mode === SeverityMode.pie;
  }

  @Computed
  get isScale(): boolean {
    return this.view.mode === SeverityMode.scale;
  }

  /**
   * 指针左侧权重 = 当前分数
   * ★ 两端各留一点点（0.001）：`layoutWeight(0)` 的节点不参与分配，
   *   拿 0 或满分时指针会贴边消失，看起来像 bug。
   */
  @Computed
  get leftWeight(): number {
    return Math.max(this.view.score, 0.001);
  }

  /** 指针右侧权重 = 满分 - 当前分数 */
  @Computed
  get rightWeight(): number {
    return Math.max(BDI_MAX_SCORE - this.view.score, 0.001);
  }

  /** 档位中文名（图例文字用） */
  private labelOf(level: SeverityLevel): string {
    return UiConstant.severityLabelOf(level);
  }

  /** 刻度尺上的一段色带 */
  @Builder
  band(level: SeverityLevel) {
    Row()
      .layoutWeight(bandSpan(level))
      .height(BAND_HEIGHT)
      .backgroundColor(UiConstant.severityColorOf(level))
  }

  /** 色带下方的档位名（宽度与色带同权重，保证对齐） */
  @Builder
  bandLabel(level: SeverityLevel) {
    Text(this.labelOf(level))
      .layoutWeight(bandSpan(level))
      .fontSize(UiTheme.fontSizeCaption)
      .fontColor(UiTheme.textSecondary)
      .textAlign(TextAlign.Center)
  }

  /** 刻度尺形态（图片 / 帧数不足 2） */
  @Builder
  scaleRuler() {
    Column({ space: UiTheme.gapS }) {
      // ── 指针（游标）──
      Row() {
        Row().layoutWeight(this.leftWeight)
        Row()
          .width(MARKER_WIDTH)
          .height(MARKER_HEIGHT)
          .borderRadius(2)
          .backgroundColor(this.view.levelColor)
        Row().layoutWeight(this.rightWeight)
      }
      .width('100%')
      .height(MARKER_HEIGHT)
      .alignItems(VerticalAlign.Center)

      // ── 四档色带（宽度按各档在 0–63 上的跨度分配）──
      Row() {
        this.band(SeverityLevel.none)
        this.band(SeverityLevel.mild)
        this.band(SeverityLevel.moderate)
        this.band(SeverityLevel.severe)
      }
      .width('100%')
      .height(BAND_HEIGHT)
      .borderRadius(BAND_HEIGHT / 2)
      .clip(true)

      // ── 档位名 ──
      Row() {
        this.bandLabel(SeverityLevel.none)
        this.bandLabel(SeverityLevel.mild)
        this.bandLabel(SeverityLevel.moderate)
        this.bandLabel(SeverityLevel.severe)
      }
      .width('100%')

      // ── 刻度端点 ──
      Row() {
        Text('0')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
        Text(`${BDI_MAX_SCORE}`)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
      }
      .width('100%')

      // ── 结论行 ──
      Row({ space: UiTheme.gapS }) {
        Text(this.view.score.toFixed(1))
          .fontSize(UiTheme.fontSizeMetric)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.view.levelColor)

        Text(`${this.view.levelLabel}（BDI-II ${this.view.score.toFixed(0)} 分）`)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(this.view.levelColor)
          .margin({ bottom: UiTheme.gapS })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 饼图形态（视频：帧级四档分布） */
  @Builder
  framePie() {
    Column({ space: UiTheme.gapS }) {
      SeverityPieChart({
        buckets: this.view.buckets,
        total: this.view.frameTotal,
        // 统计页写「N 例」，这里按"帧"口径覆盖（本组件只改环心文案）
        centerText: `${this.view.frameTotal} 帧`
      })

      Row({ space: UiTheme.gapS }) {
        Text(`主档位：${this.view.levelLabel}`)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(this.view.levelColor)
        Text(`最新帧 ${this.view.score.toFixed(1)} 分`)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: UiTheme.gapM }) {
      // ── 标题行 ──
      Column({ space: UiTheme.gapXs }) {
        Text(this.view.title)
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.view.subtitle.length > 0) {
          Text(this.view.subtitle)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.isPie) {
        this.framePie()
      } else if (this.isScale) {
        this.scaleRuler()
      } else {
        Column() {
          Text('开始分析后，这里会显示严重度分布')
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textSecondary)
        }
        .width('100%')
        .height(160)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(UiTheme.fillSoft)
        .borderRadius(UiTheme.cardRadius)
      }

      if (this.view.hint.length > 0) {
        Text(this.view.hint)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
