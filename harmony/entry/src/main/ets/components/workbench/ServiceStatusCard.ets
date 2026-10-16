/**
 * ServiceStatusCard · 工作台顶部「服务状态 + 刷新」
 *
 * 两件事：
 *   ① 服务状态：小圆点（绿=已连接 / 红=未连接）+ 文字；
 *   ② 刷新按钮：位于最右侧，**与背景完全重合**（无边框、无底色、无阴影），
 *      图标暂用字符 `⟳` 占位（用户已说明图标待选，本轮不引入图片资源）。
 *
 * ★ 为什么不用 `Image` 占位：工程 `resources/base/media/` 里目前只有应用图标，
 *   塞一张不相干的图当"刷新"会让人以为是最终设计；用字符既能立刻看到效果，
 *   将来换图标只需把 `Text('⟳')` 换成 `Image($r('app.media.ic_refresh'))` 一行。
 *
 * ★ 点刷新会真正调 `/health` 探活（`onRefresh` 由窗口层实现），
 *   而不是只把圆点改个颜色 —— 状态必须来自服务端。
 */

import { UiTheme } from '../../common/UiTheme';
import { StatusDot } from './StatusDot';

@ComponentV2
export struct ServiceStatusCard {
  /** 服务端是否在线 */
  @Param online: boolean = false;

  /** 状态文案（"在线" / "未连接"） */
  @Param label: string = '未连接';

  /** 是否正在探活（刷新按钮的禁用与文案切换） */
  @Param checking: boolean = false;

  /** 服务端地址展示（次要文字，帮现场排查连的是哪台机器） */
  @Param serverLabel: string = '';

  /** 点刷新 · 窗口层调 AppStore.checkHealth() */
  @Param onRefresh: () => void = () => {};

  /** 状态圆点颜色 */
  @Computed
  get dotColor(): string {
    return this.online ? UiTheme.statusOnline : UiTheme.statusOffline;
  }

  build() {
    Row({ space: UiTheme.gapS }) {
      StatusDot({ dotColor: this.dotColor, dotSize: 8 })

      Column({ space: UiTheme.gapXs }) {
        Text(this.label)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(this.online ? UiTheme.textPrimary : UiTheme.danger)
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.serverLabel.length > 0) {
          Text(this.serverLabel)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 刷新按钮 · 与背景完全重合（透明底 + 无边框），只有字形可见
      Button(this.checking ? '…' : '⟳')
        .fontSize(20)
        .fontColor(UiTheme.textSecondary)
        .backgroundColor(Color.Transparent)
        .borderRadius(UiTheme.cardRadius)
        .width(40)
        .height(40)
        .enabled(!this.checking)
        .onClick(() => {
          this.onRefresh();
        })
    }
    .width('100%')
    .padding({ top: UiTheme.gapXs, bottom: UiTheme.gapXs })
    .alignItems(VerticalAlign.Center)
  }
}
