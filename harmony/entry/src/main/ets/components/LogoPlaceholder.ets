/**
 * LogoPlaceholder · **应用图标（浅色页面用的那一版）**
 *
 * 名字保留了"Placeholder"的旧称，内容已经不是占位了：它就是应用图标本体
 * （青绿圆角方块 + 白色标记），与应用启动图标、待机页/登录页用的是同一张素材。
 *
 * ══════════════════ 什么时候用它、什么时候用 `BrandHero` ══════════════════
 * · 页面底色是**浅色**（注册页这类）→ 用本组件：青绿方块给标记当底，
 *   否则白色标记放在浅灰底上等于看不见；
 * · 页面底色是**品牌青绿**（待机页 / 登录页）→ 用 `BrandHero`：方块底会与背景融成一片，
 *   露出来的正是同一个标记。
 *
 * ★ 素材是透明 PNG（`media/brand_mark.png`），不含圆角也不含底色 ——
 *   圆角、底色、尺寸都在这里给，同一张图能长成任意尺寸而不糊。
 */
import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct LogoPlaceholder {
  /**
   * 方块边长 · 默认 96vp
   * ★ 加 `_` 前缀：`size` 是系统属性方法名（`.size()`），同名会编译失败。
   */
  @Param _size: number = UiTheme.logoSize;

  /** 圆角 · 默认 20vp */
  @Param radius: number = UiTheme.logoRadius;

  build() {
    Stack() {
      Image($r('app.media.brand_mark'))
        // 标记占方块的 62%：与系统图标里"前景占安全区"的比例大致对齐，
        // 和桌面上的启动图标并排看，留白感是同一个。
        .width('62%')
        .aspectRatio(UiTheme.brandMarkAspect)
        .objectFit(ImageFit.Contain)
    }
    .width(this._size)
    .height(this._size)
    .borderRadius(this.radius)
    .linearGradient({
      angle: 172,
      colors: [[UiTheme.brandStart, 0.0], [UiTheme.brandEnd, 1.0]]
    })
    // ★ 必须裁切：方块的圆角只对"自身背景"生效，里面的图片仍会画成直角
    .clip(true)
  }
}
