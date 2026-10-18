/**
 * PatientNameDialog · 患者命名输入对话框（@CustomDialog）
 *
 * 用于：① 上传素材时给素材命名患者；② 事后重命名素材所属患者。
 * 用法（窗口层）：
 * ```ts
 * const ctrl = new CustomDialogController({
 *   builder: PatientNameDialog({
 *     title: '为素材命名所属患者',
 *     initial: '',
 *     onConfirm: (name) => { ... }
 *   })
 * });
 * ctrl.open();
 * ```
 */

import { UiTheme } from '../common/UiTheme';

@CustomDialog
export struct PatientNameDialog {
  /** 对话框控制器 · 由 CustomDialog 框架注入 */
  controller: CustomDialogController = new CustomDialogController({ builder: PatientNameDialog() });

  /** 标题 */
  title: string = '为素材命名所属患者';

  /** 初始值（重命名时回填） */
  initial: string = '';

  /** 确认回调 · 参数为输入的患者名（已去首尾空格） */
  onConfirm: (patient: string) => void = (patient: string) => {};

  /** 输入框内容 */
  @State inputValue: string = '';

  aboutToAppear(): void {
    this.inputValue = this.initial;
  }

  build() {
    Column({ space: UiTheme.gapL }) {
      Text(this.title)
        .fontSize(UiTheme.fontSizeSection)
        .fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({ text: this.inputValue, placeholder: '请输入患者姓名（可留空）' })
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textPrimary)
        .placeholderColor(UiTheme.textSecondary)
        .height(UiTheme.controlHeight)
        .backgroundColor(UiTheme.fillSoft)
        .borderRadius(UiTheme.cardRadius)
        .onChange((value: string) => {
          this.inputValue = value;
        })

      Row({ space: UiTheme.gapS }) {
        Button('取消')
          .type(ButtonType.Normal)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .backgroundColor(Color.Transparent)
          .borderWidth(1)
          .borderColor(UiTheme.divider)
          .borderRadius(UiTheme.buttonRadius)
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.controller.close();
          })

        Button('确定')
          .type(ButtonType.Normal)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor('#FFFFFF')
          .backgroundColor(UiTheme.primary)
          .borderRadius(UiTheme.buttonRadius)
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            const value: string = this.inputValue.trim();
            this.onConfirm(value);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(UiTheme.gapL)
    .alignItems(HorizontalAlign.Start)
  }
}
