/**
 * EmotionCurveCard · 分析详情页「情绪曲线」卡片（原占位块 ①）
 *
 * ────────────────── 三种形态（由 `CurveView.mode` 决定）──────────────────
 *   ① `series`  → 逐帧 BDI 折线：**直接复用**工作台/统计页那套
 *      `components/charts/ScoreTrendChart.ets`（0–63 的 Y 轴、13/19/28 三条阈值虚线、
 *      四档图例），本卡片只补标题与说明，不重复实现图表逻辑。
 *   ② `flatLine` → **图片素材（或只收到 1 帧）**：只有一个分数，"随帧变化"不存在。
 *      按用户本轮的要求，这种情况**画成一条水平直线**，而不是让图表库画一个孤立点
 *      （单点在手机上几乎看不见，还会被误读成"没数据"）。
 *      直线与分数由 ArkUI 原生节点绘制，不依赖 mpchart，结果确定、可离线推演。
 *   ③ `empty`   → 还没出分：给一句"等待推理结果"，不画假图。
 *
 * ★ 为什么图片不用折线：折线的横轴是"帧序号"，一张图片只有第 1 帧，
 *   第二个点不存在。硬画折线等于编造"帧间变化"，在医疗类界面里是不能接受的。
 */

import {
  CurveMode, CurveView, emptyCurveView, severityMetaOf
} from './AnalysisChartModel';
import { ScoreTrendChart } from './ScoreTrendChart';
import { UiTheme } from '../../common/UiTheme';
import { SeverityLevel, SeverityMeta, UiConstant } from '../../types/Index';

/** 直线形态的绘图区高度（与折线图同高，切换素材类型时卡片不跳变） */
const FLAT_AREA_HEIGHT: number = 180;

@ComponentV2
export struct EmotionCurveCard {
  /** 取数结果（由 `AnalysisChartModel.buildCurveView()` 算出） */
  @Param view: CurveView = emptyCurveView();

  @Computed
  get isSeries(): boolean {
    return this.view.mode === CurveMode.series;
  }

  @Computed
  get isFlat(): boolean {
    return this.view.mode === CurveMode.flatLine;
  }

  /** 直线形态要标出来的那个分数 */
  @Computed
  get flatScore(): number {
    return this.view.points.length > 0 ? this.view.points[0] : 0;
  }

  /** 该分数对应的档位（直线颜色 + 标签都取它） */
  @Computed
  get flatMeta(): SeverityMeta {
    return severityMetaOf(this.flatScore);
  }

  /** 标题行（标题 + 副标题） */
  @Builder
  header() {
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
  }

  /** 四档区图例的一项（与 `ScoreTrendChart` 内的写法同构，保证两张卡视觉一致） */
  @Builder
  zoneItem(label: string, color: string) {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(8)
        .height(3)
        .borderRadius(2)
        .backgroundColor(color)

      Text(label)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
    }
    .layoutWeight(1)
  }

  /**
   * 直线形态：一条水平线 + 分数刻度点
   * ★ 用户原话："如果是一张图片，折线图也无法表示随着帧数的情绪变化了，这种情况直接变成直线吧"
   */
  @Builder
  flatChart() {
    Column({ space: UiTheme.gapM }) {
      // ── 直线本体：左端起于"第 1 帧"，右端是唯一的那个推理结果 ──
      Row({ space: UiTheme.gapS }) {
        Text('第 1 帧')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)

        Row()
          .layoutWeight(1)
          .height(2)
          .borderRadius(1)
          .backgroundColor(this.flatMeta.color)

        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.flatMeta.color)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ── 分数（重要数值用设计规范里的 32vp 大字号）──
      Row({ space: UiTheme.gapS }) {
        Text(this.flatScore.toFixed(1))
          .fontSize(UiTheme.fontSizeMetric)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.flatMeta.color)

        Text('BDI')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .margin({ bottom: UiTheme.gapS })

        Text(this.flatMeta.label)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(this.flatMeta.color)
          .margin({ bottom: UiTheme.gapS })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .height(FLAT_AREA_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  /** 四档图例（折线形态由 `ScoreTrendChart` 自带；直线形态在这里补上） */
  @Builder
  zoneLegend() {
    Column({ space: UiTheme.gapXs }) {
      Row({ space: UiTheme.gapS }) {
        this.zoneItem('正常 0-13', UiConstant.severityColorOf(SeverityLevel.none))
        this.zoneItem('轻度 14-19', UiConstant.severityColorOf(SeverityLevel.mild))
      }
      .width('100%')

      Row({ space: UiTheme.gapS }) {
        this.zoneItem('中度 20-28', UiConstant.severityColorOf(SeverityLevel.moderate))
        this.zoneItem('重度 29-63', UiConstant.severityColorOf(SeverityLevel.severe))
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
    Column({ space: UiTheme.gapM }) {
      this.header()

      if (this.isSeries) {
        // 折线形态：复用现成图表组件（它自带四档图例）
        ScoreTrendChart({ scores: this.view.points })
      } else if (this.isFlat) {
        this.flatChart()
        this.zoneLegend()
      } else {
        Column() {
          Text('开始分析后，这里会显示评分曲线')
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textSecondary)
        }
        .width('100%')
        .height(FLAT_AREA_HEIGHT)
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
