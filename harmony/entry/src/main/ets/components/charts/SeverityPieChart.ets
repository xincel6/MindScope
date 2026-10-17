/**
 * SeverityPieChart · 严重等级分布环形饼图（统计页）
 *
 * 数据契约（不变）：父页面传 `AppStore.statsBuckets`（SeverityBucketModel[]，
 *   label / count / color / ratio 都由 StatsMapper 摊平算好，本组件只负责画）+ 总数
 * 网页端对应：src/components/stats/SeverityPieChart.vue
 *
 * ★ 视觉参数（2026-10-17 第五轮，只动视觉，不动数据契约）：
 *   ① 圆环几何：环宽 16 / 内圆半径 60 / 外半径 76（外径 152）。
 *      mpchart 的饼图半径 = min(内容宽, 内容高) / 2，无折扣因子（实测验证），
 *      因此用「绘制高度 168 + 上下 extraOffsets 各 8」把内容高钉成 152 → 半径恒为 76；
 *      再令 holeRadius = 60 / 76 = 78.9% → 内圆 60、环厚 16，三个参数同时精确命中。
 *      扇区圆角【开启】：圆角半径 = 环厚一半（8），端头柔化；配 3vp 细缝，
 *      扇区之间有月牙形呼吸位（2026-10-17 真机对比两版后按用户偏好选定）。
 *   ② 扇区色板：降饱和语义色 正常 #17B26A / 轻度 #2E6BE6 / 中度 #F79009 / 重度 #F04438。
 *   ③ 环心：28fp/700/#1D2129 大数字 + 「总分析次数」11fp/#86909C，行距 4，绝对居中。
 *   ④ 图例 2×2：色块 10×10/圆角3 + 标签 12/#4E5969 + 数值 12/#1D2129，
 *      每项固定宽 132（两列对齐），行距 12 / 列距 24，整体居中。
 *   ⑤ 入场动画 animateY 800ms / ease_out（扇区展开）。
 *
 * ★ 保留的历史结论：
 *   - 图例自绘而不用 mpchart 内置 Legend（内置只显示 dataSet 名，无法带例数与占比）。
 *   - build 里挂 onAppear 再 invalidate：规避 mpchart 首帧 Canvas 时序竞态。
 *   - API 已对照 ohpm 源 3.0.30 源码核实。
 */

import { PieChart, PieChartModel, PieData, PieDataSet, PieEntry, JArrayList, Description, Legend } from '@ohos/mpchart';
import { SeverityBucketModel } from '../../types/Index';
import { UiTheme } from '../../common/UiTheme';

/**
 * 绘制高度（vp）
 *
 * ★ 不能直接用「外径 152 + 上下留白」：mpchart 的 PieRadarChartBase 会把
 *   `max(mMinOffset=10, extraOffset)` 和 `extraOffset` 各扣一次，实际内容高 =
 *   H - 2×max(10, inset) - 2×inset。inset=8 时相当于扣掉 36vp。
 *   要让圆环画出来正好 152（半径 76），H 必须是 152 + 36 = 188。
 *   （2026-10-17 真机实测：H=168 时环只有 ~132vp，比设计小一圈。）
 */
const PIE_HEIGHT: number = 188;

/** 上下留白（vp）· 与 mMinOffset 一起决定内容高，见上方公式 */
const PIE_VERTICAL_INSET: number = 8;

/** 中孔半径（% of 外半径）· 60 / 76 = 78.9%，即内圆 60vp、环厚 16vp */
const HOLE_RADIUS: number = 78.9;

/** 扇区入场动画时长（ms） */
const ANIM_DURATION: number = 800;

/** 兜底灰（视觉色板越界时用） */
const FALLBACK_COLOR: string = '#94A3B8';

@ComponentV2
export struct SeverityPieChart {
  /** 四档分布（正常 / 轻度 / 中度 / 重度，顺序由 mapper 保证） */
  @Param buckets: SeverityBucketModel[] = [];

  /** 分析总次数 · 画在环中心（对应网页端 pie-total 叠加层） */
  @Param total: number = 0;

  /**
   * 环心副标题文案（默认「总分析次数」）
   * ★ 工作台的 `SeverityDistributionCard` 复用本组件画"帧级分布"，
   *   会传 `${frameTotal} 帧` 覆盖口径 —— 统计页不传，走默认值。
   */
  @Param centerText: string = '总分析次数';

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

  /** 数据变化：buckets 是整体替换的新数组，这里重灌一次即可（顺带重播展开动画） */
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

  /** 视觉层色板映射：index 0-3 → 正常/轻度/中度/重度（mapper 保证顺序），越界回退数据色 */
  private sliceColor(index: number, fallback: string): string {
    const palette: string[] = UiTheme.severityPieColors;
    if (index >= 0 && index < palette.length) {
      return palette[index];
    }
    return fallback.length > 0 ? fallback : FALLBACK_COLOR;
  }

