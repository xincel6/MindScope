/**
 * PlaceholderView · 一级页面的统一占位骨架
 *
 * 本轮五个页签（工作台/素材库/历史报告/统计/我的）"只实现页面跳转、内容全部占位"，
 * 五个页面的占位区完全一样 —— 所以抽成这一个组件，各页面只传自己的文案。
 *
 * 它同时满足规范里的两条：
 *   - 空数据时提供下一步操作  → 底部的"下一步操作"按钮
 *   - 不要同时使用太多颜色    → 只用中性灰阶 + 主色/辅助蓝
 *
 * 下一轮把真实内容填进来时：页面在 `hasContent` 为 true 时渲染真实内容、
 * 否则仍渲染本组件（骨架屏用 `SkeletonView`，错误态用 `ErrorRetryView`）。
 */

import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct PlaceholderView {
  /** 大字形占位图标（用单个汉字代替图片资源，本轮不引入新素材） */
  @Param glyph: string = '占';

  /** 占位标题 · 一般是页面名 */
  @Param title: string = '';

  /** 一句话说明这一页将来做什么 */
  @Param description: string = '';

  /** 补充提示（灰字，可为空） */
  @Param hint: string = '';

  /** 下一步操作按钮文案 */
  @Param actionLabel: string = '下一步操作';

  /** 下一步操作回调 */
  @Param onAction: () => void = () => {};

  build() {
    Column({ space: UiTheme.gapL }) {
      // 图标底 · 浅灰圆
      Column() {
        Text(this.glyph)
          .fontSize(28)
          .fontColor(UiTheme.textSecondary)
      }
      .width(UiTheme.emptyIconSize)
      .height(UiTheme.emptyIconSize)
      .borderRadius(UiTheme.emptyIconSize / 2)
      .backgroundColor(UiTheme.fillSoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: UiTheme.gapS }) {
        Text(this.title)
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Center)

        Text(this.description)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)

        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')

      Button(this.actionLabel)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.primary)
        .backgroundColor(Color.Transparent)
        .borderWidth(1)
        .borderColor(UiTheme.primary)
        .borderRadius(UiTheme.buttonRadius)
        .height(40)
        .padding({ left: UiTheme.gapXl, right: UiTheme.gapXl })
        .onClick(() => {
          this.onAction();
        })
    }
    .width('100%')
    .padding({ top: UiTheme.gapXxl * 2, bottom: UiTheme.gapXxl })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
