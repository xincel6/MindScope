/**
 * Index · **Ability 入口页 / 应用外壳**（`main_pages.json` 里注册的唯一 @Entry 页面）
 *
 * 它只做"阶段分支"，不画任何业务界面：
 * ```
 *                            ┌ 开屏页（SplashView，覆盖在最上层，引导完成后淡出）
 * Index（本文件，@ComponentV2）┼ bootPhase = idle / preparing        → 骨架屏（开屏页背后）
 *                            ├ signedIn  = false                   → 登录流（独立 Navigation）
 *                            └ signedIn  = true                    → 主界面（独立 Navigation）
 * ```
 *
 * ★ 本文件是**唯一**允许触碰 store、网络与路由栈的 UI 文件（"窗口层"）：
 *   两个分支里的页面组件全部只接受参数（见 `types/PageParams.ets` 的三条纪律）。
 *
 * ★ 登录态切换靠数据驱动：`AuthStore.login/register` 成功后会把 `AuthStore.signedIn`
 *   置为 true，`AppStore.sync()` 把它镜像到门面，本页的 `@Computed signedIn` 随之失效重算，
 *   界面自动从登录流切到主界面 —— **不需要任何显式跳转指令**。
 *   同理，登出（本轮新增：「我的」页的退出按钮）会让界面自动回到登录流。
 *
 * ★ ArkTS 响应式要点：`@Computed` 必须真正读到 `@Trace` 字段才会建立依赖；
 *   而 `AppStore.get()` 是普通静态方法调用，所以这里额外读一个 `tick` 计数器，
 *   在每次 `await` 之后 +1，保证界面一定会重新取数（工程既有页面同样是这个写法）。
 */

import { AppBootstrap } from '../common/AppBootstrap';
import { UiTheme } from '../common/UiTheme';
import { AppStore } from '../store/AppStore';
import { ActionResultModel, AuthFailKind, BootPhase } from '../types/Index';
import { LoginPageParam, MainPageParam, RegisterPageParam } from '../types/PageParams';
import { AuthSkeleton } from '../components/SkeletonView';
import { SplashView } from '../components/SplashView';
import { LOGIN_ROUTE, REGISTER_ROUTE } from './PageRoutes';
import { LoginPage } from './LoginPage';
import { RegisterPage } from './RegisterPage';
import { MainPage } from './MainPage';

/**
 * 开屏页的**硬上限**（毫秒）
 * ★ 为什么需要：开屏页的收起原本只等 `AppBootstrap.ready`，
 *   一旦引导因为异常卡住（例如 preferences 打开失败后没有收敛），
 *   用户会永远停在开屏页。这里给一个兜底时长，到点就露出下面的骨架屏。
 */
const SPLASH_MAX_MS: number = 5000;

@Entry
@ComponentV2
struct Index {
  /** 刷新触发器 · 每次 await 之后 +1，保证 `@Computed` 重新取数 */
  @Local tick: number = 0;

  /** 登录流自己的路由栈（与主界面的栈相互独立） */
  @Local loginStack: NavPathStack = new NavPathStack();

  /** 登录流是否已初始化（防止重建时重复入栈） */
  private loginStackReady: boolean = false;

  /**
   * 登录页参数 · **只构造一次**，之后只更新字段
   *
   * ★ 为什么不让 `build()` 每次 `new` 一个：`@Param` 是按**对象引用**比对的，
   *   每次传新对象都会把登录页的入参整体重置一遍（`aboutToAppear` 还会被重跑）、
   *   并触发整棵子树的冗余重建。改成"构造一次 + 按需改写字段"后，
   *   页面的入参引用稳定，界面只按字段值变化更新。
   */
  private loginParam: LoginPageParam = new LoginPageParam();

  /** 注册页参数 · 同上，页面级缓存 */
  private registerParam: RegisterPageParam = new RegisterPageParam();

  /** 主界面参数 · 同上。主界面的入参里只有只读展示文案，定期同步即可 */
  private mainParam: MainPageParam = new MainPageParam();

  /** 登录页的回调是否已挂载（回调只挂一次，避免每次重建都新建闭包） */
  private loginActionsAttached: boolean = false;

  /** 注册页的回调是否已挂载 */
  private registerActionsAttached: boolean = false;

  /** 探活重连是否进行中 */
  @Local retrying: boolean = false;

