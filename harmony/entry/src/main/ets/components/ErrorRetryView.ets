/**
 * ErrorRetryView · 错误提示 + 重试按钮（规范：网络失败时提供重试按钮）
 *
 * 使用场景：
 *  ① 登录/注册页：服务端地址不通、探活失败时显示在表单下方；
 *  ② 下一轮各业务页：`param.errorMsg` 非空时整块替换内容区。
 */

import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct ErrorRetryView {
  /** 错误文案 · 一般直接展示数据层已经本地化好的 message */
  @Param message: string = '';

  /** 重试按钮文案 */
  @Param retryLabel: string = '重试';

  /** 是否正在重试 · true 时按钮禁用并改文案 */
  @Param retrying: boolean = false;

  /** 重试回调 */
  @Param onRetry: () => void = () => {};

  build() {
    Column({ space: UiTheme.gapS }) {
      Text(this.message)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.danger)
        .width('100%')
        .textAlign(TextAlign.Start)

      Button(this.retrying ? '重试中…' : this.retryLabel)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.accent)
        .backgroundColor(Color.Transparent)
        .borderWidth(1)
        .borderColor(UiTheme.accent)
        .borderRadius(UiTheme.buttonRadius)
        .height(36)
        .padding({ left: UiTheme.gapL, right: UiTheme.gapL })
        .enabled(!this.retrying)
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
