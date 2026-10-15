/**
 * RegisterPage · **注册界面**（纯展示，与登录页相互独立）
 *
 * 页面契约（★ 直接传入参数即可展示本页）：
 * ```ts
 * const param = new RegisterPageParam();
 * param.onRegister = async (u, p, e) => { ... };  // 窗口层调 AuthStore.register（注册即登录）
 * param.onBackToLogin = () => { ... };            // 窗口层出栈回登录页
 * param.authBusy = AppStore.get().auth().loading;
 * param.authError = AppStore.get().auth().errorMsg;
 * param.presetUsername = '从登录页带过来的用户名';
 * ```
 *
 * 字段说明：用户名 / 密码 / 邮箱（**选填**，与服务端 `RegisterReq.email: Optional[str]` 一致）。
 * 邮箱为空时窗口层会发 `null`，不会写进库（这是服务端契约里明确要求的行为）。
 */

import { AuthRule } from '../network/AuthApi';
import { UiTheme } from '../common/UiTheme';
import { RegisterPageParam } from '../types/PageParams';
import { AppCard } from '../components/AppCard';
import { LogoPlaceholder } from '../components/LogoPlaceholder';

@ComponentV2
export struct RegisterPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: RegisterPageParam = new RegisterPageParam();

  // ── 表单本地状态 ──
  @Local userName: string = '';
  @Local userPassword: string = '';
  @Local userEmail: string = '';
  @Local formError: string = '';
  @Local submitting: boolean = false;

  /** 已被用户"收起"的服务端错误快照 · 与登录页同一套做法（页面不回写 store） */
  @Local dismissedError: string = '';

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

  aboutToAppear(): void {
    // 从登录页跳过来时预填，减少重复输入
    this.userName = this.pageParam.presetUsername;
    this.userPassword = this.pageParam.presetPassword;
    this.formError = '';
  }

  /** 邮箱校验 · 服务端只把 email 当普通字符串（无格式校验），所以这里只做最轻的防呆 */
  private checkEmail(email: string): string {
    if (email.length === 0) {
      return '';
    }
    if (email.indexOf('@') <= 0) {
      return '邮箱格式不正确，或留空不填';
    }
    return '';
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

  /** 点「注册并登录」 */
  private submit(): void {
    if (this.busy) {
      return;
    }
    const nameError: string = AuthRule.checkUsername(this.userName);
    if (nameError.length > 0) {
      this.formError = nameError;
      return;
    }
    const passwordError: string = AuthRule.checkPassword(this.userPassword);
    if (passwordError.length > 0) {
      this.formError = passwordError;
      return;
    }
    const emailError: string = this.checkEmail(this.userEmail.trim());
    if (emailError.length > 0) {
      this.formError = emailError;
      return;
    }
    this.formError = '';
    // 重新提交时允许服务端的错误再次显示
    this.dismissedError = '';
    this.submitting = true;
    // ★ 注册即登录：成功后窗口层会落地登录态，界面自动切换到主界面
    this.pageParam.onRegister(this.userName, this.userPassword, this.userEmail.trim())
      .then(() => {
        this.submitting = false;
      })
      .catch(() => {
        this.submitting = false;
      });
  }

  build() {
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
        AppCard({ title: '注册信息', subtitle: '用户名与密码为必填，邮箱可选' }) {
          Column({ space: UiTheme.gapL }) {
            TextInput({ placeholder: '用户名（3–32 位，支持中文/字母/数字/下划线）', text: this.userName })
              .type(InputType.Normal)
              .maxLength(AuthRule.usernameMaxLength)
              .height(UiTheme.controlHeight)
              .backgroundColor(UiTheme.pageBackground)
              .borderRadius(UiTheme.cardRadius)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .enabled(!this.busy)
              .onChange((value: string) => {
                this.userName = value;
                this.onInputChanged();
              })

            TextInput({ placeholder: '密码（至少 6 位）', text: this.userPassword })
              .type(InputType.Password)
              .height(UiTheme.controlHeight)
              .backgroundColor(UiTheme.pageBackground)
              .borderRadius(UiTheme.cardRadius)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .enabled(!this.busy)
              .onChange((value: string) => {
                this.userPassword = value;
                this.onInputChanged();
              })

            TextInput({ placeholder: '邮箱（选填）', text: this.userEmail })
              .type(InputType.Email)
              .height(UiTheme.controlHeight)
              .backgroundColor(UiTheme.pageBackground)
              .borderRadius(UiTheme.cardRadius)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .enabled(!this.busy)
              .onChange((value: string) => {
                this.userEmail = value;
                this.onInputChanged();
              })

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
    .backgroundColor(UiTheme.pageBackground)
  }
}
