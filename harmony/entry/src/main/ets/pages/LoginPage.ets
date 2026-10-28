/**
 * LoginPage · **登录界面**（纯展示，不含任何业务逻辑）
 *
 * 页面契约（★ 直接传入参数即可展示本页，页面内部不引用任何 store）：
 * ```ts
 * const param = new LoginPageParam();
 * param.onLogin = async (u, p, e) => { ... };   // 窗口层去调 AuthStore
 * param.onRegister = (u, p, e) => { ... };      // 点"立即注册"由窗口层决定怎么跳
 * param.authBusy = AppStore.get().auth().loading;
 * param.authError = AppStore.get().auth().errorMsg;
 * param.authErrorTitle / authErrorHint          // 失败弹窗的标题与诊断行
 * param.serverLabel = 'xincell1013.xyz:443';     // 底部常驻的服务端地址
 * ```
 *
 * ══════════════════ 本轮（待机页转场 · 登录页重构）的版式 ══════════════════
 * ```
 * ┌──────────────────────────────┐
 * │        （青绿渐变满屏）        │  ← BrandBackdrop
 * │                              │
 * │        （白色标记 +          │  ← BrandHero：布局盒**和待机页完全一致**
 * │     MindScope / 产品名）      │     图标只在原地由 0.76 放大到 1（`heroLogoStart`）
 * │                              │
 * │ ╭──────────────────────────╮ │  ← 白色表单层：从屏幕下方盖上来的"抽屉"
 * │ │ 登录                      │ │     顶边 = `loginSheetTop`，圆角 28
 * │ │ 使用已注册的账号继续        │ │
 * │ │ [用户名]                  │ │
 * │ │ [密码]                    │ │
 * │ │ [      登录      ]        │ │
 * │ │  还没有账号？立即注册       │ │
 * │ │  忘记密码？                │ │
 * │ │ 服务端 https://xincell1013.xyz │ │
 * │ ╰──────────────────────────╯ │
 * └──────────────────────────────┘
 * ```
 *
 * 这样转场只需要两个动作：图标原地放大 + 白层从下方上滑。
 * 没有整页缩放、没有交叉淡入，所以不会出现两套版式互相穿透的画面。
 *
 * ══════════════════ 交互上保留并加强了什么 ══════════════════
 * ① **失败一定有"动作"**：任何一次失败（本地校验不过也算）都弹 `AuthAlert`，
 *    连续失败会卸载再挂载重放动画，不会因为"文案没变"就毫无反馈；
 * ② **两类失败分开说**：弹窗第三行明确写"服务端已回应 HTTP 401"（账号密码问题）
 *    还是"请求没有到达服务端"（网络/地址问题）；
 * ③ 用户名先去空白再校验（服务端是 strip 后精确匹配，两端口径一致）；
 * ④ 密码框恒为密文，键盘上直接按"前往"就能提交（`onSubmit`）；
 * ⑤ 输入框上方有标签，不再只靠 placeholder —— 填到一半时 placeholder 消失，
 *    用户会忘记这一栏是用户名还是邮箱。
 *
 * ★ 2026-10-21：按用户要求**移除**了密码框右侧的「显示/隐藏」切换
 *   （原先留着它是为了"401 时方便自查密码"）。密码找回改走邮箱验证码
 *   （见 `ForgotPasswordPage`），登录页只留"忘记密码？"一个出口。
 */

import { AuthRule } from '../network/AuthApi';
import { curves } from '@kit.ArkUI';
import { UiTheme } from '../common/UiTheme';
import { LoginPageParam } from '../types/PageParams';
import { BrandBackdrop } from '../components/BrandBackdrop';
import { BrandHero } from '../components/BrandHero';
import { ErrorRetryView } from '../components/ErrorRetryView';
import { AuthAlert } from '../components/AuthAlert';

/** 重放弹窗动画时"先卸载、再挂载"的间隔（ms）· 太短会被合批成同一次渲染 */
const ALERT_REPLAY_GAP_MS: number = 24;

/**
 * 白层起跑延迟（毫秒）
 *
 * ★ 待机页刚把图标放大完、停 60ms 才切页，本页第一帧就是"图标已到位"的画面。
 *   白层再等 40ms 起跑，观众能先看清那一下"停住"，然后表单才盖上来。
 * ★ 不能等太久：超过 100ms 就会被读成"卡了一下"，而不是"故意的停顿"。
 */
const SHEET_START_DELAY_MS: number = 40;

/**
 * "整页上提"相对白层起跑的延迟（毫秒）
 *
 * ★ 白层上滑 460ms、上提 420ms，重叠 200ms：先看白层盖上来，盖到一半时整页
 *   开始往上提，两个动作在结尾几乎同时收住，像一次连贯的落位。
 */
