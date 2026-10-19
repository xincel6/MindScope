/**
 * ScoreTrendChart · 逐帧评分曲线（工作台分析区的情绪曲线）
 *
 * 数据契约：父页面传一个 `number[]`（本次分析逐帧 BDI 分数）
 *   · 工作台：`AppStore.analysisSessionOf(当前任务 id).scores`
 *   · 分析区：`AnalysisChartModel.buildCurveView().points`
 *     —— 那里已经把"图片素材只有 1 个分数"的情形分流成直线形态（本组件只负责 ≥2 点的折线）
 *
 * 网页端对应：`dashboard/src/components/right-panel/EmotionCurve.vue`
 *   （BDI-II 评分曲线：折线 + 面积填充 + Y 轴 0–63 + 四档严重度区图例；
 *     网页端每个点按分数分色，mpchart 的单条 LineDataSet 不支持逐点配色，
 *     这里改为「整条线用主色 + 保留下方四档区图例」来承载同一语义）
 *
 * ★ 与 BdiTrendChart 的区别：BdiTrendChart 吃的是「按天聚合的日均分」（统计页），
 *   本组件吃的是「一次分析会话内的逐帧分」，X 轴是帧序号而不是日期。
 *
 * ★ API 已对照 ohpm 源 3.0.30 源码核实（见 docs/交接说明-统计页图表.md 第六节）。
 */

import {
  LineChart, LineChartModel, LineData, LineDataSet, EntryOhos, JArrayList,
  Description, Legend, XAxisPosition, YAxisLabelPosition, LimitLine, LimitLabelPosition,
  IAxisValueFormatter, AxisBase, Mode, ChartColorStop
} from '@ohos/mpchart';
import { UiConstant } from '../../types/Index';
import { UiTheme } from '../../common/UiTheme';

/** 绘制高度（vp） */
const CURVE_HEIGHT: number = 180;

/** BDI-II 量表满分（Y 轴上限） */
const BDI_MAX: number = 63;

/** 三条等级阈值（正常/轻度、轻度/中度、中度/重度 的分界） */
const THRESHOLDS: number[] = [13, 19, 28];

/** 阈值线配色取自的严重度 key */
const THRESHOLD_KEYS: string[] = ['none', 'mild', 'moderate'];

/** 手机窄屏最多显示几个 X 轴标签 */
const MAX_X_LABELS: number = 5;

/**
 * X 轴标签 · 帧序号（1 基）· 按步长抽稀
 * 签名按官方 demo 的双参写法
 */
class FrameAxisFormatter implements IAxisValueFormatter {
  private count: number = 0;
  private step: number = 1;

  constructor(count: number, step: number) {
    this.count = count;
    this.step = step < 1 ? 1 : step;
  }

  public getFormattedValue(value: number, axis: AxisBase): string {
    const index: number = Math.round(value);
    if (index < 0 || index >= this.count) {
      return '';
    }
    if (index % this.step !== 0 && index !== this.count - 1) {
      return '';
    }
    return `${index + 1}`;
  }
}

@ComponentV2
export struct ScoreTrendChart {
  /** 逐帧分数序列（空数组 → 显示空态文案，不白屏） */
  @Param scores: number[] = [];

  private model: LineChartModel = new LineChartModel();

  /** 组件是否已销毁 · 延迟重绘前先看它，避免往已释放的 Canvas 上画 */
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.applyStyle();
    this.render();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  /** 每来一帧分数，传入的都是新数组 → 重灌数据 */
  @Monitor('scores')
  private onScoresChanged(): void {
    this.render();
  }

  /** '#RRGGBB' → 0xAARRGGBB */
  private toArgb(hex: string): number {
    const clean: string = hex.replace('#', '');
    if (clean.length < 6) {
      return 0xFF94A3B8;
    }
    const r: number = parseInt(clean.substring(0, 2), 16);
    const g: number = parseInt(clean.substring(2, 4), 16);
    const b: number = parseInt(clean.substring(4, 6), 16);
    return 0xFF000000 + (r << 16) + (g << 8) + b;
  }

  private applyStyle(): void {
    const desc: Description = new Description();
    desc.setText('');
    desc.setEnabled(false);
    this.model.setDescription(desc);

    const legend: Legend | null = this.model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }

