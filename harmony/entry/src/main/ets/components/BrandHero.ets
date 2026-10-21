/**
 * BrandHero · **品牌区**（图标 + "MindScope" + 产品名）
 *
 * 这个组件是待机页 → 登录页那次转场的"锚点"：两个页面都用它、都在
 * `UiTheme.heroTop` 这个位置上、都用 `UiTheme.heroLogoWidth` 这个**布局宽度**。
 * 于是转场真正发生的事只有两件：
 *   ① 图标在**原地**长大（`logoScale` 0.76 → 1，只缩图形、不改布局盒）；
 *   ② 白色表单层从屏幕下方盖上来。
 * 图标本身**不移动、不重画、不换图**，下面的文字也不动，所以谈不上"闪"。
 *
 * ★ 图片是透明底的白色标记（`media/brand_mark.png`），底色由父级给：
 *   待机页/登录页给青绿渐变，注册页这类浅色页面给 `LogoPlaceholder` 的青绿方块。
 */
import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct BrandHero {
  /** 标记的布局宽度（高度按 `brandMarkAspect` 推）· 待机页与登录页必须一致 */
  @Param logoWidth: number = UiTheme.heroLogoWidth;

  /**
   * 标记的绘制缩放 · 只改图形、不改布局（`.scale()` 不参与排版）
   *
   * 待机页给它 `heroLogoStart`（0.84）→ 切页前 Window 层把它推到 1（在待机页上完成），
   * 登录页直接给 1。文字位置始终对齐，所以"长大"这件事看不出接缝。
   */
  @Param logoScale: number = 1;

  /** 文字淡入进度 · 与图标分开控制：图标先到位，文字跟上 */
  @Param textOpacity: number = 1;

  build() {
    Column() {
      Image($r('app.media.brand_mark'))
        .width(this.logoWidth)
        .aspectRatio(UiTheme.brandMarkAspect)
        .objectFit(ImageFit.Contain)
        .scale({ x: this.logoScale, y: this.logoScale })

      Text('MindScope')
        .fontSize(UiTheme.heroTitleSize)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(1.2)
        .fontColor(UiTheme.onBrand)
        .margin({ top: UiTheme.gapL })
        .opacity(this.textOpacity)

      Text('抑郁症智能辅助评估')
        .fontSize(UiTheme.heroProductSize)
        .fontColor(UiTheme.onBrandMuted)
        .margin({ top: UiTheme.gapXs })
        .opacity(this.textOpacity)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