  /**
   * 开屏页是否还在显示
   * ★ 它是**覆盖层**，不是阶段分支：开屏期间下面的骨架屏/登录流照常构建，
   *   收起时只播一个淡出，不会引起下层重新布局。
   */
  @Local splashVisible: boolean = true;

  /** 应用启动时刻（毫秒）· 用来算"开屏页还差多少才到最短展示时长" */
  private launchAt: number = 0;

  /** 主界面的动作回调是否已挂载（登出回调只挂一次） */
  private mainActionsAttached: boolean = false;

  // ══════════════════ 数据 → 界面 ══════════════════

  @Computed
  get app(): AppStore {
    this.tick;
    return AppStore.get();
  }

  /**
   * 界面阶段 · 空串表示"引导中，显示骨架屏"
   * 读 `bootPhase` 与 `signedIn` 两个 `@Trace` 字段，任一变化都会让界面重算。
   */
  @Computed
  get phase(): string {
    const phase: BootPhase = this.app.bootPhase;
    if (phase === BootPhase.idle || phase === BootPhase.preparing) {
      return '';
    }
    return this.app.signedIn ? 'main' : 'auth';
  }

  /**
   * 登录页要展示的错误文案 · **只在引导真正结束后**才取 AuthStore 的 errorMsg，
   * 否则会把引导过程中的中间态误当成错误弹出来。
   * 已登录时返回空串（主界面不该看到登录错误）。
   */
  @Computed
  get authError(): string {
    if (this.phase !== 'auth') {
      return '';
    }
    const auth = this.app.auth();
    const message: string = auth.errorMsg;
    if (message.length > 0) {
      return message;
    }
    // 401 全局提示（如"登录已过期，请重新登录"）同样归到登录页展示
    return this.app.globalMessage;
  }

  /** 鉴权请求是否进行中 */
  @Computed
  get authBusy(): boolean {
    return this.app.auth().loading;
  }

  /**
   * 非空时在登录页底部显示"重新连接服务端"（规范：网络失败时提供重试按钮）
   *
   * ★ 只在"没有鉴权错误可展示"时才提示：否则用户输错密码时会同时看到
   *   "用户名或密码错误"和"无法连接服务端"两条互相矛盾的信息。
   *   （网络类失败时 `AuthStore` 自己给的文案已含排查指引，那一条更准确。）
   */
  @Computed
  get retryMessage(): string {
    if (this.phase !== 'auth' || this.authError.length > 0) {
      return '';
    }
    return this.app.offline ? `无法连接服务端 ${this.app.serverHost}:${this.app.serverPort}` : '';
  }

  /** 当前服务端地址文案（登录页底部常驻显示 · 排查 401 的第一现场信息） */
  @Computed
  get serverLabel(): string {
    return `${this.app.serverHost}:${this.app.serverPort}`;
  }

  /**
   * 失败弹窗的**标题** · 按 `AuthStore.failKind` 选词
   *
   * ★ 同一个 401 在后端只有一句话（"用户名或密码错误"），但"为什么失败"有五种完全不同的
   *   排查方向 —— 这一层就是把这五种分开，交给登录页的弹窗显示（页面不判断错误类型）。
   */
  @Computed
  get authErrorTitle(): string {
    if (this.phase !== 'auth') {
      return '';
    }
    const kind: AuthFailKind = this.app.auth().failKind;
    if (kind === AuthFailKind.invalid) {
      return '无法提交';
    }
    if (kind === AuthFailKind.credentials) {
      return '登录失败';
    }
    if (kind === AuthFailKind.disabled) {
      return '账号已禁用';
    }
    if (kind === AuthFailKind.network) {
      return '无法连接服务端';
    }
    if (kind === AuthFailKind.server) {
      return '服务端异常';
    }
    if (kind === AuthFailKind.unknown) {
      return '登录失败';
    }
    // 没有失败类别但确实有文案 → 冷启动那条"登录已过期，请重新登录"
    return this.authError.length > 0 ? '需要重新登录' : '';
  }

