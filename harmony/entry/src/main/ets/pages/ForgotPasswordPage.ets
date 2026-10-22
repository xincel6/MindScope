/**
 * ForgotPasswordPage · **找回密码页**（2026-10-21 新增）
 *
 * 与服务端两个接口对应：
 * ```text
 *   POST /api/auth/send-code       { email, purpose: "reset" }   → 发 6 位验证码
 *   POST /api/auth/reset-password  { email, verification_code, new_password }
 * ```
 *
 * ══════════════════ 页面契约 ══════════════════
 * ```ts
 * const param = new ForgotPasswordPageParam();
 * param.onSendCode = async (email, 'reset') => { ... };  // 窗口层调 AuthStore.sendCode
 * param.onReset = async (email, code, newPwd) => { ... }; // 窗口层调 AuthStore.resetPassword
 * param.onBackToLogin = () => { ... };                    // 窗口层出栈回登录页
 * ```
 * 两个回调都约定"空串 = 成功，非空 = 失败文案"：发码/重置是表单内的局部动作，
 * 失败不该把登录页那套"登录失败"弹窗拽出来（详见 `SendCodeAction` 注释）。
 *
 * ══════════════════ 已知限制 ══════════════════
 * 老账户（注册时未绑定邮箱）走不通这条路：服务端对未注册邮箱返回 202 但**不发信**，
 * 用户永远收不到验证码。页面底部用小字说明，避免用户反复重试。
 *
 * ══════════════════ 版式 ══════════════════
 * ```text
 * │  （ Logo ）                     │
 * │  找回密码                       │
 * │  通过注册邮箱重置密码            │
 * │ ╭───────────────────────────╮ │
 * │ │ 邮箱                        │ │
 * │ │ [ 注册时用的邮箱      ]      │ │
 * │ │ 验证码                      │ │
 * │ │ [ 6 位验证码  ][获取验证码] │ │
 * │ │ 新密码                      │ │
 * │ │ [ 至少6位，含大小写与字符 ]  │ │
 * │ │  （错误行 / 成功行）         │ │
 * │ │ [      重置密码      ]      │ │
 * │ │ [      返回登录      ]      │ │
 * │ ╰───────────────────────────╯ │
 * │  未绑定邮箱的老账号无法用此方式  │
 * ```
 */

import { AuthRule } from '../network/AuthApi';
import { UiTheme } from '../common/UiTheme';
import { ForgotPasswordPageParam } from '../types/PageParams';
import { AppCard } from '../components/AppCard';
import { LogoPlaceholder } from '../components/LogoPlaceholder';
import { AuthAlert } from '../components/AuthAlert';

/** 重放弹窗动画时"先卸载、再挂载"的间隔（ms）· 与登录/注册页同一套做法 */
const ALERT_REPLAY_GAP_MS: number = 24;

/** 发码成功后的倒计时秒数 · 与服务端 `RESEND_COOLDOWN_SECONDS` 保持一致 */
const RESEND_COOLDOWN_SECONDS: number = 60;

/** 验证码那一行里「获取验证码」按钮的定宽 */
const SEND_CODE_BUTTON_WIDTH: number = 104;

