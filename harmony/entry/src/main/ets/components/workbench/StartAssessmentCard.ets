/**
 * StartAssessmentCard · 工作台主入口卡片「开始新的辅助评估」
 *
 * 布局：标题 + 一句话说明 + 右下角主色按钮「选择素材」。
 * 整卡也可点（走 `RippleCard.onTap`），与按钮同一个动作 ——
 * 这是常见的"整卡即按钮"设计，比只让一个小按钮可点更好按。
 *
 * ★ 两者的点击不会互相打架：
 *   点按钮触发按钮的 `onClick`；点卡片其他位置触发卡片的 `onClick`。
 *   ArkUI 中按钮会消费掉自己的点击，所以**不会**出现"一次点击触发两遍"。
 */

import { UiTheme } from '../../common/UiTheme';
import { RippleCard } from '../RippleCard';

@ComponentV2
export struct StartAssessmentCard {
  /** 点「选择素材」（或点整卡）· 窗口层跳素材选择页 */
  @Param onPick: () => void = () => {};

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

        Text('选择一段图片或视频，服务端会逐帧推理并给出 BDI 辅助评分')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Row() {
          Button('选择素材')
            .height(44)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.cardBackground)
            .backgroundColor(UiTheme.primary)
            .borderRadius(UiTheme.buttonRadius)
            .padding({ left: UiTheme.gapXl, right: UiTheme.gapXl })
            .onClick(() => {
              this.onPick();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
