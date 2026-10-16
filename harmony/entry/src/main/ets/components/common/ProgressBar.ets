/**
 * ProgressBar · 通用横向进度条（轨道 + 填充）
 *
 * 本轮有两处用到它，语义不同但外观一致：
 *   ① 工作台「最近使用的素材」—— 填充 = BDI 严重度（越长越严重），颜色按档位变；
 *   ② 分析详情页 —— 填充 = 分析进度。
 *
 * ★ 填充宽度用 `layoutWeight` 而不是字符串百分比：
 *   `layoutWeight` 由布局引擎按权重精确分配，不存在 `Math.round` 带来的
 *   "99% 看起来像 100%" 这类舍入问题；而百分比字符串在极小比例下会被取整成 0。
 *
 * ★ 按设计规范"少用大面积效果"，这里不做流光/呼吸动画：
 *   进度本身变化时由调用方决定要不要包 `animateTo`（详情页就这么做）。
 */

import { UiTheme } from '../../common/UiTheme';

@ComponentV2
export struct ProgressBar {
  /** 填充比例 0–1（超出范围会被夹紧，不会画出界） */
  @Param ratio: number = 0;

  /** 填充色 · 由调用方按严重度/进度语义传入 */
  @Param barColor: string = UiTheme.primary;

  /** 条高 · 默认 8vp；更细的次要指标可用 4vp */
  @Param barHeight: number = UiTheme.progressHeight;

  /** 轨道色 */
  @Param trackColor: string = UiTheme.progressTrack;

  /** 夹紧后的填充权重（1 - 它 就是右侧空白权重） */
  @Computed
  get fill(): number {
    if (!Number.isFinite(this.ratio)) {
      return 0;
    }
    if (this.ratio <= 0) {
      return 0;
    }
    return this.ratio >= 1 ? 1 : this.ratio;
  }

  build() {
    Row() {
      // 填充段（比例 0 时不渲染，避免出现 0 宽度的空节点）
      if (this.fill > 0) {
        Row()
          .layoutWeight(this.fill)
          .height('100%')
          .backgroundColor(this.barColor)
          .borderRadius(this.barHeight / 2)
      }
      // 剩余段（比例 1 时不渲染）
      if (this.fill < 1) {
        Row()
          .layoutWeight(1 - this.fill)
          .height('100%')
      }
    }
    .width('100%')
    .height(this.barHeight)
    .backgroundColor(this.trackColor)
    .borderRadius(this.barHeight / 2)
  }
}
