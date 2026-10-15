/**
 * LogoPlaceholder · **品牌图标占位组件**
 *
 * 本轮登录/注册页顶部的"品牌图标"位置先用它顶着：主色圆角方块 + 一个"心"字。
 * 后期打磨 UI 时**只改这一个文件**即可换成真图标：
 * ```ts
 * // 例如拿到 app.media.brand_logo 之后，把 Column 换成：
 * Image($r('app.media.brand_logo'))
 *   .width(this._size).height(this._size).borderRadius(this.radius)
 * ```
 * 调用方（LoginPage / RegisterPage）不需要任何改动。
 */

import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct LogoPlaceholder {
  /**
   * 图标边长 · 默认 96vp
   * ★ 加 `_` 前缀：`size` 是系统属性方法名（`.size()`），同名会编译失败。
   */
  @Param _size: number = UiTheme.logoSize;

  /** 圆角 · 默认 20vp */
  @Param radius: number = UiTheme.logoRadius;

  /**
   * 底色 · 默认主色
   * ★ 加 `_` 前缀：`background` 是系统属性方法名（`.background()`），同名会编译失败。
   */
  @Param _background: string = UiTheme.primary;

  /** 占位字形/文案 · 默认"心"（"心理/情绪"语义，且有辨识度） */
  @Param glyph: string = '心';

  build() {
    Column() {
      Text(this.glyph)
        .fontSize(this._size * 0.42)
        .fontWeight(FontWeight.Bold)
        .fontColor(UiTheme.cardBackground)
    }
    .width(this._size)
    .height(this._size)
    .borderRadius(this.radius)
    .backgroundColor(this._background)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
