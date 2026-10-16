/**
 * SeverityPieChart · 严重等级分布环形饼图（统计页）
 *
 * 数据契约：父页面传 `AppStore.statsBuckets`（SeverityBucketModel[]，
 *   label / count / color / ratio 都由 StatsMapper 摊平算好，本组件只负责画）+ 总数
 * 网页端对应：src/components/stats/SeverityPieChart.vue
 *   （ECharts 环形图 radius 55%~80% + 圆心「N 例」叠加层 + 底部图例）
 *
 * ★ 为什么图例自己画而不用 mpchart 的内置 Legend：
 *   内置 Legend 只显示 dataSet 名（一行），无法像网页端那样列出「正常/轻度/中度/重度」
 *   四项并带例数与占比；所以关掉内置图例，用 ArkUI 画一条 2×2 图例，视觉与网页端一致。
 *
 * ★ 为什么 build 里挂了 onAppear 再 invalidate 一次：
 *   mpchart 的 PieChart 在 Canvas.onReady 里【只 setContext2D、不 onDraw】，
 *   首帧是否出图取决于 onAreaChange 的触发时序；在 V1 图表嵌进 V2 组件、
 *   又包在 if/else 分支里时，时序并不保证 → 曾出现「饼图空白」。
 *   这里在挂载后主动补一次重绘（再延迟一帧兜底），彻底消除该竞态。
 *
 * ★ API 已对照 ohpm 源 3.0.30 源码核实（见 docs/交接说明-统计页图表.md 第六节）。
 */

import { PieChart, PieChartModel, PieData, PieDataSet, PieEntry, JArrayList, Description, Legend } from '@ohos/mpchart';
import { SeverityBucketModel } from '../../types/Index';
import { UiTheme } from '../../common/UiTheme';

/** 饼图绘制高度（vp） */
const PIE_HEIGHT: number = 200;

/** 兜底灰（bucket.color 异常时用） */
const FALLBACK_COLOR: string = '#94A3B8';

@ComponentV2
export struct SeverityPieChart {
  /** 四档分布（正常 / 轻度 / 中度 / 重度，顺序由 mapper 保证） */
  @Param buckets: SeverityBucketModel[] = [];

  /** 分析总次数 · 画在环中心（对应网页端 pie-total 叠加层） */
  @Param total: number = 0;

  private model: PieChartModel = new PieChartModel();

  /** 组件是否已销毁 · 延迟重绘前先看它，避免往已释放的 Canvas 上画 */
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.applyStyle();
    this.render();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  /** 数据变化：buckets 是整体替换的新数组，这里重灌一次即可 */
  @Monitor('buckets')
  private onBucketsChanged(): void {
    this.render();
  }

  @Monitor('total')
  private onTotalChanged(): void {
    this.render();
  }

  /** '#RRGGBB' → 0xAARRGGBB（mpchart 的颜色 API 只收数字，不收字符串） */
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
    // Description 默认文本是 "Description Label"，必须显式清掉并禁用
    const desc: Description = new Description();
    desc.setText('');
    desc.setEnabled(false);
    this.model.setDescription(desc);

    // 内置图例关掉（本组件自绘图例，见文件头注释）
    const legend: Legend | null = this.model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }

    this.model.setUsePercentValues(false);
    this.model.setDrawHoleEnabled(true);
    this.model.setHoleRadius(56);              // 环形中孔（对应网页端 radius ['55%','80%']）
    this.model.setTransparentCircleRadius(60); // 必须大于 holeRadius，否则会画出一圈错位色
    this.model.setTransparentCircleAlpha(0);   // 0 = 不要那圈"透明圆环"（网页端没有）
    this.model.setHoleColor(this.toArgb(UiTheme.cardBackground));
    this.model.setDrawCenterText(true);
    this.model.setCenterTextSize(20);
    this.model.setCenterTextColor(this.toArgb(UiTheme.textPrimary));
    this.model.setDrawEntryLabels(false);      // 扇区不标文字（对应网页端 label.show=false）
    this.model.setExtraOffsets(6, 6, 6, 6);
    this.model.setRotationEnabled(false);      // 手机上禁用误触旋转
    this.model.setHighlightPerTapEnabled(false);
    this.model.setTouchEnabled(false);         // 外层是滚动容器，图表不抢手势
  }

  /** 把数据灌进模型 · 数据变化后必须 invalidate 才重绘 */
  private render(): void {
    if (this.buckets.length === 0) {
      return;
    }

    const entries: JArrayList<PieEntry> = new JArrayList<PieEntry>();
    const colors: number[] = [];
    for (let i = 0; i < this.buckets.length; i++) {
      const bucket: SeverityBucketModel = this.buckets[i];
      entries.add(new PieEntry(bucket.count, bucket.label));
      colors.push(this.toArgb(bucket.color));
    }

    const dataSet: PieDataSet = new PieDataSet(entries, '严重等级分布');
    dataSet.setColorsByArr(colors);   // 多色 API 是 setColorsByArr（不是 setColors）
    dataSet.setSliceSpace(2);
    dataSet.setDrawValues(false);     // 扇区不标数字（中心看总数、图例看明细）
    dataSet.setSelectionShift(4);

    this.model.setData(new PieData(dataSet));
    this.model.setCenterText(this.total > 0 ? `${this.total} 例` : '');
    this.model.invalidate();
  }

  /** 单个图例项：色点 + 标签 + 例数 + 占比 */
  @Builder
  legendItem(bucket: SeverityBucketModel) {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(bucket.color.length > 0 ? bucket.color : FALLBACK_COLOR)

      Text(`${bucket.label} ${bucket.count}`)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)

      Text(`${Math.round(bucket.ratio * 100)}%`)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textPrimary)
    }
    .layoutWeight(1)
  }

  build() {
    Column({ space: UiTheme.gapS }) {
      PieChart({ model: this.model })
        .width('100%')
        .height(PIE_HEIGHT)

      // 2×2 自绘图例（与网页端底部图例同构，额外补了例数与占比）
      if (this.buckets.length > 0) {
        Column({ space: UiTheme.gapXs }) {
          Row({ space: UiTheme.gapS }) {
            this.legendItem(this.buckets[0])
            if (this.buckets.length > 1) {
              this.legendItem(this.buckets[1])
            }
          }
          .width('100%')

          Row({ space: UiTheme.gapS }) {
            if (this.buckets.length > 2) {
              this.legendItem(this.buckets[2])
            }
            if (this.buckets.length > 3) {
              this.legendItem(this.buckets[3])
            }
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
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
