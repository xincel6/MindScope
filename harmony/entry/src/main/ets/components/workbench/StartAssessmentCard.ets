/**
 * StartAssessmentCard · 工作台主入口卡片「开始新的辅助评估」
 *
 * 布局：标题 + 一句话说明 + 图片/视频两种类型胶囊 + 整宽主按钮。
 * 整卡也可点（走 `RippleCard.onTap`），与按钮同一个动作 ——
 * 这是常见的"整卡即按钮"设计，比只让一个小按钮可点更好按。
 * ★ 两者的点击不会互相打架：
 *   点按钮触发按钮的 `onClick`；点卡片其他位置触发卡片的 `onClick`。
 *   ArkUI 中按钮会消费掉自己的点击，所以**不会**出现"一次点击触发两遍"。
 *
 * ★ 本轮（工作台主页重构）只做视觉加法：类型胶囊说明"支持什么"，
 *   按钮改为整宽以承担主 CTA；文字与颜色仍全部来自 `UiTheme`，不新增令牌。
 */

import { UiTheme } from '../../common/UiTheme';
import { RippleCard } from '../RippleCard';

@ComponentV2
export struct StartAssessmentCard {
  /** 点「选择素材」（或点整卡）· 窗口层跳素材选择页 */
  @Param onPick: () => void = () => {};

  /** 类型胶囊（圆点 + 文案）· 颜色只作为"图片/视频"的功能色 */
  @Builder
  typePill(label: string, tone: string) {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(tone)

      Text(label)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .maxLines(1)
    }
    .padding({ left: UiTheme.gapS, right: UiTheme.gapS, top: 5, bottom: 5 })
    .borderRadius(12)
    .backgroundColor(UiTheme.fillSoft)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    RippleCard({
      onTap: () => {
        this.onPick();
      }
    }) {
      Column({ space: UiTheme.gapM }) {
        Text('开始新的辅助评估')
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('选择一张图片或一段视频，服务端会逐帧推理并给出 BDI 辅助评分')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Row({ space: UiTheme.gapS }) {
          this.typePill('图片 · 单次推理', UiTheme.primary)
          this.typePill('视频 · 逐帧采样', UiTheme.accent)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Button('选择素材')
          .width('100%')
          .height(48)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.cardBackground)
          .backgroundColor(UiTheme.primary)
          .borderRadius(UiTheme.buttonRadius)
          .onClick(() => {
            this.onPick();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
