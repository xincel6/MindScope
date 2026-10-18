/**
 * AnalysisVlmCard · 工作台分析区的「智能解读」卡
 *
 * 原分析详情页只在有 `vlmText` 时才渲染这张卡；工作台把它固定成分析区的一节，
 * 这样即使本次分析没有触发解读，用户也能看到"为什么没有"而不是一块空白：
 *   · 有文本 → 正常展示；
 *   · 实时分析未完成 → 「分析完成后会生成一段文字解读」；
 *   · 本机归档没有保留 → 「本机未保留本次分析的文字解读」。
 *
 * ★ 本组件只画内容，白卡底/圆角/投影由外层 `RippleCard` 提供。
 * ★ 文案不在这里判断"有没有会话"：`emptyHint` 由工作台按会话状态算好传入。
 */

import { UiTheme } from '../../common/UiTheme';

@ComponentV2
export struct AnalysisVlmCard {
  /** 解读正文（空串 = 没有） */
  @Param text: string = '';

  /** 没有正文时的说明 · 由工作台按运行/归档状态给 */
  @Param emptyHint: string = '';

  build() {
    Column({ space: UiTheme.gapS }) {
      Text('智能解读')
        .fontSize(UiTheme.fontSizeSection)
        .fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(this.text.length > 0 ? this.text : this.emptyHint)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(this.text.length > 0 ? UiTheme.textPrimary : UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