    this.model.setDrawGridBackground(false);
    this.model.setPinchZoom(false);
    this.model.setScaleEnabled(false);
    this.model.setDragEnabled(false);
    this.model.setTouchEnabled(false);

    const yAxis = this.model.getAxisLeft();
    yAxis?.setAxisMinimum(0);
    yAxis?.setAxisMaximum(BDI_MAX);
    yAxis?.setLabelCount(5, true);
    yAxis?.setPosition(YAxisLabelPosition.OUTSIDE_CHART);
    yAxis?.setDrawGridLines(true);
    yAxis?.setDrawAxisLine(false);
    yAxis?.setGranularity(1);
    yAxis?.setTextColor(this.toArgb(UiTheme.textSecondary));

    this.model.getAxisRight()?.setEnabled(false);

    const xAxis = this.model.getXAxis();
    xAxis?.setPosition(XAxisPosition.BOTTOM);
    xAxis?.setDrawGridLines(false);
    xAxis?.setDrawAxisLine(true);
    xAxis?.setGranularity(1);
    xAxis?.setAvoidFirstLastClipping(true);
    xAxis?.setTextColor(this.toArgb(UiTheme.textSecondary));
  }

  private render(): void {
    if (this.scores.length === 0) {
      return;
    }

    const entries: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
    for (let i = 0; i < this.scores.length; i++) {
      entries.add(new EntryOhos(i, this.scores[i]));
    }

    const dataSet: LineDataSet = new LineDataSet(entries, '实时评分');
    dataSet.setMode(Mode.LINEAR);              // 网页端 smooth: false（逐帧折线不美化）
    dataSet.setColorByColor(this.toArgb(UiTheme.primary));
    dataSet.setLineWidth(2);
    dataSet.setDrawCircles(true);
    dataSet.setCircleColor(this.toArgb(UiTheme.primary));
    dataSet.setCircleRadius(3);
    dataSet.setDrawCircleHole(false);
    dataSet.setDrawValues(false);

    dataSet.setDrawFilled(true);
    const fill: JArrayList<ChartColorStop> = new JArrayList<ChartColorStop>();
    fill.add(['#400D9488', 0]);
    fill.add(['#000D9488', 1]);
    dataSet.setGradientFillColor(fill);

    this.model.setData(new LineData([dataSet]));

    const step: number = Math.ceil(this.scores.length / MAX_X_LABELS);
    this.model.getXAxis()?.setValueFormatter(new FrameAxisFormatter(this.scores.length, step));

    // 三条阈值虚线：先清再加，避免逐帧重绘时累积
    const yAxis = this.model.getAxisLeft();
    yAxis?.removeAllLimitLines();
    for (let i = 0; i < THRESHOLDS.length; i++) {
      const color: string = UiConstant.severityColor(THRESHOLD_KEYS[i]);
      const line: LimitLine = new LimitLine(THRESHOLDS[i], `${THRESHOLDS[i]}`);
      line.setLineColor(this.toArgb(color));
      line.setLineWidth(1);
      line.enableDashedLine(6, 6, 0);
      line.setLabelPosition(LimitLabelPosition.RIGHT_TOP);
      line.setTextSize(9);
      line.setTextColor(this.toArgb(color));
      yAxis?.addLimitLine(line);
    }

    this.model.invalidate();
  }

  /** 四档严重度区图例项（对应网页端 zone-legend） */
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

  build() {
    Column({ space: UiTheme.gapS }) {
      if (this.scores.length === 0) {
        Column() {
          Text('开始分析后，这里会实时显示评分曲线')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
        }
        .width('100%')
        .height(CURVE_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        LineChart({ model: this.model })
          .width('100%')
          .height(CURVE_HEIGHT)
          .onAppear(() => {
            this.model.invalidate();
            setTimeout(() => {
              if (!this.disposed) {
                this.model.invalidate();
              }
            }, 60);
          })
      }

      // 四档区间图例（2×2）
      Row({ space: UiTheme.gapS }) {
        this.zoneItem('正常 0-13', UiConstant.severityColor('none'))
        this.zoneItem('轻度 14-19', UiConstant.severityColor('mild'))
      }
      .width('100%')

      Row({ space: UiTheme.gapS }) {
        this.zoneItem('中度 20-28', UiConstant.severityColor('moderate'))
        this.zoneItem('重度 29-63', UiConstant.severityColor('severe'))
      }
      .width('100%')
    }
    .width('100%')
  }
}
