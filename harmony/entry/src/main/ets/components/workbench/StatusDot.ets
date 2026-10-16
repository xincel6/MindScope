/**
 * StatusDot · 统一状态圆点（服务状态 / 任务状态共用一个）
 *
 * 为什么抽出来：本轮至少两处要用"用颜色表达状态"的小圆点
 * （工作台顶部的服务状态、当前任务卡片的状态），
 * 各写一份 `Circle().width(8)` 迟早会出现"一个 8vp 一个 10vp"的漂移。
 *
 * ★ 圆点只承载颜色，**必须**配文字：只用颜色表达状态对色觉障碍用户不可读
 *   （所以调用方都同时给出"在线/未连接/分析中"这类文案）。
 */

import { UiTheme } from '../../common/UiTheme';

@ComponentV2
export struct StatusDot {
  /** 圆点颜色 */
  @Param dotColor: string = UiTheme.textSecondary;

  /** 直径 · 默认 8vp（页头用），卡片内可用 6vp */
  @Param dotSize: number = 8;

  build() {
    Circle()
      .width(this.dotSize)
      .height(this.dotSize)
      .fill(this.dotColor)
  }
}
