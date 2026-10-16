/**
 * AttentionHeatmap · 注意力热力图**面板**（大图 + 色带图例 + Top-3 医学解读）
 *
 * ★ 本轮（实装轮）的结构调整 —— 只搬位置，不改算法：
 *   原来"矩阵 → PixelMap、三层叠放、标注框"这一整套都写在本文件里，尺寸硬编码 200vp。
 *   但分析详情页要做**视频切分视图**：横向排开很多张热力图（几十帧，每帧一张）。
 *   所以把"一张热力图方块"抽成 `HeatmapTile.ets`（尺寸可传），本文件改为**薄壳**：
 *
 *     AttentionHeatmap            ← 详情页主图 / 探测页用的"面板"（200vp + 图例 + 解读）
 *       └── HeatmapTile           ← 可复用的最小单元（尺寸可传，自己管 PixelMap）
 *
 *   · `HeatmapUtil` / `HeatHotspot` 现在**只有一份实现**，在 `HeatmapTile.ets` 里，
 *     本文件重新导出（`export { ... from ... }`），所以
 *     `import { HeatmapUtil } from '.../AttentionHeatmap'` 的既有调用方**无需改动**。
 *   · 视觉与算法口径**逐位未变**，离线一致性测试仍在守卫：
 *     `node harmony/scripts/test-heatmap-consistency.mjs`
 *
 * ────────────────── 与 Web 端的对应关系 ──────────────────
 * Web 实现：`dashboard/src/components/center-panel/FacePreview.vue`
 *   单张 200×200 Canvas + 画布外的 CSS 色带（低 → 高）+ 医学解读文案。
 *   本文件负责的正是"画布之外"那一层：色带与解读。
 *
 * ★ 关键 API 均已核实（见报告"证据清单"一节）：
 *   Image(src: PixelMap | ResourceStr | ...) / .interpolation() / .opacity()  @since 8/9
 *   linearGradient({ angle, colors: [color, stop][] })                        @since 7
 */

import { UiTheme } from '../../common/UiTheme';
import {
  HEAT_COLORMAP, HeatHotspot, HeatmapTile, HeatmapUtil
} from './HeatmapTile';

// ★ 重新导出纯函数层：保持既有 import 路径可用，同时保证算法**只有一份实现**
export { HeatHotspot, HeatmapUtil } from './HeatmapTile';

/** 面板默认方块边长（vp）· 与 Web 端 `SIZE = 200` 对齐 */
const DEFAULT_SIZE: number = 200;

/**
 * 注意力热力图面板
 *
 * 用法（父页面）：
 * ```ts
 * AttentionHeatmap({
 *   heatmap: this.heatmapData,                    // number[][] 16×16，值域 0..1
 *   faceDataUrl: this.alignedFaceDataUrl,         // 'data:image/jpeg;base64,...' 或裸 base64
 *   smooth: true
 * })
 * ```
 */
@ComponentV2
export struct AttentionHeatmap {
  /** 16×16 注意力矩阵（行优先，`data[y][x]`），空数组表示尚无数据 */
  @Param heatmap: number[][] = [];

  /** 对齐人脸图 · 支持 `data:image/...;base64,` 前缀，也支持裸 base64 */
  @Param faceDataUrl: string = '';

  /** 是否把 16×16 平滑放大（true=High 插值 / false=逐格方块，与 Web 逐格一致） */
  @Param smooth: boolean = true;

  /**
   * 面板边长（vp）· 默认 200，与 Web 端同口径
   *
   * ★ 字段名**不能叫 `size`**：`CustomComponent` 基类已有 `size(value: SizeOptions)`
   *   属性方法，同名会编译失败（见 `HeatmapTile.ets` 里的同一处说明）。
   */
  @Param panelSize: number = DEFAULT_SIZE;

  /** 是否显示方块里的 4 个解剖区域标注框 */
  @Param showAnnotations: boolean = true;

  /** 是否显示下方色带图例 */
  @Param showColorBar: boolean = true;

  /** 是否显示 Top-3 热点解读文案 */
  @Param showHotspotText: boolean = true;

  @Local private boxSize: number = DEFAULT_SIZE;

  aboutToAppear(): void {
    this.boxSize = this.panelSize;
  }

  @Monitor('panelSize')
  private onSizeChanged(): void {
    this.boxSize = this.panelSize;
  }

  /** 是否有可展示的热度数据（用矩阵形状判断，不看 PixelMap —— 它现在归 HeatmapTile 持有） */
  @Computed
  get hasData(): boolean {
    const data: number[][] = this.heatmap;
    return data.length > 0 && data[0].length > 0;
  }

  /** 医学解读文案（与 Web 端 `medical-notes` 的句子结构一致） */
  @Computed
  get hotspotText(): string {
    const list: HeatHotspot[] = HeatmapUtil.hotspots(this.heatmap, 3);
    if (list.length === 0) {
      return '';
    }
    let text: string = `重点关注 ${list[0].region}（${list[0].percent}%）`;
    if (list.length > 1) {
      text += `，其次 ${list[1].region}（${list[1].percent}%）`;
    }
    return text;
  }

  build() {
    Column({ space: UiTheme.gapS }) {
      // ── 主图：一张热力图方块（复用 HeatmapTile，尺寸由本面板指定） ──
      HeatmapTile({
        heatmap: this.heatmap,
        faceDataUrl: this.faceDataUrl,
        panelSize: this.boxSize,
        smooth: this.smooth,
        showAnnotations: this.showAnnotations
      })

      // ── 色带图例（用 ArkUI 原生 linearGradient，不必进 Canvas） ──
      if (this.hasData && this.showColorBar) {
        Row({ space: UiTheme.gapS }) {
          Text('低')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
          Row()
            .layoutWeight(1)
            .height(6)
            .borderRadius(3)
            .linearGradient({ angle: 90, colors: HEAT_COLORMAP })
          Text('高')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
        }
        .width(this.boxSize)
        .alignItems(VerticalAlign.Center)
      }

      // ── Top-3 热点解读 ──
      if (this.hotspotText.length > 0 && this.showHotspotText) {
        Text(this.hotspotText)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width(this.boxSize)
          .textAlign(TextAlign.Start)
      }
    }
    .width(this.boxSize)
    .alignItems(HorizontalAlign.Start)
  }
}
