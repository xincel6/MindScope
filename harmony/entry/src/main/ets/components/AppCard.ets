/**
 * AppCard · 统一卡片容器（规范：卡片背景 #FFFFFF、圆角 16vp、极淡投影）
 *
 * 用法：
 * ```ts
 * AppCard({ title: '账号信息' }) {
 *   Text('内容')
 * }
 * ```
 *
 * ★ `@BuilderParam content` 必须给默认实现，否则组件在不传尾随闭包时会编译失败；
 *   这里默认渲染一个空行，保证任何调用方式都合法。
 */

import { CardStyle } from '../common/CardStyle';
import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct AppCard {
  /** 卡片标题 · 空串表示不显示标题区 */
  @Param title: string = '';

  /** 卡片副标题 · 空串表示不显示 */
  @Param subtitle: string = '';

  /**
   * 卡片内边距 · 默认 16vp
   *
   * ★ 字段名必须加 `_` 前缀：`padding` 是 ArkUI 自定义组件的**系统属性方法名**
   *   （`.padding()` 继承自 `CommonAttribute`），同名成员会被判定为
   *   "Property 'padding' in type 'AppCard' is not assignable to the same property in base type 'CustomComponent'"
   *   而编译失败。本工程约定：凡是与系统属性同名的入参，一律加 `_` 前缀。
   */
  @Param _padding: number = UiTheme.cardPadding;

  /** 卡片内容（用尾随闭包传入） */
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
    Row().width('100%').height(0)
  }

  build() {
    Column({ space: UiTheme.gapM }) {
      if (this.title.length > 0) {
        Column({ space: UiTheme.gapXs }) {
          Text(this.title)
            .fontSize(UiTheme.fontSizeSection)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.textPrimary)
            .width('100%')
            .textAlign(TextAlign.Start)
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(this._padding)
    // ★ 卡片视觉内联写：不要抽成共享的 AttributeModifier
    //   （原因见 common/CardStyle.ets 顶部说明：共享修饰器实例会让卡片整片不渲染）
    .backgroundColor(CardStyle.background())
    .borderRadius(UiTheme.cardRadius)
    // 灰底白卡：极淡投影负责"浮起"，1px 描边负责"收边"（见 common/CardStyle.ets）
    .border({ width: 1, color: CardStyle.borderColor() })
    .shadow(CardStyle.shadow())
  }
}
