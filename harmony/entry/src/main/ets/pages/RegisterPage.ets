/**
 * RegisterPage · **注册界面**（纯展示，与登录页相互独立）
 *
 * 页面契约（★ 直接传入参数即可展示本页）：
 * ```ts
 * const param = new RegisterPageParam();
 * param.onRegister = async (u, p, e, code) => { ... };  // 窗口层调 AuthStore.register（注册即登录）
 * param.onSendCode = async (email, 'register') => { ... }; // 窗口层调 AuthStore.sendCode
 * param.onBackToLogin = () => { ... };            // 窗口层出栈回登录页
 * param.authBusy = AppStore.get().auth().loading;
 * param.authError = AppStore.get().auth().errorMsg;
 * param.presetUsername = '从登录页带过来的用户名';
 * ```
 *
 * 字段说明（2026-10-21 起）：
 *   用户名 / 密码 / 邮箱 / 验证码 —— **四项全部必填**。
 *   邮箱是账号唯一的找回通道，验证码证明"这个邮箱真的是你的"；
 *   密码至少 6 位且同时包含大写字母、小写字母和特殊字符。
 *
 * ══════════════════ 验证码一栏的版式 ══════════════════
 * ```text
 * │ 验证码                              │
 * │ [ 6 位验证码        ][获取验证码]   │  ← 输入框自适应，按钮定宽 104
 * ```
 * 按钮三态：`获取验证码` → 点击后 `60s` 倒计时（与服务端冷却同长）→ 归零恢复。
 * 倒计时期间按钮禁用，避免用户连点触发 429。
 */

import { AuthRule } from '../network/AuthApi';
import { UiTheme } from '../common/UiTheme';
import { RegisterPageParam } from '../types/PageParams';
import { AppCard } from '../components/AppCard';
import { LogoPlaceholder } from '../components/LogoPlaceholder';
import { AuthAlert } from '../components/AuthAlert';

/** 重放弹窗动画时"先卸载、再挂载"的间隔（ms）· 与登录页同一套做法 */
const ALERT_REPLAY_GAP_MS: number = 24;

/** 发码成功后的倒计时秒数 · 与服务端 `RESEND_COOLDOWN_SECONDS` 保持一致 */
const RESEND_COOLDOWN_SECONDS: number = 60;

/** 验证码那一行里「获取验证码」按钮的定宽 · 5 个 12fp 汉字 + 内边距 */
const SEND_CODE_BUTTON_WIDTH: number = 104;

