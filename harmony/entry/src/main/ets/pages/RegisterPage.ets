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
import { AuthAlert } from '../components/AuthAlert';

/** 重放弹窗动画时"先卸载、再挂载"的间隔（ms）· 与登录页同一套做法 */
const ALERT_REPLAY_GAP_MS: number = 24;

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
      this.showAlert('无法提交', passwordError, '密码请输入 6 位以上，注意区分大小写');
      return;
    }
    const email: string = this.userEmail.trim();
    const emailError: string = this.checkEmail(email);
    if (emailError.length > 0) {
      this.formError = emailError;
      this.showAlert('无法提交', emailError, '邮箱可以不填，填了就要带 @');
      return;
    }
    this.formError = '';
    // 重新提交时允许服务端的错误再次显示
    this.dismissedError = '';
    this.submitting = true;
    // ★ 注册即登录：成功后窗口层会落地登录态，界面自动切换到主界面
    this.pageParam.onRegister(name, this.userPassword, email)
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

  /** 注册表单本体（品牌区 + 三个输入框 + 两个按钮） */
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
        AppCard({ title: '注册信息', subtitle: '用户名与密码为必填，邮箱可选' }) {
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

            TextInput({ placeholder: '密码（至少 6 位）', text: this.userPassword })
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

            TextInput({ placeholder: '邮箱（选填）', text: this.userEmail })
              .type(InputType.Email)
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
