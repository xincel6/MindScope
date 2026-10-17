/**
 * BdiTrendChart · BDI 日均趋势折线（统计页）
 *
 * 数据契约（不变）：父页面传 `AppStore.statsSummary.bdiTrend`（BdiTrendPointModel[]：
 *   date 'YYYY-MM-DD' / avgScore 0~63）
 * 网页端对应：src/components/stats/BdiTrendChart.vue（ECharts：平滑曲线 + 面积填充 +
 *   Y 轴固定 0–63 + markLine 阈值线）
 *
 * ★ 视觉参数（2026-10-17 第五轮，只动视觉，不动数据契约）：
 *   ① 网格：只保留横向虚线 #E5E6EB / 1vp（4-6 虚线节奏）；纵向网格线与坐标轴线全部关闭；
 *      Y 轴刻度文字 11fp/#86909C，刻度短线随轴线一起隐藏。
 *   ② 折线：#00B42A / 2.5vp，CUBIC_BEZIER 平滑（对应网页端 smooth: true）。
 *   ③ 数据点：白心描边——填充 #FFFFFF、描边 2vp #00B42A（radius 4 / hole 2）。
 *   ④ 渐变面积：#00B42A @15% → 完全透明，垂直向下。
 *   ⑤ 阈值线（两条，细实线 + 右端数值标注，禁止整条虚线）：
 *      19 分线 #165DFF / 1vp / 右端「19」11fp 同色；
 *      28 分线 #FF7D00 / 1vp / 右端「28」11fp 同色。
 *   ⑥ 入场动画 animateX 900ms / ease_out（X 轴从左向右绘制）。
 *
 * ★ 保留的历史结论：
 *   - Y 轴显式钉死 0–63（与网页端一致）、4 档刻度；阈值线 removeAllLimitLines() 先清再加防累积。
 *   - X 轴按索引取标签 + 抽稀（MAX_X_LABELS），最后一根永远显示。
 *   - build 里挂 onAppear 再 invalidate：规避首帧 Canvas 时序竞态。
 *   - API 已对照 ohpm 源 3.0.30 源码核实。
 */

import {
  LineChart, LineChartModel, LineData, LineDataSet, EntryOhos, JArrayList,
  Description, Legend, XAxisPosition, YAxisLabelPosition, LimitLine, LimitLabelPosition,
  IAxisValueFormatter, AxisBase, Mode, ChartColorStop
} from '@ohos/mpchart';
import { BdiTrendPointModel } from '../../types/Index';
import { UiTheme } from '../../common/UiTheme';

/** 折线绘制高度（vp）· 留足 X 轴标签行（= UiTheme.lineHeight） */
const LINE_HEIGHT: number = 232;

/** BDI-II 量表满分（Y 轴硬上限，与网页端一致） */
const BDI_MAX: number = 63;

/** Y 轴最小可视上限（保证 28 分阈值线不贴顶，且低分数据不塌到底部） */
const Y_MIN_MAX: number = 40;

/** Y 轴刻度档数（0 / 中值 / 上限 三档，横线不密不疏） */
const Y_LABEL_COUNT: number = 3;

/** 两条阈值线数值（与 UiTheme.chartThresholdColors 一一对应：19 蓝 / 28 橙） */
const THRESHOLDS: number[] = [19, 28];

/** 手机窄屏最多显示几个 X 轴标签（其余抽稀掉，避免糊成一团） */
const MAX_X_LABELS: number = 6;