  /**
   * 失败弹窗的**诊断行** · 一句话说清"请求到底有没有到服务端"
   *
   * ★ 这是本轮针对「一直点登录都提示密码错误」补的关键信息：
   *   · 401 → 服务端**已经回应**了，问题在账号密码/账号归属（不是网络）；
   *   · network → 请求根本没到服务端，方向完全不同。
   *   用户据此就能自己判断该改密码还是该查地址，不必猜。
   */
  @Computed
  get authErrorHint(): string {
    if (this.phase !== 'auth') {
      return '';
    }
    const kind: AuthFailKind = this.app.auth().failKind;
    const status: number = this.app.auth().failStatus;
    const target: string = this.serverLabel;
    const statusText: string = status > 0 ? `${status}` : '—';
    if (kind === AuthFailKind.credentials) {
      return `服务端 ${target} 已回应 HTTP ${statusText}：用户名或密码不匹配（后端不区分"账号不存在"与"密码错"）。可点密码框右侧「显示」核对输入，并确认账号是注册在这台服务器上。`;
    }
    if (kind === AuthFailKind.disabled) {
      return `服务端 ${target} 已回应 HTTP ${statusText}：账号已被禁用，请联系管理员。`;
    }
    if (kind === AuthFailKind.network) {
      return `请求没有到达服务端 ${target}：请检查网络，并确认后端已启动（可用底部「重新连接服务端」探活）。`;
    }
    if (kind === AuthFailKind.server) {
      return `服务端 ${target} 回应异常（HTTP ${statusText}）：请稍后重试，或查看服务端日志。`;
    }
    if (kind === AuthFailKind.invalid) {
      return '本次没有发出网络请求：本地校验未通过，请按提示修改后再试。';
    }
    if (kind === AuthFailKind.unknown) {
      return `请求失败 · 服务端 ${target}`;
    }
    return '';
  }

  // ══════════════════ 生命周期 ══════════════════

  aboutToAppear(): void {
    this.launchAt = Date.now();
    // ★ 先把登录页压入登录流的栈：首次渲染时栈非空，不会出现根内容闪一帧的情况
    if (!this.loginStackReady) {
      this.loginStackReady = true;
      this.syncLoginParam();
      this.loginStack.pushPathByName(LOGIN_ROUTE, this.loginParam, false);
    }
    // 引导流程在 EntryAbility.onCreate 里已经点火，这里只等它结束再刷新一次界面
    AppBootstrap.ready.then(() => {
      this.refreshUi();
      this.dismissSplash();
    });
    // ★ 兜底：引导万一卡住，开屏页也必须让位（否则用户永远看到开屏页）
    setTimeout((): void => {
      this.splashVisible = false;
    }, SPLASH_MAX_MS);
  }

  // ══════════════════ 开屏页 ══════════════════

  /**
   * 收起开屏页（**至少**显示 `UiTheme.splashMinDurationMs`）
   *
   * ★ 为什么要设下限：引导流程在缓存命中时两百毫秒就结束了，
   *   不留一个下限的话开屏页只会"闪一下"，比不显示更难看。
   * ★ 收起方式：把 `splashVisible` 置 false，由 `build()` 里那个 `if` 上的
   *   `transition(OPACITY)` 播淡出；下层的登录流/骨架屏在这期间就已经构建好了，
   *   所以淡出结束看到的是**已经就绪**的界面，不会出现"先白一下再出内容"。
   */
  private dismissSplash(): void {
    const elapsed: number = Date.now() - this.launchAt;
    const wait: number = elapsed >= UiTheme.splashMinDurationMs ? 0 : (UiTheme.splashMinDurationMs - elapsed);
    setTimeout((): void => {
      this.splashVisible = false;
    }, wait);
  }

  // ══════════════════ 页面参数构造（★ 唯一注入点） ══════════════════

  /**
   * 把所有页面参数同步到 store 的当前状态
   *
   * ★ 调用时机：**每次 await 收敛之后**（引导完成 / 登录返回 / 注册返回 / 探活返回）。
   *   `@Builder` 体内只能写 UI 组件（调普通方法会报 "does not meet UI component syntax"），
   *   所以不能放在 build 里做，只能在状态收敛点手动同步。
   */
  private syncAllParams(): void {
    this.syncLoginParam();
    this.syncRegisterParam();
    this.syncMainParam();
  }

  /**
   * 让界面与页面参数都跟上 store 的最新状态
   * `tick` 让 `@Computed` 失效重算，`syncAllParams` 把值写回缓存好的参数对象。
   */
  private refreshUi(): void {
    this.tick = this.tick + 1;
    this.syncAllParams();
  }

