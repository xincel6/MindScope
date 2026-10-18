/**
 * PatientNameDialog · 患者命名输入对话框（@CustomDialog）
 *
 * 用于：① 上传素材时给素材命名患者；② 事后重命名素材所属患者。
 * 用法（窗口层）：
 * ```ts
 * this.dialogCtrl = new CustomDialogController({
 *   builder: PatientNameDialog({
 *     title: '为素材命名所属患者',
 *     initial: '',
 *     onConfirm: (name) => { ... }
 *   })
 * });
 * this.dialogCtrl.open();
 * ```
 */

import { UiTheme } from '../common/UiTheme';

@CustomDialog
export struct PatientNameDialog {
  /**
   * 对话框控制器 · `@CustomDialog` 语法要求必须声明该属性（编译器强制）
   *
   * ★ 但**不要在对话框内部调用它**：本页由 V2 页面的 `CustomDialogController` 动态创建时，
   *   这个字段取不到注入值，`this.controller.close()` 会抛
   *   `TypeError: Cannot read property close of undefined` 并把应用打崩（真机实测）。
   *   关闭动作统一由持有 controller 的页面负责（见 `MainPage.promptPatientName`）。
   */
  controller?: CustomDialogController;

  /** 标题 */
  title: string = '为素材命名所属患者';

  /** 初始值（重命名时回填） */
  initial: string = '';

  /**
   * 确认回调 · 参数为输入的患者名（已去首尾空格）
   *
   * ★ 对话框的关闭由**持有 controller 的页面**负责（见 `MainPage.promptPatientName`）：
   *   本页在 V2 页面里由 `CustomDialogController` 动态创建时，组件内的 `controller`
   *   字段取不到注入值；在这里调 `this.controller.close()` 会抛
   *   `TypeError: Cannot read property close of undefined` 并把应用打崩（真机实测）。
   */
  onConfirm: (patient: string) => void = (patient: string) => {};

  /** 取消回调 · 由页面关闭对话框 */
  onCancel: () => void = () => {};

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
            this.onCancel();
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
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(UiTheme.gapL)
    .alignItems(HorizontalAlign.Start)
  }
}
