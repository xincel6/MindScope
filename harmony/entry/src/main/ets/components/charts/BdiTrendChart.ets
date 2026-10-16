/**
 * BdiTrendChart · BDI 日均趋势折线（统计页）
 *
 * 数据契约：父页面传 `AppStore.statsSummary.bdiTrend`（BdiTrendPointModel[]：
 *   date 'YYYY-MM-DD' / avgScore 0~63）
 * 网页端对应：src/components/stats/BdiTrendChart.vue
 *   （ECharts：平滑曲线 + 面积填充 + Y 轴固定 0–63 + markLine 13/19/28 三条阈值虚线）
 *
 * ★ 本轮修的问题：
 *   ① 「折线图整个看不到」——根因在页面层（StatsPage 没有 Scroll，第二张卡片被顶出屏幕），
 *      页面已加 Scroll；本组件只负责把图本身画好。
 *   ② 「Y 轴 / 阈值线不对」——阈值线用 removeAllLimitLines() 先清再加，杜绝重复累积；
 *      Y 轴显式钉死 0–63，并固定 5 个刻度。
 *   ③ 「首帧空白」——见文件尾 onAppear 注释（与饼图同一竞态）。
 *
 * ★ API 已对照 ohpm 源 3.0.30 源码核实（见 docs/交接说明-统计页图表.md 第六节）。
 */

import {
  LineChart, LineChartModel, LineData, LineDataSet, EntryOhos, JArrayList,
  Description, Legend, XAxisPosition, YAxisLabelPosition, LimitLine, LimitLabelPosition,
  IAxisValueFormatter, AxisBase, Mode, ChartColorStop
} from '@ohos/mpchart';
import { BdiTrendPointModel, UiConstant } from '../../types/Index';
import { UiTheme } from '../../common/UiTheme';

/** 折线绘制高度（vp） */
const LINE_HEIGHT: number = 200;

/** BDI-II 量表满分（Y 轴上限，与网页端一致） */
const BDI_MAX: number = 63;

/** 三条等级阈值（与网页端 markLine 一致：13 / 19 / 28） */
const THRESHOLDS: number[] = [13, 19, 28];

/** 阈值线配色取自的严重度 key（正常 / 轻度 / 中度） */
const THRESHOLD_KEYS: string[] = ['none', 'mild', 'moderate'];

/** 手机窄屏最多显示几个 X 轴标签（其余抽稀掉，避免糊成一团） */
const MAX_X_LABELS: number = 5;

/**
 * X 轴类目标签 · 'YYYY-MM-DD' → 'M/D'，并按步长抽稀
 * （签名按官方 demo 的双参写法）
 */
class TrendDateFormatter implements IAxisValueFormatter {
  private dates: string[] = [];
  private step: number = 1;

  constructor(dates: string[], step: number) {
    this.dates = dates;
    this.step = step < 1 ? 1 : step;
  }

  public getFormattedValue(value: number, axis: AxisBase): string {
    const index: number = Math.round(value);
    if (index < 0 || index >= this.dates.length) {
      return '';
    }
    // 抽稀：非步长整数倍不显示；但最后一根永远显示，保证右边界有标签
    if (index % this.step !== 0 && index !== this.dates.length - 1) {
      return '';
    }
    const parts: string[] = this.dates[index].split('-');
    if (parts.length === 3) {
      return `${parseInt(parts[1], 10)}/${parseInt(parts[2], 10)}`;
    }
    return this.dates[index];
  }
}

@ComponentV2
export struct BdiTrendChart {
  /** 趋势点（date + avgScore），空数组时本组件不渲染图表（由页面兜底文案） */
  @Param trend: BdiTrendPointModel[] = [];

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