  /** 把 store 的实时状态写进缓存的登录页参数（动作回调只挂一次，不重复创建闭包） */
  private syncLoginParam(): void {
    const param: LoginPageParam = this.loginParam;
    if (!this.loginActionsAttached) {
      this.loginActionsAttached = true;
      this.attachLoginActions(param);
    }
    param.authBusy = this.authBusy;
    param.authError = this.authError;
    // ★ 失败三元组里的后两项：标题与诊断行（页面只负责画，不判断类别）
    param.authErrorTitle = this.authErrorTitle;
    param.authErrorHint = this.authErrorHint;
    param.retryMessage = this.retryMessage;
    param.retrying = this.retrying;
    param.serverLabel = this.serverLabel;
  }

  /** 挂载登录页的两个动作回调（只在首次调用时执行） */
  private attachLoginActions(param: LoginPageParam): void {
    param.onLogin = async (username: string, password: string, email: string): Promise<boolean> => {
      const result: ActionResultModel = await AppStore.get().auth().login(username, password);
      // ★ 无论成败都 sync 一次：成功要把 signedIn 镜像到门面，失败要把 errorMsg 带出来
      AppStore.get().sync();
      if (!result.ok) {
        this.refreshUi();
        return false;
      }
      // ★ 门面不会自动拉业务数据，登录成功后必须自己拉一次
      await AppStore.get().loadAll();
      this.refreshUi();
      return true;
    };

    param.onRegister = async (username: string, password: string, email: string): Promise<boolean> => {
      // 注册是独立页面，这里只负责跳转，并把已输入的用户名/密码带过去预填
      this.syncRegisterParam();
      this.registerParam.presetUsername = username;
      this.registerParam.presetPassword = password;
      this.loginStack.pushPathByName(REGISTER_ROUTE, this.registerParam);
      return true;
    };

    param.onRetry = async (): Promise<string> => {
      return await this.checkServer();
    };
  }

  /** 把 store 的实时状态写进缓存的注册页参数 */
  private syncRegisterParam(): void {
    const param: RegisterPageParam = this.registerParam;
    if (!this.registerActionsAttached) {
      this.registerActionsAttached = true;
      param.onRegister = async (username: string, password: string, email: string): Promise<boolean> => {
        // ★ 注册即登录：AuthStore.register 内部拿到 token 后会立刻再调 /api/auth/me
        const result: ActionResultModel = await AppStore.get().auth().register(username, password, email);
        AppStore.get().sync();
        if (!result.ok) {
          this.refreshUi();
          return false;
        }
        await AppStore.get().loadAll();
        this.refreshUi();
        return true;
      };
      param.onBackToLogin = () => {
        // 出栈回登录页；栈里没有登录页时保持不变（不会崩）
        this.loginStack.popToIndex(0);
      };
    }
    param.authBusy = this.authBusy;
    param.authError = this.authError;
    // 注册页与登录页共用同一套失败三元组（同一个 AuthStore、同一种弹窗）
    param.authErrorTitle = this.authErrorTitle === '登录失败' || this.authErrorTitle === '需要重新登录'
      ? '注册失败' : this.authErrorTitle;
    param.authErrorHint = this.authErrorHint;
  }

  /** 主界面参数 · 同步只读展示文案（用户名 / 服务端地址） */
  private syncMainParam(): void {
    const param: MainPageParam = this.mainParam;
    if (!this.mainActionsAttached) {
      this.mainActionsAttached = true;
      this.attachMainActions(param);
    }
    param.signedIn = this.app.signedIn;
    param.userName = this.app.username();
    param.serverLabel = this.serverLabel;
  }

  /**
   * 挂载主界面的动作回调（只在首次调用时执行）
   *
   * ★ 目前只有"退出登录"一件：由**本文件**统一实现「清登录态 + 复位登录栈 + 刷新界面」，
   *   而不是让 `MainPage` 自己调 `AuthStore.logout()` ——
   *   登录流的栈属于本页，`MainPage` 碰不到它（详见 `MainPageParam.onLogout` 注释）。
   */
  private attachMainActions(param: MainPageParam): void {
    param.onLogout = async (): Promise<void> => {
      // ① 清登录态：删令牌 + 清业务缓存 + 清内存（由 AuthStore.logout 的内部 cleanup 完成）
      await AppStore.get().auth().logout('');
      // ② 顺手清掉"登录已过期"这类全局提示，否则刚退出就会在登录页看到一条红字
      AppStore.get().clearGlobalMessage();
      AppStore.get().sync();
      // ③ 把登录流的栈复位到登录页（用户注册过的话，栈顶还压着注册页）
      this.resetLoginStack();
      this.refreshUi();
    };
  }

