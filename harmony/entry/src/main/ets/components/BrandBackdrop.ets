/**
 * BrandBackdrop · **品牌底色**（待机页与登录页共用的一层青绿渐变）
 *
 * 为什么单独抽成一个组件：待机页和登录页在转场里必须是**同一张底**。
 * 两处各写一份渐变色值，早晚会漂成两个色，而转场时那 400ms 用户盯着的
 * 正是这层底 —— 一旦有色差，看起来就像闪屏。
 *
 * ★ `expandSafeArea`：渐变要铺到状态栏与导航栏底下。
 *   不铺的话，安全区之外露出的是页面底色（浅灰 `pageBackground`），
 *   整屏青绿上会多出上下两条浅色横带，第一眼就穿帮。
 */
import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct BrandBackdrop {
  build() {
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({
        // 竖向渐变（略斜 8°）：比纯竖直多一点点方向感，又不至于像打光
        angle: 172,
        colors: [[UiTheme.brandStart, 0.0], [UiTheme.brandEnd, 1.0]]
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
