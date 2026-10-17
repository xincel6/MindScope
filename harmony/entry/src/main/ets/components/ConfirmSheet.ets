/**
 * ConfirmSheet · **二次确认弹层**（本轮新增 · 供「我的」页的退出登录使用）
 *
 * 为什么不用系统 `AlertDialog`：本工程的视觉规范集中在 `common/UiTheme.ets`，
 * 系统弹窗的圆角/字号/配色都不受控；自己画一层只需 40 行，且能保证
 * "退出登录"这个按钮与全应用其它按钮是同一套手感。
 *
 * 结构（`Stack` 两层，顺序即层级）：
 * ```
 * ① 遮罩：整屏 60% 不透明度 —— 点它取消（busy 时忽略）
 * ② 面板：标题 + 说明 + 两个按钮，弹性放大淡入
 * ```
 *
 * ★ 遮罩用"叶子节点 + opacity"表达半透明，不用 8 位 ARGB 色值
 *   （`BUG清单.md` BUG-09：8 位色值在部分场景会被判为非法）。
 * ★ 只有 `opacity` / `scale` / `translate` 参与动画，尺寸恒定。
 * ★ 纯展示组件：点"确定"只回调 `onConfirm`，页面/窗口层决定真正做什么。
 */

import { curves } from '@kit.ArkUI';
import { UiTheme } from '../common/UiTheme';

/** 遮罩不透明度 · 足够压暗背景，又不至于看不见下面的内容 */
const SCRIM_OPACITY: number = 0.32;

@ComponentV2
export struct ConfirmSheet {
  /** 标题 · 如「退出登录」 */
  @Param title: string = '';

  /** 说明文案 · 讲清后果（如"本地缓存与登录状态都会被清除"） */
  @Param message: string = '';

  /** 确认按钮文案 */
  @Param confirmLabel: string = '确定';

  /** 取消按钮文案 */
  @Param cancelLabel: string = '取消';

  /** 是否正在执行（true 时两个按钮都禁用，文案由页面自己改） */
  @Param busy: boolean = false;

  /** 点取消 / 点遮罩 */
  @Param onCancel: () => void = () => {};

  /** 点确认 */
  @Param onConfirm: () => void = () => {};

  // ── 动画状态 ──
  @Local panelOpacity: number = 0;
  @Local panelScale: number = 0.94;
  @Local panelOffsetY: number = 16;

  aboutToAppear(): void {
    // 复位 + 弹性放大淡入（一次 animateTo 足够：弹簧自己带过冲）
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      this.panelOpacity = 0;
      this.panelScale = 0.94;
      this.panelOffsetY = 16;
    });
    this.getUIContext().animateTo({ curve: curves.springMotion(0.4, 0.7) }, (): void => {
      this.panelOpacity = 1;
      this.panelScale = 1;
      this.panelOffsetY = 0;
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // ① 遮罩 · 点它取消
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(UiTheme.textPrimary)
        .opacity(SCRIM_OPACITY)
        .onClick((): void => {
          if (!this.busy) {
            this.onCancel();
          }
        })

      // ② 面板
      Column({ space: UiTheme.gapL }) {
        Column({ space: UiTheme.gapS }) {
          Text(this.title)
            .fontSize(UiTheme.fontSizeSection)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.textPrimary)
            .width('100%')
            .textAlign(TextAlign.Start)

          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: UiTheme.gapM }) {
          Button(this.cancelLabel)
            .layoutWeight(1)
            .height(UiTheme.controlHeight)
            .fontSize(UiTheme.fontSizeSection)
            .fontColor(UiTheme.textSecondary)
            .backgroundColor(Color.Transparent)
            .borderWidth(1)
            .borderColor(UiTheme.divider)
            .borderRadius(UiTheme.buttonRadius)
            .enabled(!this.busy)
            .onClick((): void => {
              this.onCancel();
            })

          Button(this.confirmLabel)
            .layoutWeight(1)
            .height(UiTheme.controlHeight)
            .fontSize(UiTheme.fontSizeSection)
            .fontColor(UiTheme.cardBackground)
            .backgroundColor(UiTheme.primary)
            .borderRadius(UiTheme.buttonRadius)
            .enabled(!this.busy)
            .onClick((): void => {
              this.onConfirm();
            })
        }
        .width('100%')
      }
      .width('86%')
      .alignItems(HorizontalAlign.Start)
      .padding(UiTheme.gapXl)
      .backgroundColor(UiTheme.cardBackground)
      .borderRadius(UiTheme.alertRadius)
      .border({ width: 1, color: UiTheme.divider })
      .scale({ x: this.panelScale, y: this.panelScale })
      .translate({ y: this.panelOffsetY })
      .opacity(this.panelOpacity)
    }
    .width('100%')
    .height('100%')
  }
}