  /** 数据变化：trend 是整体替换的新数组 */
  @Monitor('trend')
  private onTrendChanged(): void {
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

  /** 与数据无关的样式：只在挂载时配一次 */
  private applyStyle(): void {
    const desc: Description = new Description();
    desc.setText('');
    desc.setEnabled(false);
    this.model.setDescription(desc);

    // 卡片标题已说明图表含义，关掉内置图例（单条 dataSet 的图例没有信息量）
    const legend: Legend | null = this.model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }

    this.model.setDrawGridBackground(false);
    this.model.setPinchZoom(false);
    this.model.setScaleEnabled(false);
    this.model.setDragEnabled(false);
    this.model.setTouchEnabled(false);   // 外层滚动容器优先，图表不抢手势

    // ── Y 轴：钉死 0–63，固定 5 个刻度 ──
    const yAxis = this.model.getAxisLeft();
    yAxis?.setAxisMinimum(0);
    yAxis?.setAxisMaximum(BDI_MAX);
    yAxis?.setLabelCount(5, true);
    yAxis?.setPosition(YAxisLabelPosition.OUTSIDE_CHART);
    yAxis?.setDrawGridLines(true);
    yAxis?.setDrawAxisLine(false);
    yAxis?.setGranularity(1);
    yAxis?.setTextColor(this.toArgb(UiTheme.textSecondary));

    // 右 Y 轴不需要
    this.model.getAxisRight()?.setEnabled(false);

    // ── X 轴：底部、无网格线、按索引取标签 ──
    const xAxis = this.model.getXAxis();
    xAxis?.setPosition(XAxisPosition.BOTTOM);
    xAxis?.setDrawGridLines(false);
    xAxis?.setDrawAxisLine(true);
    xAxis?.setGranularity(1);            // x 只能取整数索引，防止标签错位
    xAxis?.setAvoidFirstLastClipping(true);
    xAxis?.setTextColor(this.toArgb(UiTheme.textSecondary));
  }

  /** 把数据灌进模型 · 数据变化后必须 invalidate 才重绘 */
  private render(): void {
    if (this.trend.length === 0) {
      return;
    }

    const dates: string[] = [];
    const entries: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
    for (let i = 0; i < this.trend.length; i++) {
      dates.push(this.trend[i].date);
      entries.add(new EntryOhos(i, this.trend[i].avgScore));
    }

    // 这个移植版没有 LineEntry，折线点用基类 EntryOhos
    const dataSet: LineDataSet = new LineDataSet(entries, 'BDI 日均');
    dataSet.setMode(Mode.CUBIC_BEZIER);        // 平滑曲线（对应网页端 smooth: true）
    dataSet.setColorByColor(this.toArgb(UiTheme.primary));
    dataSet.setLineWidth(2);
    dataSet.setDrawCircles(true);
    dataSet.setCircleColor(this.toArgb(UiTheme.primary));
    dataSet.setCircleRadius(3.5);
    dataSet.setDrawCircleHole(false);          // 实心点，手机上更清楚
    dataSet.setDrawValues(false);

    // 面积填充（对应网页端 areaStyle）：ChartColorStop = [8 位 hex, 渐变位置]，0 在折线处、1 在底部
    dataSet.setDrawFilled(true);
    const fill: JArrayList<ChartColorStop> = new JArrayList<ChartColorStop>();
    fill.add(['#400D9488', 0]);
    fill.add(['#000D9488', 1]);
    dataSet.setGradientFillColor(fill);

    // LineData 只收 ILineDataSet[] / JArrayList<ILineDataSet>，不收单个 dataSet
    this.model.setData(new LineData([dataSet]));

    // X 轴标签按点数抽稀
    const step: number = Math.ceil(this.trend.length / MAX_X_LABELS);
    this.model.getXAxis()?.setValueFormatter(new TrendDateFormatter(dates, step));

    // ── 三条阈值虚线：先清旧线再加，否则重复 render 会累积成 6/9 条 ──
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

  build() {
    LineChart({ model: this.model })
      .width('100%')
      .height(LINE_HEIGHT)
      .onAppear(() => {
        // 见文件头注释：补一次重绘，规避 Canvas onReady / onAreaChange 时序竞态
        this.model.invalidate();
        setTimeout(() => {
          if (!this.disposed) {
            this.model.invalidate();
          }
        }, 60);
      })
  }
}
