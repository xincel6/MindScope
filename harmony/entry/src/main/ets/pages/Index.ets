/**
 * Index · **Ability 入口页 / 应用外壳**（`main_pages.json` 里注册的唯一 @Entry 页面）
 *
 * 它只做"阶段分支"，不画任何业务界面：
 * ```
 *                            ┌ bootPhase = idle / preparing        → 待机页（StandbyView）
 * Index（本文件，@ComponentV2）┼ signedIn  = false                   → 登录流（独立 Navigation）
 *                            └ signedIn  = true                    → 主界面（独立 Navigation）
 * ```
 *
 * ★ 待机页不是"覆盖层"而是**一个真实的阶段**（`phase === ''`）：用户看到的第一个界面
 *   就是它，引导结束后它被登录页顶掉。登录页的入场动画（图标放大 + 白层上滑）写在
 *   `LoginPage.playEnter()` 里，两个页面的品牌区共用 `UiTheme.heroTop / heroLogoWidth`，
 *   所以这一刀切下去图标不会跳。
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
import { StandbyView } from '../components/StandbyView';
import { LOGIN_ROUTE, REGISTER_ROUTE } from './PageRoutes';
import { LoginPage } from './LoginPage';
import { RegisterPage } from './RegisterPage';
import { MainPage } from './MainPage';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 待机页最短展示时长（毫秒）· 见 `UiTheme.standbyMinDurationMs`
 *
 * ★ 为什么由本页来卡：引导流程（读缓存 → 探活 → 拉数据）在缓存命中时两百毫秒就结束了，
 *   不留下限的话"待机页"只会闪一下 —— 用户看到的是白屏闪动，比不显示更难看。
 *   这里把"允许离开待机页"的最早时刻记下来，而不是去延迟引导本身（引导越快越好）。
 */
const STANDBY_MIN_MS: number = UiTheme.standbyMinDurationMs;

/** 已登录冷启动时，待机页淡出到主界面的时长（毫秒） */
const COVER_FADE_MS: number = 360;

/**
 * 图标长大之后、切页之前的停顿（毫秒）
 *
 * ★ 需要一点点"停住"：放大结束时图标正好停在登录页的尺寸上，留 60ms 让眼睛
 *   确认"它已经到了"，白层再盖上来才像是接着发生的第二拍，而不是同一口气。
 */