@ComponentV2
export struct RegisterPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: RegisterPageParam = new RegisterPageParam();

  // ── 表单本地状态 ──
  @Local userName: string = '';
  @Local userPassword: string = '';
  @Local userEmail: string = '';
  @Local userCode: string = '';
  @Local formError: string = '';
  @Local submitting: boolean = false;

  /** 发码按钮的忙碌态 · 只属于这个按钮，不占用 pageParam.authBusy（见 AuthStore.sendCode 注释） */
  @Local sendingCode: boolean = false;

  /** 发码冷却剩余秒数 · 0 表示可再发 */
  @Local cooldown: number = 0;

  /** 倒计时的定时器句柄 · 离开页面必须清掉，否则回调会打到已销毁的组件上 */
  private cooldownTimer: number = -1;

  /** 已被用户"收起"的服务端错误快照 · 与登录页同一套做法（页面不回写 store） */
  @Local dismissedError: string = '';

  // ── 失败弹窗状态（与登录页同一个组件，保证两页手感一致）──
  @Local alertVisible: boolean = false;
  @Local alertTitle: string = '注册失败';
  @Local alertMessage: string = '';
  @Local alertHint: string = '';

  @Computed
  get busy(): boolean {
    return this.pageParam.authBusy || this.submitting;
  }

  @Computed
  get visibleError(): string {
    if (this.formError.length > 0) {
      return this.formError;
    }
    const server: string = this.pageParam.authError;
    return server === this.dismissedError ? '' : server;
  }

  @Computed
  get submitLabel(): string {
    return this.busy ? '注册中…' : '注册并登录';
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

  /** 发码按钮是否可点 · 冷却中 / 正在发 / 表单忙碌 都禁掉 */
  @Computed
  get sendCodeEnabled(): boolean {
    return !this.sendingCode && this.cooldown === 0 && !this.busy;
  }

  aboutToAppear(): void {
    // 从登录页跳过来时预填，减少重复输入
    this.userName = this.pageParam.presetUsername;
    this.userPassword = this.pageParam.presetPassword;
    this.formError = '';
  }

  aboutToDisappear(): void {
    this.stopCooldown();
  }

  /** 启动 60 秒倒计时 · 到 0 自动停表（不需要再触发任何渲染以外的动作） */
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

  /** 输入变化：清掉本地校验提示，并收起上一次的服务端错误 */
  private onInputChanged(): void {
    if (this.formError.length > 0) {
      this.formError = '';
    }
    const server: string = this.pageParam.authError;
    if (server.length > 0) {
      this.dismissedError = server;
    }
  }

  /** 注册失败弹窗（与登录页同一个组件、同一套"重放"做法） */
  private showAlert(title: string, message: string, hint: string): void {
    this.alertTitle = title.length > 0 ? title : '注册失败';
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

  /** 把窗口层写在参数里的失败三元组弹出来 */
  private presentServerFailure(): void {
    const message: string = this.pageParam.authError;
    this.showAlert(
      this.pageParam.authErrorTitle,
      message.length > 0 ? message : '注册失败，请重试',
      this.pageParam.authErrorHint
    );
  }

  /** 点「获取验证码」· 邮箱先过本地校验，再交给窗口层发信 */
  private sendCode(): void {
    if (!this.sendCodeEnabled) {
      return;
    }
    const email: string = this.userEmail.trim();
    const emailError: string = AuthRule.checkEmail(email);
    if (emailError.length > 0) {
      this.formError = emailError;
      this.showAlert('无法发送验证码', emailError, '邮箱是必填项，找回密码也要靠它');
      return;
    }
    this.formError = '';
    this.sendingCode = true;
    this.pageParam.onSendCode(email, 'register')
      .then((error: string): void => {
        this.sendingCode = false;
        if (error.length === 0) {
          // 成功：起倒计时。服务端的 60 秒冷却与这里同长，倒计时归零时恰好可以重发
          this.startCooldown();
          return;
        }
        // 失败：就地展示（429 冷却 / 409 邮箱已注册 / 503 未配邮件服务…）
        this.formError = error;
        this.showAlert('验证码发送失败', error, '请检查邮箱地址，或稍后再试');
      })
      .catch((): void => {
        this.sendingCode = false;
        this.formError = '验证码发送失败，请稍后再试';
        this.showAlert('验证码发送失败', '验证码发送失败，请稍后再试', '请检查网络与服务端状态');
      });
  }

  /** 点「注册并登录」 */
  private submit(): void {
    if (this.busy) {
      return;
    }
    // ★ 与服务端 `username.strip()` 对齐：先去空白再校验/提交
    const name: string = this.userName.trim();
    const nameError: string = AuthRule.checkUsername(name);
    if (nameError.length > 0) {
      this.formError = nameError;
      this.showAlert('无法提交', nameError, '用户名 3–32 位，可用字母、数字、下划线或中文');
      return;
    }
    const passwordError: string = AuthRule.checkPassword(this.userPassword);
    if (passwordError.length > 0) {
      this.formError = passwordError;
      this.showAlert('无法提交', passwordError, AuthRule.passwordHint);
      return;
    }
    const email: string = this.userEmail.trim();
    const emailError: string = AuthRule.checkEmail(email);
    if (emailError.length > 0) {
      this.formError = emailError;
      this.showAlert('无法提交', emailError, '邮箱是必填项，找回密码也要靠它');
      return;
    }
    const codeError: string = AuthRule.checkCode(this.userCode);
    if (codeError.length > 0) {
      this.formError = codeError;
      this.showAlert('无法提交', codeError, '验证码已发到您的邮箱，6 位数字，5 分钟内有效');
      return;
    }
    this.formError = '';
    // 重新提交时允许服务端的错误再次显示
    this.dismissedError = '';
    this.submitting = true;
    // ★ 注册即登录：成功后窗口层会落地登录态，界面自动切换到主界面
    this.pageParam.onRegister(name, this.userPassword, email, this.userCode.trim())
      .then((ok: boolean): void => {
        this.submitting = false;
        if (ok) {
          return;
        }
        this.presentServerFailure();
      })
      .catch((): void => {
        this.submitting = false;
        this.presentServerFailure();
      });
  }

  /** 注册表单本体（品牌区 + 四个输入框 + 两个按钮） */
  @Builder
  formSection() {
    Scroll() {
      Column({ space: UiTheme.gapXl }) {
        // ── ① 品牌区（与登录页一致，保证两页视觉连续） ──
        Column({ space: UiTheme.gapXl }) {
          LogoPlaceholder({ _size: 72, radius: 16 })

          Column({ space: UiTheme.gapS }) {
            Text('创建账号')
              .fontSize(UiTheme.fontSizeTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(UiTheme.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Start)

            Text('注册成功后自动登录，可直接开始使用')
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

        // ── ② 注册表单 ──
        AppCard({ title: '注册信息', subtitle: '用户名、邮箱与验证码为必填，用于登录与找回密码' }) {
          Column({ space: UiTheme.gapL }) {
            // ★ 输入框底取 `fillSoft`（与登录页同一口径）：页底是浅灰，
            //   卡内填充块不能沿用页底色，否则会在白卡上显成灰补丁。
            TextInput({ placeholder: '用户名（3–32 位，支持中文/字母/数字/下划线）', text: this.userName })
              .type(InputType.Normal)
              .maxLength(AuthRule.usernameMaxLength)
              .height(UiTheme.controlHeight)
              .backgroundColor(UiTheme.fillSoft)
              .borderRadius(UiTheme.cardRadius)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .enabled(!this.busy)
              .onChange((value: string) => {
                this.userName = value;
                this.onInputChanged();
              })

            TextInput({ placeholder: '密码（至少 6 位，含大小写字母与特殊字符）', text: this.userPassword })
              .type(InputType.Password)
              .height(UiTheme.controlHeight)
              .backgroundColor(UiTheme.fillSoft)
              .borderRadius(UiTheme.cardRadius)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .enabled(!this.busy)
              .onChange((value: string) => {
                this.userPassword = value;
                this.onInputChanged();
              })

            TextInput({ placeholder: '邮箱（必填，用于找回密码）', text: this.userEmail })
              .type(InputType.Email)
              .maxLength(128)
              .height(UiTheme.controlHeight)
              .backgroundColor(UiTheme.fillSoft)
              .borderRadius(UiTheme.cardRadius)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .enabled(!this.busy)
              .onChange((value: string) => {
                this.userEmail = value;
                this.onInputChanged();
              })

            // ── 验证码：输入框 + 定宽发送按钮 ──
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
                  .enabled(!this.busy)
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

            if (this.visibleError.length > 0) {
              Text(this.visibleError)
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
              .enabled(!this.busy)
              .onClick(() => {
                this.submit();
              })

            Button('已有账号？返回登录')
              .width('100%')
              .height(UiTheme.controlHeight)
              .fontSize(UiTheme.fontSizeSection)
              .fontColor(UiTheme.accent)
              .backgroundColor(Color.Transparent)
              .borderWidth(1)
              .borderColor(UiTheme.accent)
              .borderRadius(UiTheme.buttonRadius)
              .enabled(!this.busy)
              .onClick(() => {
                this.pageParam.onBackToLogin();
              })
          }
          .width('100%')
        }
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
      // ── 页面本体 ──
      Column() {
        this.formSection()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(UiTheme.pageBackground)

      // ── 失败弹窗（覆盖在最上层，不占布局；与登录页同一组件） ──
      //
      // ★ 套一层 `.position({x:0,y:0})`：直接当 Stack 子节点时它一出现会把页面
      //   本体整体下推（登录页实测被推 104vp），绝对定位之后才真正"不占布局"。
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