@ComponentV2
export struct ForgotPasswordPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: ForgotPasswordPageParam = new ForgotPasswordPageParam();

  // ── 表单本地状态 ──
  @Local userEmail: string = '';
  @Local userCode: string = '';
  @Local newPassword: string = '';
  @Local formError: string = '';
  @Local successMessage: string = '';
  @Local submitting: boolean = false;
  @Local sendingCode: boolean = false;
  @Local cooldown: number = 0;

  /** 倒计时的定时器句柄 · 离开页面必须清掉 */
  private cooldownTimer: number = -1;

  // ── 失败弹窗状态（与登录/注册页同一个组件）──
  @Local alertVisible: boolean = false;
  @Local alertTitle: string = '操作失败';
  @Local alertMessage: string = '';
  @Local alertHint: string = '';

  /** 任一来源的忙碌态 · 输入框与按钮共用 */
  @Computed
  get anyBusy(): boolean {
    return this.pageParam.busy || this.submitting || this.sendingCode;
  }

  @Computed
  get submitLabel(): string {
    return this.submitting ? '重置中…' : '重置密码';
  }

  /** 发码按钮三态文案 */
  @Computed
  get sendCodeLabel(): string {
    if (this.sendingCode) {
      return '发送中…';
    }
    if (this.cooldown > 0) {
      return `${this.cooldown}s`;
    }
    return '获取验证码';
  }

  @Computed
  get sendCodeEnabled(): boolean {
    return !this.anyBusy && this.cooldown === 0;
  }

  /** 是否已重置成功 · 成功后锁掉提交按钮，避免重复重置把刚拿到的码又消费一次 */
  @Computed
  get done(): boolean {
    return this.successMessage.length > 0;
  }

  aboutToAppear(): void {
    this.formError = '';
    this.successMessage = '';
  }

  aboutToDisappear(): void {
    this.stopCooldown();
  }

  /** 启动 60 秒倒计时 · 到 0 自动停表 */
  private startCooldown(): void {
    this.cooldown = RESEND_COOLDOWN_SECONDS;
    this.stopCooldown();
    this.cooldownTimer = setInterval((): void => {
      this.cooldown = this.cooldown - 1;
      if (this.cooldown <= 0) {
        this.cooldown = 0;
        this.stopCooldown();
      }
    }, 1000);
  }

  private stopCooldown(): void {
    if (this.cooldownTimer !== -1) {
      clearInterval(this.cooldownTimer);
      this.cooldownTimer = -1;
    }
  }

  /** 输入变化：清掉本地提示与成功横幅 */
  private onInputChanged(): void {
    if (this.formError.length > 0) {
      this.formError = '';
    }
    if (this.successMessage.length > 0) {
      this.successMessage = '';
    }
  }

  private showAlert(title: string, message: string, hint: string): void {
    this.alertTitle = title.length > 0 ? title : '操作失败';
    this.alertMessage = message;
    this.alertHint = hint;
    if (this.alertVisible) {
      this.alertVisible = false;
      setTimeout((): void => {
        this.alertVisible = true;
      }, ALERT_REPLAY_GAP_MS);
      return;
    }
    this.alertVisible = true;
  }

  /** 点「获取验证码」 */
  private sendCode(): void {
    if (!this.sendCodeEnabled) {
      return;
    }
    const email: string = this.userEmail.trim();
    const emailError: string = AuthRule.checkEmail(email);
    if (emailError.length > 0) {
      this.formError = emailError;
      this.showAlert('无法发送验证码', emailError, '请填写注册时使用的邮箱');
      return;
    }
    this.formError = '';
    this.sendingCode = true;
    this.pageParam.onSendCode(email, 'reset')
      .then((error: string): void => {
        this.sendingCode = false;
        if (error.length === 0) {
          this.startCooldown();
          return;
        }
        this.formError = error;
        this.showAlert('验证码发送失败', error, '请检查邮箱地址，或稍后再试');
      })
      .catch((): void => {
        this.sendingCode = false;
        this.formError = '验证码发送失败，请稍后再试';
        this.showAlert('验证码发送失败', '验证码发送失败，请稍后再试', '请检查网络与服务端状态');
      });
  }

  /** 点「重置密码」 */
  private submit(): void {
    if (this.anyBusy || this.done) {
      return;
    }
    const email: string = this.userEmail.trim();
    const emailError: string = AuthRule.checkEmail(email);
    if (emailError.length > 0) {
      this.formError = emailError;
      this.showAlert('无法提交', emailError, '请填写注册时使用的邮箱');
      return;
    }
    const codeError: string = AuthRule.checkCode(this.userCode);
    if (codeError.length > 0) {
      this.formError = codeError;
      this.showAlert('无法提交', codeError, '验证码已发到您的邮箱，6 位数字，5 分钟内有效');
      return;
    }
    const passwordError: string = AuthRule.checkPassword(this.newPassword);
    if (passwordError.length > 0) {
      this.formError = passwordError;
      this.showAlert('无法提交', passwordError, AuthRule.passwordHint);
      return;
    }
    this.formError = '';
    this.submitting = true;
    this.pageParam.onReset(email, this.userCode.trim(), this.newPassword)
      .then((error: string): void => {
        this.submitting = false;
        if (error.length === 0) {
          // 成功：显示横幅并锁掉表单，用户自己点「返回登录」
          this.successMessage = '密码已重置，请使用新密码登录';
          return;
        }
        this.formError = error;
        this.showAlert('重置失败', error, '请确认验证码输入正确，或重新获取');
      })
      .catch((): void => {
        this.submitting = false;
        this.formError = '重置失败，请稍后再试';
        this.showAlert('重置失败', '重置失败，请稍后再试', '请检查网络与服务端状态');
      });
  }

  /** 表单本体 */
  @Builder
  formSection() {
    Scroll() {
      Column({ space: UiTheme.gapXl }) {
        // ── ① 品牌区 ──
        Column({ space: UiTheme.gapXl }) {
          LogoPlaceholder({ _size: 72, radius: 16 })

          Column({ space: UiTheme.gapS }) {
            Text('找回密码')
              .fontSize(UiTheme.fontSizeTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(UiTheme.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Start)

            Text('通过注册邮箱验证身份后重置密码')
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // ── ② 表单 ──
        AppCard({ title: '重置密码', subtitle: '验证码 5 分钟内有效，仅可使用一次' }) {
          Column({ space: UiTheme.gapL }) {
            // 邮箱
            TextInput({ placeholder: '注册时使用的邮箱', text: this.userEmail })
              .type(InputType.Email)
              .maxLength(128)
              .height(UiTheme.controlHeight)
              .backgroundColor(UiTheme.fillSoft)
              .borderRadius(UiTheme.cardRadius)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .enabled(!this.anyBusy)
              .onChange((value: string) => {
                this.userEmail = value;
                this.onInputChanged();
              })

            // 验证码 + 发送按钮
            Column({ space: UiTheme.gapS }) {
              Text('验证码')
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(UiTheme.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Start)

              Row({ space: UiTheme.gapS }) {
                TextInput({ placeholder: '6 位数字验证码', text: this.userCode })
                  .type(InputType.Number)
                  .maxLength(6)
                  .height(UiTheme.controlHeight)
                  .layoutWeight(1)
                  .backgroundColor(UiTheme.fillSoft)
                  .borderRadius(UiTheme.cardRadius)
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.textPrimary)
                  .placeholderColor(UiTheme.textSecondary)
                  .enabled(!this.anyBusy)
                  .onChange((value: string) => {
                    this.userCode = value;
                    this.onInputChanged();
                  })

                Button(this.sendCodeLabel)
                  .width(SEND_CODE_BUTTON_WIDTH)
                  .height(UiTheme.controlHeight)
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(this.sendCodeEnabled ? UiTheme.onBrand : UiTheme.textSecondary)
                  .backgroundColor(this.sendCodeEnabled ? UiTheme.accent : UiTheme.fillSoft)
                  .borderRadius(UiTheme.buttonRadius)
                  .enabled(this.sendCodeEnabled)
                  .onClick(() => {
                    this.sendCode();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')

            // 新密码
            TextInput({ placeholder: '新密码（至少 6 位，含大小写字母与特殊字符）', text: this.newPassword })
              .type(InputType.Password)
              .maxLength(64)
              .height(UiTheme.controlHeight)
              .backgroundColor(UiTheme.fillSoft)
              .borderRadius(UiTheme.cardRadius)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .enabled(!this.anyBusy)
              .onChange((value: string) => {
                this.newPassword = value;
                this.onInputChanged();
              })

            // 成功横幅（绿色调：与错误行同一位置，语义相反）
            if (this.done) {
              Text(this.successMessage)
                .fontSize(UiTheme.fontSizeBody)
                .fontColor(UiTheme.primary)
                .width('100%')
                .textAlign(TextAlign.Start)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }

            // 错误行
            if (this.formError.length > 0) {
              Text(this.formError)
                .fontSize(UiTheme.fontSizeBody)
                .fontColor(UiTheme.danger)
                .width('100%')
                .textAlign(TextAlign.Start)
                .maxLines(4)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }

            Button(this.submitLabel)
              .width('100%')
              .height(UiTheme.controlHeight)
              .fontSize(UiTheme.fontSizeSection)
              .fontColor(UiTheme.cardBackground)
              .backgroundColor(UiTheme.primary)
              .borderRadius(UiTheme.buttonRadius)
              .enabled(!this.anyBusy && !this.done)
              .onClick(() => {
                this.submit();
              })

            Button('返回登录')
              .width('100%')
              .height(UiTheme.controlHeight)
              .fontSize(UiTheme.fontSizeSection)
              .fontColor(UiTheme.accent)
              .backgroundColor(Color.Transparent)
              .borderWidth(1)
              .borderColor(UiTheme.accent)
              .borderRadius(UiTheme.buttonRadius)
              .enabled(!this.anyBusy)
              .onClick(() => {
                this.pageParam.onBackToLogin();
              })
          }
          .width('100%')
        }

        // ── ③ 老账户提示 ──
        Text('若账号注册时未绑定邮箱，将无法通过此方式找回，请联系管理员处理。')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .padding(UiTheme.pagePadding)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.formSection()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(UiTheme.pageBackground)

      // 失败弹窗（与登录/注册页同一组件、同一套绝对定位做法）
      Column() {
        if (this.alertVisible) {
          AuthAlert({
            title: this.alertTitle,
            message: this.alertMessage,
            hint: this.alertHint,
            onClose: () => {
              this.alertVisible = false;
            }
          })
        }
      }
      .width('100%')
      .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.pageBackground)
  }
}