  /**
   * 复位登录流的栈：清空后只留一个登录页
   *
   * ★ 为什么必须做：注册页是 `pushPathByName` 压进来的，注册成功后界面切到主界面，
   *   但 `loginStack` 里仍然是 `[登录, 注册]`。不做复位的话，用户点「退出登录」后
   *   会直接落在**注册页**上 —— 这是本轮新增登出功能必然带来的连带问题。
   */
  private resetLoginStack(): void {
    this.syncLoginParam();
    this.loginStack.clear(false);
    this.loginStack.pushPathByName(LOGIN_ROUTE, this.loginParam, false);
    this.loginStackReady = true;
  }

  /** 探活重连 · 供登录页的"重新连接服务端"按钮使用 */
  private async checkServer(): Promise<string> {
    this.retrying = true;
    this.syncLoginParam();
    const result: ActionResultModel = await AppStore.get().checkHealth();
    this.retrying = false;
    this.refreshUi();
    return result.ok ? '' : result.message;
  }

  // ══════════════════ 路由分发（登录流） ══════════════════

  @Builder
  loginDestination(name: string, param: ESObject) {
    if (name === LOGIN_ROUTE && param instanceof LoginPageParam) {
      NavDestination() {
        LoginPage({ pageParam: param as LoginPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
      // ★ 登录页是登录流的**根页面**：系统返回键不允许把它弹掉。
      //   弹掉之后栈为空，Navigation 只会露出一个空白根内容（真机实测：整屏纯白，
      //   用户会以为应用卡死）。返回 true = 消费返回事件。
      .onBackPressed((): boolean => {
        return true;
      })
    } else if (name === REGISTER_ROUTE && param instanceof RegisterPageParam) {
      NavDestination() {
        RegisterPage({ pageParam: param as RegisterPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
      // 注册页允许返回（回到登录页），因此这里**不**拦截
    }
  }

  // ══════════════════ 界面组装 ══════════════════

  /** 引导中 · 骨架屏（规范：加载时显示骨架屏） */
  @Builder
  readyStage() {
    AuthSkeleton()
  }

  /** 未登录 · 登录流（登录页 ↔ 注册页） */
  @Builder
  authStage() {
    Column() {
      Navigation(this.loginStack) {
        // 内容区由 navDestination 分发器接管；`aboutToAppear` 已把登录页入栈，
        // 这里的根内容不会显示，只作为空栈兜底。
        // ★ 兜底也做成"自愈"：万一栈被清空（异常返回键 / 未来某处误清），
        //   这段根内容一露出来就把登录页重新压回去，而不是留一块白屏。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(UiTheme.pageBackground)
          .onAppear((): void => {
            if (this.loginStack.size() === 0) {
              this.resetLoginStack();
            }
          })
      }
      .navDestination(this.loginDestination)
      .hideTitleBar(true)
      .mode(NavigationMode.Stack)
      .backgroundColor(UiTheme.pageBackground)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.pageBackground)
  }

  /** 已登录 · 主界面 */
  @Builder
  mainStage() {
    MainPage({ pageParam: this.mainParam })
  }

  /** 当前阶段的界面（开屏页淡出后露出的就是它） */
  @Builder
  stageContent() {
    Column() {
      if (this.phase.length === 0) {
        this.readyStage()
      } else if (this.phase === 'auth') {
        this.authStage()
      } else {
        this.mainStage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.pageBackground)
  }

  build() {
    // ★ 两层结构：① 阶段内容 ② 开屏页（覆盖在最上层）
    //   开屏页是"覆盖"而不是"阶段"，所以它淡出时下层已经构建完成，
    //   不会出现"白一下再出内容"的中间态，也不需要额外的骨架屏衔接。
    Stack({ alignContent: Alignment.TopStart }) {
      this.stageContent()

      if (this.splashVisible) {
        SplashView()
          .transition(TransitionEffect.OPACITY.animation({ duration: 320, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.pageBackground)
  }
}