  /** 图例数值文案：例数 + 占比（数据不丢） */
  private legendValue(bucket: SeverityBucketModel): string {
    return `${bucket.count}例  ${Math.round(bucket.ratio * 100)}%`;
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
    this.model.setHoleRadius(HOLE_RADIUS);       // 内圆 60 / 环厚 16（见文件头几何说明）
    this.model.setTransparentCircleRadius(HOLE_RADIUS + 4); // 必须大于 holeRadius
    this.model.setTransparentCircleAlpha(0);     // 0 = 不要那圈"透明圆环"
    this.model.setHoleColor(this.toArgb(UiTheme.cardBackground));
    this.model.setDrawCenterText(false);         // 环心文字改用 ArkUI Stack 叠加
    this.model.setDrawEntryLabels(false);        // 扇区不标文字
    // 圆角扇区（圆角半径 = 环厚 / 2 = 8，由 mpchart 内部公式固定）
    // ★ 2026-10-17 真机对比后按用户偏好保留圆角版：直角切面虽更"精密"，
    //   但圆角端头更柔和、更符合整体圆润的调性。已配降饱和色板验证过。
    this.model.setDrawRoundedSlices(true);
    // 上下各 8 → 内容高 152 → 半径恒为 76；左右 0 不压缩宽度
    this.model.setExtraOffsets(0, PIE_VERTICAL_INSET, 0, PIE_VERTICAL_INSET);
    this.model.setRotationEnabled(false);        // 手机上禁用误触旋转
    this.model.setHighlightPerTapEnabled(false);
    this.model.setTouchEnabled(false);           // 外层是滚动容器，图表不抢手势
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
      colors.push(this.toArgb(this.sliceColor(i, bucket.color)));
    }

    const dataSet: PieDataSet = new PieDataSet(entries, '严重等级分布');
    dataSet.setColorsByArr(colors);            // 语义色板（见 sliceColor 映射）
    dataSet.setSliceSpace(UiTheme.pieSliceSpace); // 扇区间隙，圆角分段感更清晰
    dataSet.setDrawValues(false);              // 扇区不标数字（环心看总数、图例看明细）
    dataSet.setSelectionShift(0);              // 触摸已禁用，取消选中偏移保持圆环完整

    this.model.setData(new PieData(dataSet));
    this.model.invalidate();
    // 扇区从 0 展开的入场动画（UIContext 未就绪时由 mpchart 内部队列兜底）
    this.model.animateY(ANIM_DURATION, 'ease_out');
  }

  /** 环心叠加层：28/700 大数字 + 「总分析次数」11/#86909C，行距 4，绝对居中 */
  @Builder
  centerOverlay() {
    Column({ space: UiTheme.gapXs }) {
      Text(`${this.total}`)
        .fontSize(UiTheme.fontSizeChartCenter)
        .fontWeight(FontWeight.Bold)
        .fontColor(UiTheme.textPrimary)
        .maxLines(1)

      Text(this.centerText)
        .fontSize(UiTheme.fontSizeAxis)
        .fontColor(UiTheme.textSecondary)
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 单个图例项：色块 10×10/r3 + 标签 12/#4E5969 + 数值 12/#1D2129
   *
   * ★ 不用 Blank() 两端撑开（真机上会变成"正常 …… 82例 59%"的表格感），
   *   改成定宽标签 + 数值紧跟：色块与编号贴在一起，读起来是一个整体。
   */
  @Builder
  legendItem(bucket: SeverityBucketModel, index: number) {
    Row({ space: UiTheme.gapS }) {
      Row()
        .width(UiTheme.legendDotSize)
        .height(UiTheme.legendDotSize)
        .borderRadius(UiTheme.legendDotRadius)
        .backgroundColor(this.sliceColor(index, bucket.color))

      Text(bucket.label)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.legendLabelColor)
        .width(26)
        .maxLines(1)

      Text(this.legendValue(bucket))
        .fontSize(UiTheme.fontSizeCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.textPrimary)
        .maxLines(1)
    }
    .width(UiTheme.legendItemWidth)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: UiTheme.gapXs }) {
      // Stack 叠加：底层 Canvas 圆环 + 上层 ArkUI 环心文字
      Stack() {
        PieChart({ model: this.model })
          .width('100%')
          .height(PIE_HEIGHT)

        this.centerOverlay()
      }
      .width('100%')
      .height(PIE_HEIGHT)

      // 2×2 自绘图例：行距 12 / 列距 24，整体居中于圆环下方
      if (this.buckets.length > 0) {
        Column({ space: UiTheme.gapM }) {
          Row({ space: UiTheme.gapXl }) {
            this.legendItem(this.buckets[0], 0)
            if (this.buckets.length > 1) {
              this.legendItem(this.buckets[1], 1)
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)

          if (this.buckets.length > 2) {
            Row({ space: UiTheme.gapXl }) {
              this.legendItem(this.buckets[2], 2)
              if (this.buckets.length > 3) {
                this.legendItem(this.buckets[3], 3)
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
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
