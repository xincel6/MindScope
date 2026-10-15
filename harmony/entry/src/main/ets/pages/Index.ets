/**
 * Index · **Ability 入口页 / 应用外壳**（`main_pages.json` 里注册的唯一 @Entry 页面）
 *
 * 它只做"阶段分支"，不画任何业务界面：
 * ```
 *                            ┌ bootPhase = idle / preparing        → 骨架屏
 * Index（本文件，@ComponentV2）┼ signedIn  = false                   → 登录流（独立 Navigation）
 *                            └ signedIn  = true                    → 主界面（独立 Navigation）
 * ```
 *
 * ★ 本文件是**唯一**允许触碰 store、网络与路由栈的 UI 文件（"窗口层"）：
 *   两个分支里的页面组件全部只接受参数（见 `types/PageParams.ets` 的三条纪律）。
 *
 * ★ 登录态切换靠数据驱动：`AuthStore.login/register` 成功后会把 `AuthStore.signedIn`
 *   置为 true，`AppStore.sync()` 把它镜像到门面，本页的 `@Computed signedIn` 随之失效重算，
 *   界面自动从登录流切到主界面 —— **不需要任何显式跳转指令**。
 *
 * ★ ArkTS 响应式要点：`@Computed` 必须真正读到 `@Trace` 字段才会建立依赖；
 *   而 `AppStore.get()` 是普通静态方法调用，所以这里额外读一个 `tick` 计数器，
 *   在每次 `await` 之后 +1，保证界面一定会重新取数（工程既有页面同样是这个写法）。
 */

import { AppBootstrap } from '../common/AppBootstrap';
import { UiTheme } from '../common/UiTheme';
import { AppStore } from '../store/AppStore';
import { ActionResultModel, BootPhase } from '../types/Index';
import { LoginPageParam, MainPageParam, RegisterPageParam } from '../types/PageParams';
import { AuthSkeleton } from '../components/SkeletonView';
import { LOGIN_ROUTE, REGISTER_ROUTE } from './PageRoutes';
import { LoginPage } from './LoginPage';
import { RegisterPage } from './RegisterPage';
import { MainPage } from './MainPage';

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

  // ══════════════════ 生命周期 ══════════════════

  aboutToAppear(): void {
    // ★ 先把登录页压入登录流的栈：首次渲染时栈非空，不会出现根内容闪一帧的情况
    if (!this.loginStackReady) {
      this.loginStackReady = true;
      this.syncLoginParam();
      this.loginStack.pushPathByName(LOGIN_ROUTE, this.loginParam, false);
    }
    // 引导流程在 EntryAbility.onCreate 里已经点火，这里只等它结束再刷新一次界面
    AppBootstrap.ready.then(() => {
      this.refreshUi();
    });
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
    param.retryMessage = this.retryMessage;
    param.retrying = this.retrying;
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
  }

  /** 主界面参数 · 同步只读展示文案（用户名 / 服务端地址） */
  private syncMainParam(): void {
    const param: MainPageParam = this.mainParam;
    param.signedIn = this.app.signedIn;
    param.userName = this.app.username();
    param.serverLabel = `${this.app.serverHost}:${this.app.serverPort}`;
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
    } else if (name === REGISTER_ROUTE && param instanceof RegisterPageParam) {
      NavDestination() {
        RegisterPage({ pageParam: param as RegisterPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
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
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(UiTheme.pageBackground)
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

  build() {
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
}