const LIFT_START_DELAY_MS: number = 200;

@ComponentV2
export struct LoginPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: LoginPageParam = new LoginPageParam();

  // ── 表单本地状态 ──
  @Local userName: string = '';
  @Local userPassword: string = '';
  @Local formError: string = '';
  /** 回调返回前的兜底忙碌态（参数里的 authBusy 是权威来源） */
  @Local submitting: boolean = false;

  /**
   * 已被用户"收起"的服务端错误快照
   *
   * 场景：服务端返回"用户名或密码错误"后，用户开始改密码，这条报错就该消失
   * （否则看起来像"我的修改没生效"）。做法是页面记下这条已展示过的文案，
   * 而不是回头去清 `AuthStore.errorMsg` —— 页面不回写 store，是本工程的纪律。
   */
  @Local dismissedError: string = '';

  // ── 失败弹窗状态（三行文案 + 是否显示）──
  @Local alertVisible: boolean = false;
  @Local alertTitle: string = '登录失败';
  @Local alertMessage: string = '';
  @Local alertHint: string = '';

  // ── 转场状态 ──

  /**
   * 图标缩放 · 恒为 1
   *
   * ★ 保留这个字段是因为布局盒要以"登录页那一档"为准：待机页只画
   *   `heroLogoStart`(0.84) 那一档，切页前**已经在待机页上**放大到 1（见
   *   `Index.growStandbyLogoThenEnter`）。所以登录页接手时图标是最终尺寸，
   *   这里不再有放大动画 —— 转场只剩"白层盖上来"这一拍。
   */
  @Local logoScale: number = 1;

  /** 白层的位移 · 入场时从 +屏幕高度 滑到 0 */
  @Local sheetOffset: number = 520;

  /**
   * 品牌区当前顶边 · 入场末尾从 `heroTop`(156) 上提到 `heroTopLifted`(96)
   * ★ 必须和待机页共用起点（否则切页瞬间图标跳一下），终点才上提。
   */
  @Local heroTopNow: number = UiTheme.heroTop;

  /**
   * 白层当前顶边 · 入场末尾从 `loginSheetTop`(372) 上提到 `loginSheetTopLifted`(312)
   * ★ 改的是布局高度（占位 `Row`），不是 translate —— translate 会把底边一起抬起。
   */
  @Local sheetTopNow: number = UiTheme.loginSheetTop;

  /** 白层内容的淡入值 */
  @Local sheetOpacity: number = 0;

  /** 任一来源的忙碌态 */
  @Computed
  get busy(): boolean {
    return this.pageParam.authBusy || this.submitting;
  }

  /** 展示给用户的错误：本地校验提示优先；已被收起的服务端错误不再显示 */
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

  /** 底部服务端地址行 · 空串则不显示（避免出现"服务端 "这种半截文案） */
  @Computed
  get serverLine(): string {
    const label: string = this.pageParam.serverLabel;
    return label.length > 0 ? `服务端 ${label}` : '';
  }

  // ── 生命周期 ──

  aboutToAppear(): void {
    this.formError = '';
    this.playEnter();
    // ★ 冷启动可能带着一条现成的提示（如"登录已过期，请重新登录"）：
    //   它是"用户必须知道"的信息，所以进页面就用同一种弹窗表达一次。
    const preset: string = this.pageParam.authError;
    if (preset.length > 0) {
      this.showAlert(this.pageParam.authErrorTitle, preset, this.pageParam.authErrorHint);
    }
  }

  /**
   * 入场：白层从下方滑上来 → 接着**整页往上提**（用户指定的收尾动作）
   *
   * ★ "图标慢慢放大"这一拍**不在这里**：它发生在待机页上
   *   （`Index.growStandbyLogoThenEnter`）。顺序是：待机页把图标从 0.84 放到 1
   *   → 停 60ms → 切到本页 → 白层上滑 → 整页上提。
   * ★ 最后一拍是用户的明确要求：「动画的最后让白屏向上拉动，让图标上移」：
   *   品牌区顶边 156→96、白层顶边 372→312，**同一位移**，所以两者间距不变，
   *   观感是"整块版式被往上提了一格"，而表单区白白多出 60vp。
   * ★ 上提与上滑重叠 200ms 起跑：完全串行会显得拖沓（总时长已经 1.4s 了）。
   */
  private playEnter(): void {
    setTimeout((): void => {
      this.getUIContext().animateTo({
        duration: UiTheme.sheetEnterMs,
        curve: curves.springMotion(0.46, 0.72)
      }, (): void => {
        this.sheetOffset = 0;
      });
    }, SHEET_START_DELAY_MS);

    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, (): void => {
        this.sheetOpacity = 1;
      });
    }, SHEET_START_DELAY_MS + 120);

    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: UiTheme.sheetLiftMs, curve: Curve.EaseOut }, (): void => {
        this.heroTopNow = UiTheme.heroTopLifted;
        this.sheetTopNow = UiTheme.loginSheetTopLifted;
      });
    }, SHEET_START_DELAY_MS + LIFT_START_DELAY_MS);
  }

  // ── 失败弹窗 ──

  /**
   * 弹一次失败弹窗
   *
   * ★ 已经显示着的时候不能只改文案：动画已经播完了，用户会觉得"这次没反应"。
   *   做法是先卸载、隔一帧再挂载 —— 组件重新 `aboutToAppear` 就一定重放动画。
   */
  private showAlert(title: string, message: string, hint: string): void {
    this.alertTitle = title.length > 0 ? title : '登录失败';
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
      message.length > 0 ? message : '登录失败，请重试',
      this.pageParam.authErrorHint
    );
  }

  // ── 交互 ──

  /** 点「登录」：先本地校验，再把用户输入交给窗口层 */
  private submit(): void {
    if (this.busy) {
      return;
    }
    // ★ 手机输入法容易带尾随空格：服务端是 strip 后精确匹配，端上先去空白
    const name: string = this.userName.trim();
    const nameError: string = AuthRule.checkUsername(name);
    if (nameError.length > 0) {
      this.formError = nameError;
      this.showAlert('无法提交', nameError, '用户名 3–32 位，可用字母、数字、下划线或中文');
      return;
    }
    // ★ 登录只查长度，不查强度：老账户的弱密码必须还能登录（与后端同一条口径）
    const passwordError: string = AuthRule.checkLoginPassword(this.userPassword);
    if (passwordError.length > 0) {
      this.formError = passwordError;
      this.showAlert('无法提交', passwordError, '密码至少 6 位，注意区分大小写');
      return;
    }
    this.formError = '';
    // 重新提交时允许服务端的错误再次显示
    this.dismissedError = '';
    this.submitting = true;
    this.pageParam.onLogin(name, this.userPassword, '')
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

  /** 点「立即注册」：登录页与注册页相互独立，跳转交给窗口层 */
  private goRegister(): void {
    if (this.busy) {
      return;
    }
    this.formError = '';
    this.pageParam.onRegister(this.userName.trim(), this.userPassword, '');
  }

  // ── 界面 ──

  /** 表单里的一个"标签 + 输入框"竖排 */
  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(UiTheme.fontSizeCaption)
      .fontColor(UiTheme.textSecondary)
      .width('100%')
      .textAlign(TextAlign.Start)
  }

  /** 白色表单层的内容（标题 + 输入 + 按钮） */
  @Builder
  sheetBody() {
    Scroll() {
      // ★ 行距用 gapM(12) 而不是 gapL(16)：这台机器上白层只有约 480vp 高，
      //   两个输入框 + 错误行 + 按钮已经填满，用 16 会把登录按钮压到可视区边缘。
      Column({ space: UiTheme.gapM }) {
        // ① 标题
        Column({ space: UiTheme.gapXs }) {
          Text('登录')
            .fontSize(UiTheme.loginTitleSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(UiTheme.textPrimary)
            .width('100%')
            .textAlign(TextAlign.Start)

          Text('使用已注册的账号继续')
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // ② 用户名
        this.fieldLabel('用户名')
        TextInput({ placeholder: '手机号 / 邮箱 / 用户名', text: this.userName })
          .type(InputType.Normal)
          .maxLength(AuthRule.usernameMaxLength)
          .height(UiTheme.controlHeight)
          .backgroundColor(UiTheme.fillSoft)
          .borderRadius(UiTheme.buttonRadius)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textPrimary)
          .placeholderColor(UiTheme.textSecondary)
          .enabled(!this.busy)
          .onChange((value: string) => {
            this.userName = value;
            this.onInputChanged();
          })

        // ③ 密码（恒为密文 · 2026-10-21 移除「显示/隐藏」切换；键盘"前往"直接提交）
        this.fieldLabel('密码')
        TextInput({ placeholder: '请输入密码', text: this.userPassword })
          .type(InputType.Password)
          .height(UiTheme.controlHeight)
          .backgroundColor(UiTheme.fillSoft)
          .borderRadius(UiTheme.buttonRadius)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textPrimary)
          .placeholderColor(UiTheme.textSecondary)
          .enterKeyType(EnterKeyType.Go)
          .enabled(!this.busy)
          .onChange((value: string) => {
            this.userPassword = value;
            this.onInputChanged();
          })
          .onSubmit(() => {
            this.submit();
          })

        // ④ 错误提示（弹窗会消失，这一行保证信息不丢）
        if (this.visibleError.length > 0) {
          Text(this.visibleError)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.danger)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        // ⑤ 登录（主按钮）
        Button(this.submitLabel)
          .width('100%')
          .height(UiTheme.controlHeight)
          .fontSize(UiTheme.fontSizeSection)
          .fontColor(UiTheme.onBrand)
          .backgroundColor(UiTheme.primary)
          .borderRadius(UiTheme.buttonRadius)
          .enabled(!this.busy)
          .margin({ top: UiTheme.gapXs })
          .onClick(() => {
            this.submit();
          })

        // ★ 「还没有账号？立即注册」搬到了 `sheetFooter`：它留在 Scroll 里时，
        //   一旦出现行内错误行（"密码至少 6 位"），表单变高就会把它顶出可视区
        //   （实测被裁掉一半）。放到底部常驻区，任何时候都能点到。
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: UiTheme.pagePadding,
        right: UiTheme.pagePadding,
        top: UiTheme.gapM,
        bottom: UiTheme.gapL
      })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .opacity(this.sheetOpacity)
  }

  /** 白层底部：注册入口 + 找回密码入口 + 连接失败的重试出口 + 当前服务端地址 */
  @Builder
  sheetFooter() {
    Column({ space: UiTheme.gapS }) {
      // 注册入口常驻在这里（不放进 Scroll）：行内错误行一出现，表单就会变高，
      // 留在 Scroll 里的入口会被顶出可视区 —— 这是真机上踩到的。
      Row({ space: UiTheme.gapXs }) {
        Text('还没有账号？')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)

        Text('立即注册')
          .fontSize(UiTheme.fontSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.primary)
          .onClick(() => {
            this.goRegister();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // ★ 忘记密码入口（2026-10-21 新增）：找回走邮箱验证码，见 ForgotPasswordPage。
      //   未绑定邮箱的老账户走不通，所以放在注册入口下面，不占主视觉。
      Text('忘记密码？')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .onClick(() => {
          if (this.busy) {
            return;
          }
          this.pageParam.onForgotPassword();
        })

      // 连接失败时的重试出口（规范：网络失败时提供重试按钮）
      if (this.pageParam.retryMessage.length > 0) {
        ErrorRetryView({
          message: this.pageParam.retryMessage,
          retryLabel: '重新连接服务端',
          retrying: this.pageParam.retrying,
          onRetry: () => {
            this.pageParam.onRetry();
          }
        })
      }

      // ★ 常驻的小字：账号在哪台服务器上一目了然（排查 401 的第一现场信息）
      if (this.serverLine.length > 0) {
        Text(this.serverLine)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding({
      left: UiTheme.pagePadding,
      right: UiTheme.pagePadding,
      bottom: UiTheme.gapL
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ① 品牌底色（铺满，含状态栏）
      BrandBackdrop()

      // ② 品牌区：起点与待机页**完全一致**（同一个布局盒 + 同一个 heroTop），
      //   入场末尾由 `heroTopNow` 上提到 heroTopLifted（"图标上移"那一拍）
      Column() {
        BrandHero({
          logoWidth: UiTheme.heroLogoWidth,
          logoScale: this.logoScale,
          textOpacity: 1
        })
      }
      .width('100%')
      .margin({ top: this.heroTopNow })

      // ③ 白层：从 loginSheetTop 铺到底，入场时从下方滑上来
      Column() {
        // 品牌区占位（白层不能盖住图标，占位高度就是图标的落脚点）
        // ★ 高度跟着 `sheetTopNow` 走：入场末尾它变小 60vp，白层顶边就"拉上来"了，
        //   而底边始终贴着屏幕底，所以表单区实打实多出 60vp。
        Row()
          .width('100%')
          .height(this.sheetTopNow)

        Column() {
          this.sheetBody()
          this.sheetFooter()
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(UiTheme.cardBackground)
        .borderRadius({ topLeft: UiTheme.loginSheetRadius, topRight: UiTheme.loginSheetRadius })
        // ★ 必须裁切：圆角只作用在自身背景上，内部 Scroll 的内容仍会画成直角
        .clip(true)
        // 白层要盖到导航栏底下，否则导航栏那一条会露出青绿
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .translate({ y: this.sheetOffset })

      // ④ 失败的弹性警告弹窗（覆盖在最上层，不占布局）
      //
      // ★ 外面必须再套一层 `.position({x:0,y:0})`：实测直接把它当 Stack 的子节点时，
      //   它一出现会把**同层兄弟（品牌区、白层）整体往下推**约 104vp，底部的
      //   "还没有账号？立即注册" 直接被挤出屏幕。`.position` 是绝对定位语义，
      //   挂上去之后它就完全不参与父级排版，弹窗出现/收起都不再推动下面任何东西。
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
    // 兜底底色：万一渐变还没铺上（首帧），也不能闪一下浅灰
    .backgroundColor(UiTheme.brandEnd)
  }
}