/** 折线入场动画时长（ms） */
const ANIM_DURATION: number = 900;

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

  /** 数据变化：trend 是整体替换的新数组（顺带重播展开动画） */
  @Monitor('trend')
  private onTrendChanged(): void {
    this.render();
  }

  /** '#RRGGBB' → 0xAARRGGBB（alpha 默认 FF） */
  private toArgb(hex: string, alpha: number = 0xFF): number {
    const clean: string = hex.replace('#', '');
    if (clean.length < 6) {
      return 0xFF94A3B8;
    }
    const r: number = parseInt(clean.substring(0, 2), 16);
    const g: number = parseInt(clean.substring(2, 4), 16);
    const b: number = parseInt(clean.substring(4, 6), 16);
    return (alpha << 24) + (r << 16) + (g << 8) + b;
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

    this.model.setDrawGridBackground(false);       // 画布背景透明
    this.model.setPinchZoom(false);
    this.model.setScaleEnabled(false);
    this.model.setDragEnabled(false);
    this.model.setTouchEnabled(false);             // 外层滚动容器优先，图表不抢手势
    this.model.setExtraOffsets(10, 10, 26, 2);     // 左侧让 Y 轴刻度贴住绘图区，右侧给阈值标注留位

    // ── Y 轴：只留横向虚线网格，轴线与刻度短线全部隐藏 ──
    // 上限在 render() 里按数据动态钉（见 yAxisMax），这里先给一个安全初值
    const yAxis = this.model.getAxisLeft();
    yAxis?.setAxisMinimum(0);
    yAxis?.setAxisMaximum(Y_MIN_MAX);
    yAxis?.setLabelCount(Y_LABEL_COUNT, true);
    yAxis?.setPosition(YAxisLabelPosition.OUTSIDE_CHART);
    yAxis?.setDrawGridLines(true);                 // 只保留横向网格线
    yAxis?.setDrawAxisLine(false);                 // 无轴线 → 无刻度短线
    yAxis?.setDrawLabels(true);                    // 11fp 浅灰刻度文字保留
    yAxis?.setGranularity(1);
    yAxis?.setGridColor(this.toArgb(UiTheme.chartGrid));   // #E5E6EB
    yAxis?.setGridLineWidth(1);                    // 1vp
    yAxis?.enableGridDashedLine(4, 4, 0);          // 4-4 虚线节奏（4-6 在真机屏上几乎断成点）
    yAxis?.setTextSize(UiTheme.fontSizeAxis);      // 11fp（降权弱化）
    yAxis?.setTextColor(this.toArgb(UiTheme.textSecondary)); // #86909C

    // 右 Y 轴不需要
    this.model.getAxisRight()?.setEnabled(false);

    // ── X 轴：纵向网格线 / 轴线全关，只留 11fp 浅灰日期标签 ──
    const xAxis = this.model.getXAxis();
    xAxis?.setPosition(XAxisPosition.BOTTOM);
    xAxis?.setDrawGridLines(false);                // 纵向网格线全部删除
    xAxis?.setDrawAxisLine(false);                 // 底部不留基线，画面更干净
    xAxis?.setDrawLabels(true);
    xAxis?.setGranularity(1);                      // x 只能取整数索引，防止标签错位
    xAxis?.setAvoidFirstLastClipping(true);        // 首尾标签内移，不被画布裁掉
    xAxis?.setTextSize(UiTheme.fontSizeAxis);      // 11fp
    xAxis?.setTextColor(this.toArgb(UiTheme.textSecondary)); // #86909C
  }

  /**
   * Y 轴上限（视觉自适应 · 只影响刻度范围，不改任何数据）
   *
   * 固定 0–63 时，日均分 10–20 的常态数据会整条塌在底部、上方大片空白，
   * 所以按「最高分 × 1.15，向上取 4 的倍数」自适应，下限 40（保证 28 分阈值线
   * 不贴顶）、上限 64（满分 63 之上取整，三档刻度 0 / 32 / 64 仍是整数）。
   */
  private yAxisMax(): number {
    let maxScore: number = 0;
    for (let i = 0; i < this.trend.length; i++) {
      if (this.trend[i].avgScore > maxScore) {
        maxScore = this.trend[i].avgScore;
      }
    }
    const wanted: number = Math.ceil((maxScore * 1.15) / 4) * 4;
    const bounded: number = Math.max(Y_MIN_MAX, wanted);
    return bounded > BDI_MAX ? 64 : bounded;
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
    dataSet.setMode(Mode.CUBIC_BEZIER);            // 平滑曲线（对应网页端 smooth: true）
    dataSet.setCubicIntensity(0.2);               // 柔和不过弯
    dataSet.setColorByColor(this.toArgb(UiTheme.statAccent)); // #00B42A
    dataSet.setLineWidth(UiTheme.lineWidth);       // 2.5vp，图表绝对视觉主体
    // 白心描边圆点：外圈描边 #00B42A 2vp（radius 4 - hole 2），内心白
    dataSet.setDrawCircles(true);
    dataSet.setCircleColor(this.toArgb(UiTheme.statAccent));
    dataSet.setCircleRadius(UiTheme.linePointRadius);
    dataSet.setDrawCircleHole(true);
    dataSet.setCircleHoleRadius(UiTheme.linePointHoleRadius);
    dataSet.setCircleHoleColor(this.toArgb(UiTheme.cardBackground));
    dataSet.setDrawValues(false);

    // 面积填充：#00B42A @15% → 完全透明，垂直向下渐变（对应网页端 areaStyle）
    dataSet.setDrawFilled(true);
    const fill: JArrayList<ChartColorStop> = new JArrayList<ChartColorStop>();
    fill.add([UiTheme.chartLineFillTop, 0]);
    fill.add([UiTheme.chartLineFillBottom, 1]);
    dataSet.setGradientFillColor(fill);

    // LineData 只收 ILineDataSet[] / JArrayList<ILineDataSet>，不收单个 dataSet
    this.model.setData(new LineData([dataSet]));

    // X 轴标签按点数抽稀
    const step: number = Math.ceil(this.trend.length / MAX_X_LABELS);
    this.model.getXAxis()?.setValueFormatter(new TrendDateFormatter(dates, step));

    // ── 两条阈值线：先清旧线再加防累积；细实线 1vp + 右端数值标注 ──
    // 19 分线 #165DFF / 28 分线 #FF7D00（UiTheme.chartThresholdColors 一一对应）
    // 阈值线挂之前先把 Y 轴上限钉好，否则阈值标注会被裁到画布外
    const yAxis = this.model.getAxisLeft();
    yAxis?.setAxisMaximum(this.yAxisMax());
    yAxis?.removeAllLimitLines();
    for (let i = 0; i < THRESHOLDS.length; i++) {
      const color: string = UiTheme.chartThresholdColors[i];
      const line: LimitLine = new LimitLine(THRESHOLDS[i], `${THRESHOLDS[i]}`);
      line.setLineColor(this.toArgb(color));
      line.setLineWidth(1);                        // 细实线（不虚线横贯）
      line.enableDashedLine(0, 0, 0);              // 显式关掉虚线（0/0 = 实线）
      line.setLabelPosition(LimitLabelPosition.RIGHT_TOP); // 右端标注
      line.setTextSize(UiTheme.fontSizeAxis);      // 11fp 同色数值
      line.setTextColor(this.toArgb(color));
      yAxis?.addLimitLine(line);
    }

    this.model.invalidate();
    // 从左向右的入场展开动画（ease_out 收尾；UIContext 未就绪时由内部队列兜底）
    this.model.animateX(ANIM_DURATION, 'ease_out');
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
