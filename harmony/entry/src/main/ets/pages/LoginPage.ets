/**
 * LoginPage · **登录界面**（纯展示，不含任何业务逻辑）
 *
 * 页面契约（★ 直接传入参数即可展示本页，页面内部不引用任何 store / 变量）：
 * ```ts
 * const param = new LoginPageParam();
 * param.onLogin = async (u, p, e) => { ... };   // 交给窗口层去调 AuthStore
 * param.onRegister = (u, p, e) => { ... };      // 点"注册账号"由窗口层决定怎么跳
 * param.authBusy = AppStore.get().auth().loading;
 * param.authError = AppStore.get().auth().errorMsg;
 * ```
 *
 * 页面自己只持有三类状态（都属于"表单本地状态"，不是业务数据）：
 *   - 输入框内容：用户名 / 密码 / 是否明文显示密码
 *   - 本地校验提示：`formError`（用 `AuthRule` 先拦一次，省掉一次必然失败的往返）
 *   - 演示用的"登录中…"兜底态：在回调返回之前防止连点
 * 鉴权结果、错误文案全部来自参数，页面不解析、不判断错误类型。
 */

import { AuthRule } from '../network/AuthApi';
import { UiTheme } from '../common/UiTheme';
import { LoginPageParam } from '../types/PageParams';
import { AppCard } from '../components/AppCard';
import { LogoPlaceholder } from '../components/LogoPlaceholder';
import { ErrorRetryView } from '../components/ErrorRetryView';

@ComponentV2
export struct LoginPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: LoginPageParam = new LoginPageParam();

  // ── 表单本地状态 ──
  @Local userName: string = '';
  @Local userPassword: string = '';
  @Local passwordVisible: boolean = false;
  @Local formError: string = '';
  /** 回调返回前的兜底忙碌态（参数里的 authBusy 是权威来源） */
  @Local submitting: boolean = false;

  /**
   * 已被用户"收起"的服务端错误快照
   *
   * 场景：服务端返回"用户名或密码错误"后，用户开始改密码，这条报错就该消失
   * （否则看起来像"我的修改没生效"）。做法是**页面本地记下这条已展示过的文案**，
   * 而不是回头去清 `AuthStore.errorMsg` —— 页面不回写 store，是本工程的纪律。
   * 如果下次又拿到不同的错误文案，它不等于快照，会重新显示出来。
   */
  @Local dismissedError: string = '';

  /** 任一来源的忙碌态 */
  @Computed
  get busy(): boolean {
    return this.pageParam.authBusy || this.submitting;
  }

  /** 展示给用户的错误：本地校验提示优先于服务端返回的错误；已被收起的服务端错误不再显示 */
  @Computed
  get visibleError(): string {
    if (this.formError.length > 0) {
      return this.formError;
    }
    const server: string = this.pageParam.authError;
    return server === this.dismissedError ? '' : server;
  }

  /** 登录按钮文案 */
  @Computed
  get submitLabel(): string {
    return this.busy ? '登录中…' : '登录';
  }

  /** 注册入口文案 */
  @Computed
  get registerLabel(): string {
    return this.busy ? '注册中…' : '注册账号';
  }

  // ── 生命周期：把"用户开始重新输入"当作清掉上一次错误的时机 ──

  aboutToAppear(): void {
    this.formError = '';
  }

  /** 点「登录」：先本地校验，再把手输入交给窗口层 */
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
    this.formError = '';
    // 重新提交时允许服务端的错误再次显示
    this.dismissedError = '';
    this.submitting = true;
    this.pageParam.onLogin(this.userName, this.userPassword, '')
      .then(() => {
        this.submitting = false;
      })
      .catch(() => {
        this.submitting = false;
      });
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

  /** 点「注册账号」：登录页与注册页相互独立，跳转交给窗口层 */
  private goRegister(): void {
    if (this.busy) {
      return;
    }
    this.formError = '';
    this.pageParam.onRegister(this.userName, this.userPassword, '');
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: UiTheme.gapXl }) {
          // ── ① 品牌区：图标占位 + 产品名 + 场景说明 ──
          Column({ space: UiTheme.gapXl }) {
            LogoPlaceholder()

            Column({ space: UiTheme.gapS }) {
              Text('抑郁症智能辅助评估')
                .fontSize(UiTheme.fontSizeTitle)
                .fontWeight(FontWeight.Bold)
                .fontColor(UiTheme.textPrimary)
                .width('100%')
                .textAlign(TextAlign.Start)

              Text('面向临床与研究场景')
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

          // ── ② 表单卡片：两个输入框 + 登录 + 注册 ──
          AppCard({ title: '账号登录', subtitle: '请使用已注册的账号登录系统' }) {
            Column({ space: UiTheme.gapL }) {
              // 用户名
              TextInput({ placeholder: '请输入用户名', text: this.userName })
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

              // 密码（默认密文，右侧可切换明文）
              Row({ space: UiTheme.gapS }) {
                TextInput({ placeholder: '请输入密码', text: this.userPassword })
                  .type(this.passwordVisible ? InputType.Normal : InputType.Password)
                  .height(UiTheme.controlHeight)
                  .layoutWeight(1)
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

                Text(this.passwordVisible ? '隐藏' : '显示')
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.accent)
                  .width(44)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.passwordVisible = !this.passwordVisible;
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              // 错误提示
              if (this.visibleError.length > 0) {
                Text(this.visibleError)
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.danger)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .maxLines(4)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }

              // 登录（主按钮）
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

              // 注册（次按钮 · 跳转独立注册页）
              Button(this.registerLabel)
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
                  this.goRegister();
                })
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding({
          left: UiTheme.pagePadding,
          right: UiTheme.pagePadding,
          top: UiTheme.pagePadding,
          bottom: UiTheme.gapXl
        })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // ── ③ 连接失败时的重试出口（规范：网络失败时提供重试按钮） ──
      if (this.pageParam.retryMessage.length > 0) {
        ErrorRetryView({
          message: this.pageParam.retryMessage,
          retryLabel: '重新连接服务端',
          retrying: this.pageParam.retrying,
          onRetry: () => {
            this.pageParam.onRetry();
          }
        })
          .padding({
            left: UiTheme.pagePadding,
            right: UiTheme.pagePadding,
            bottom: UiTheme.gapL
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.pageBackground)
    .alignItems(HorizontalAlign.Start)
  }
}
