/**
 * PageHeader · 统一页头（规范：页面标题 22vp）
 *
 * 每个页面自己画标题栏，而不是用系统 `Navigation` 的标题栏，原因：
 *  ① 系统标题栏的配色/字号不好完全对齐设计规范（22vp 正文色 #1E3A5F）；
 *  ② 页面标题需要和副标题、右侧动作按钮一起排版。
 * 所以 `Navigation` 一律 `hideTitleBar(true)`，标题交给本组件。
 *
 * 用法：
 * ```ts
 * PageHeader({ title: '工作台', subtitle: '今日概览' })
 * PageHeader({ title: '历史报告', showBack: true, onBack: () => { ... } })
 * ```
 */

import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct PageHeader {
  /** 页面标题（22vp） */
  @Param title: string = '';

  /** 副标题/说明 · 空串表示不显示 */
  @Param subtitle: string = '';

  /** 是否显示左上角返回按钮 */
  @Param showBack: boolean = false;

  /** 返回回调 · showBack 为 true 时生效 */
  @Param onBack: () => void = () => {};

  build() {
    Column({ space: UiTheme.gapXs }) {
      Row({ space: UiTheme.gapS }) {
        if (this.showBack) {
          // 返回键：用"‹"字符代替图片资源，避免本轮引入额外素材
          Text('‹')
            .fontSize(28)
            .fontColor(UiTheme.textPrimary)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .borderRadius(UiTheme.cardRadius)
            .onClick(() => {
              this.onBack();
            })
        }

        Text(this.title)
          .fontSize(UiTheme.fontSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

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
}