const STANDBY_HOLD_MS: number = 60;

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
   * 是否还压在待机页上
   *
   * ★ 它是"最短展示时长"的执行者：`phase` 可能很早就变成 'auth'/'main'，
   *   但只要这个开关还是 true，`shownPhase` 就继续返回 ''（继续显示待机页）。
   *   到点后置 false，界面一次性切到真实阶段 —— 切换动作本身是"一帧完成"的，
   *   因为登录页有自己的入场动画、主界面有自己的淡出覆盖层。
   */
  @Local holdStandby: boolean = true;

  /**
   * 待机页图标的"长大"倍数（1 → 1/heroLogoStart）
   *
   * ★ 用户选定的节奏是"图标先放大，白层再盖上"：引导就绪且够时长后，先在
   *   **待机页上**把图标推到登录页的尺寸（`heroEnterMs`），推完才切页；
   *   登录页接手时图标已经是最终大小，只需要把白层盖上来。
   * ★ 只改这一个数就能让整个转场停下：`animateTo` 只动 `scale()`，不触发排版。
   */
  @Local standbyGrowScale: number = 1;

  /**
   * 冷启动直通主界面时的品牌色覆盖层
   *
   * ★ 为什么只在这一条路上需要：待机页 → 登录页有"白层上滑"做衔接；
   *   而待机页 → 主界面是两套完全不同的版式（青绿 ↔ 浅灰），硬切会像闪屏。
   *   所以先把待机页留在最上层，让主界面在底下构建好，再把它淡出。
   */
  @Local bootCoverVisible: boolean = false;

  /** 覆盖层当前透明度 */
  @Local bootCoverOpacity: number = 1;

  /** 应用启动时刻（毫秒）· 用来算"待机页还差多少才到最短展示时长" */
  private launchAt: number = 0;

  /** 覆盖层是否已经播过（只在冷启动时播一次） */
  private coverPlayed: boolean = false;

  /** 状态栏内容色是否已按当前阶段设置过（避免每帧都调系统接口） */
  private barStyleApplied: string = '';

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
   * 界面上**实际**显示哪个阶段 · 只在"待机页最短展示时长"内与 `phase` 不同
   *
   * ★ 两个都保留的原因：`phase` 是"数据真相"（store 到哪一步了），
   *   `shownPhase` 是"观感真相"（用户现在该看什么）。把它们混成一个会让
   *   "引导已完成"与"界面已切换"两件事纠缠在一起，后面加延迟或兜底就无处下刀。
   */
  @Computed
  get shownPhase(): string {
    if (this.holdStandby) {
      return '';
    }
    return this.phase;
  }

  /**
   * 待机页底部那句状态 · 让等待**可解释**
   *
   * ★ "正在启动"与"正在准备数据"必须分开：前者一闪而过，后者在慢网/坏服务端时
   *   会停留十几秒 —— 用户看到"正在准备数据"才知道是在等后端，而不是 App 挂了。
   */
  @Computed
  get standbyStatusText(): string {
    const phase: BootPhase = this.app.bootPhase;
    if (phase === BootPhase.preparing) {
      return '正在准备数据…';
    }
    return '正在启动…';
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
    this.applyBarStyle(this.phase !== 'main');
    // ★ 先把登录页压入登录流的栈：首次渲染时栈非空，不会出现根内容闪一帧的情况
    if (!this.loginStackReady) {
      this.loginStackReady = true;
      this.syncLoginParam();
      this.loginStack.pushPathByName(LOGIN_ROUTE, this.loginParam, false);
    }
    // 引导流程在 EntryAbility.onCreate 里已经点火，这里只等它结束
    AppBootstrap.ready.then(() => {
      this.refreshUi();
      this.releaseStandby();
    });
  }

  // ══════════════════ 待机页收尾 ══════════════════

  /**
   * 允许离开待机页（**至少**展示 `STANDBY_MIN_MS`）
   *
   * ★ 到点后按阶段分两条路：
   *   · 未登录 → 先在待机页上把图标放大到登录页尺寸，**放完才切页**（用户选的节奏）；
   *   · 已登录 → 直接放开开关，再用品牌色覆盖层淡出（主界面版式完全不同，硬切会闪）。
   * ★ 顺序不能反：先放开开关再刷界面，`shownPhase` 才会算出真实阶段。
   */
  private releaseStandby(): void {
    const elapsed: number = Date.now() - this.launchAt;
    const wait: number = elapsed >= STANDBY_MIN_MS ? 0 : (STANDBY_MIN_MS - elapsed);
    setTimeout((): void => {
      if (this.phase !== 'main') {
        this.growStandbyLogoThenEnter();
        return;
      }
      this.holdStandby = false;
      this.refreshUi();
      this.playBootCoverIfNeeded();
    }, wait);
  }

  /**
   * 待机页图标"长大"到登录页尺寸，之后再切页
   *
   * ★ 这是"待机页 → 登录页"转场的第一拍：图标在**原地**从 0.84 长到 1
   *   （`.scale()` 不参与排版，下面的 MindScope/产品名一动不动）。
   * ★ 放完再切，是为了让"长大"这件事被看见：如果切页和放大同时发生，
   *   白层会盖住放大过程的后半段（用户实测感受是"没看清就没了"）。
   */
  private growStandbyLogoThenEnter(): void {
    this.getUIContext().animateTo({
      duration: UiTheme.heroEnterMs,
      curve: Curve.EaseOut
    }, (): void => {
      // 父级 @Param 变化会带动子组件一起播这条动画
      this.standbyGrowScale = 1 / UiTheme.heroLogoStart;
    });
    setTimeout((): void => {
      this.holdStandby = false;
      this.refreshUi();
    }, UiTheme.heroEnterMs + STANDBY_HOLD_MS);
  }

  /**
   * 冷启动直通主界面时，把待机页当覆盖层淡出
   *
   * ★ 只在 `phase === 'main'` 且没播过时执行一次；登录流不需要它（白层上滑已经在衔接）。
   */
  private playBootCoverIfNeeded(): void {
    if (this.coverPlayed || this.phase !== 'main') {
      return;
    }
    this.coverPlayed = true;
    this.bootCoverVisible = true;
    this.bootCoverOpacity = 1;
    this.getUIContext().animateTo({
      duration: COVER_FADE_MS,
      curve: Curve.EaseInOut
    }, (): void => {
      this.bootCoverOpacity = 0;
    });
    setTimeout((): void => {
      this.bootCoverVisible = false;
    }, COVER_FADE_MS + 40);
  }

  /**
   * 按当前页面底色设置状态栏/导航栏内容色
   *
   * ★ 必须切：待机页与登录页是**青绿满屏**，系统默认的深色图标在上面几乎看不见；
   *   主界面、注册页是浅色页面，用白色图标同样看不见。所以这里跟着当前页面改，
   *   而不是在 EntryAbility 里写死一次。
   * ★ `onBrand = true` 表示"这一页是青绿底、要白图标"。
   * ★ 失败只记日志：状态栏颜色是"锦上添花"，不能因为系统接口拒绝而让页面挂掉。
   */
  private applyBarStyle(onBrand: boolean): void {
    const key: string = onBrand ? 'brand' : 'light';
    if (this.barStyleApplied === key) {
      return;
    }
    this.barStyleApplied = key;
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      const props: window.SystemBarProperties = {
        statusBarContentColor: onBrand ? '#FFFFFF' : '#000000',
        isStatusBarLightIcon: onBrand,
        navigationBarContentColor: onBrand ? '#FFFFFF' : '#000000',
        isNavigationBarLightIcon: onBrand
      };
      win.setWindowSystemBarProperties(props).catch((err: BusinessError): void => {
        console.error(`Index.applyBarStyle 失败: ${err.code} ${err.message}`);
      });
    }).catch((err: BusinessError): void => {
      console.error(`Index.applyBarStyle 取窗口失败: ${err.code} ${err.message}`);
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
    // ★ 阶段可能刚变（登录成功 / 登出），状态栏内容色要跟着切。
    //   注意这里只按"阶段"给粗值：auth 阶段默认落在登录页（青绿），
    //   注册页是浅色页面，由 `loginDestination` 里的 onShown/onHidden 再纠正。
    this.applyBarStyle(this.phase !== 'main');
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
      // ★ 兜底用品牌深色（不是浅灰）：登录页是青绿满屏，
      //   万一它某一帧没画满，露出来的也应该是同一族的深青绿，而不是一条浅灰边。
      .backgroundColor(UiTheme.brandEnd)
      // ★ 登录页是登录流的**根页面**：系统返回键不允许把它弹掉。
      //   弹掉之后栈为空，Navigation 只会露出一个空白根内容（真机实测：整屏纯白，
      //   用户会以为应用卡死）。返回 true = 消费返回事件。
      .onBackPressed((): boolean => {
        return true;
      })
      // 回到登录页 = 回到青绿底，状态栏图标要换回白色
      .onShown(() => {
        this.applyBarStyle(true);
      })
    } else if (name === REGISTER_ROUTE && param instanceof RegisterPageParam) {
      NavDestination() {
        RegisterPage({ pageParam: param as RegisterPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
      // 注册页允许返回（回到登录页），因此这里**不**拦截
      // ★ 注册页是浅灰底（登录页是青绿底），状态栏图标必须跟着换深色，
      //   否则进到注册页后时间/电量就"消失"了（实测白图标压在 #F2F3F7 上）
      .onShown(() => {
        this.applyBarStyle(false);
      })
      .onHidden(() => {
        this.applyBarStyle(true);
      })
    }
  }

  // ══════════════════ 界面组装 ══════════════════

  /** 引导中 · 待机页（用户看到的第一个界面） */
  @Builder
  standbyStage() {
    StandbyView({
      statusText: this.standbyStatusText,
      growScale: this.standbyGrowScale
    })
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
      // ★ 透明：登录页自己铺满青绿渐变（并扩到状态栏底下），
      //   这里再刷一层底色会在安全区边缘留下细边
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    // ★ 透明：见下方 `stageContent` 的同名说明
    .backgroundColor(Color.Transparent)
  }

  /** 已登录 · 主界面 */
  @Builder
  mainStage() {
    MainPage({ pageParam: this.mainParam })
  }

  /** 当前阶段的界面（待机页 / 登录流 / 主界面） */
  @Builder
  stageContent() {
    Column() {
      if (this.shownPhase.length === 0) {
        this.standbyStage()
      } else if (this.shownPhase === 'auth') {
        this.authStage()
      } else {
        this.mainStage()
      }
    }
    .width('100%')
    .height('100%')
    // ★ 透明：三个阶段各自满屏作画（待机/登录是青绿渐变且要铺进状态栏），
    //   这里再刷一层浅灰只会在安全区边缘露出细边
    .backgroundColor(Color.Transparent)
  }

  build() {
    // ★ 两层结构：① 阶段内容 ② 冷启动直通主界面时的品牌色覆盖层（只在这一条路上出现）
    Stack({ alignContent: Alignment.TopStart }) {
      this.stageContent()

      if (this.bootCoverVisible) {
        StandbyView({ statusText: '正在准备数据…' })
          .opacity(this.bootCoverOpacity)
          // 覆盖层只是"盖着看一眼"，不该吃掉下层主界面的点击
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.pageBackground)
  }
}
