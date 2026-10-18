/**
 * PageParams · **全部页面参数契约的唯一文件**
 *
 * 本工程的页面纪律（详见 `docs/鸿蒙端页面框架与路由说明.md`）：
 *   ① 页面一律 `@ComponentV2` + 只读 `@Param`，**不 import 任何 store**；
 *   ② 页面要展示的一切（文案 / 忙碌态 / 错误 / 回调）都从参数对象取；
 *   ③ 页面要产生的动作都通过参数里的回调交回窗口层。
 *
 * 于是"页面接口"就是这些参数类 —— 集中在一个文件里，看这一份就能知道
 * **每个页面需要什么、能做什么**，不必逐个翻页面源码。
 *
 * 调用方只有两个（"窗口层"）：
 *   - `pages/Index.ets`    登录流：登录页 / 注册页 / 主界面的参数
 *   - `pages/MainPage.ets` 主界面内部：五个页签的参数
 *
 * ★ 后缀为什么是 `.ets`：本文件要引用 `NavPathStack`（ArkUI 组件类型），
 *   纯 `.ts` 不能 import ArkUI 组件类型，所以按工程规则（docs/本轮开发交接.md 5.2 节）
 *   归入"ArkTS 专用"。它放在 `types/` 是因为**内容仍然全是数据类型**。
 *
 * ★ `NavPathStack` 是 ArkUI 的**全局声明类型**（`component/navigation.d.ts` 里 `declare class`），
 *   不需要也无法 import（`@kit.ArkUI` 并未导出它）。直接写类型名即可。
 */

import { MediaType } from './enums';
import { CurrentTaskModel, MediaItemModel, RecentMediaModel, ReportListItemModel } from './model';

/** 全部页面参数的基类 · 让"页面参数"在类型上有一个共同祖先，便于统一签名与调试 */
export class PageParam {
}

/**
 * 五个一级页签 · **枚举值即路由名**，顺序即底部导航栏的展示顺序
 *
 * ★ 顺序不能随便调：底部导航栏按下标渲染，`workbench` 必须排第一（默认页）。
 */
export enum MainTab {
  /** 工作台 */
  workbench = 'workbench',
  /** 素材库 */
  media = 'media',
  /** 历史报告 */
  reports = 'reports',
  /** 统计 */
  stats = 'stats',
  /** 我的 */
  profile = 'profile'
}

/**
 * 鉴权动作签名 · 登录与注册共用
 *
 * 页面把用户输入交给窗口层，窗口层负责调 `AuthStore` 并把结果转成 boolean：
 *  - 返回 `true`  → 鉴权成功（窗口层已落地登录态，界面会自动切换）
 *  - 返回 `false` → 失败（页面保持原样，错误文案由窗口层回填到参数里）
 *
 * @param username 用户名（页面已按 `AuthRule` 做过本地校验）
 * @param password 密码
 * @param email    邮箱；登录时传空串，注册时可空（窗口层会转成 null 发给服务端）
 */
export type AuthAction = (username: string, password: string, email: string) => Promise<boolean>;

// ══════════════════════════════════════════════════════════════════
//  一、登录页参数
// ══════════════════════════════════════════════════════════════════

/**
 * 登录页参数（`pages/LoginPage.ets`）
 *
 * ```ts
 * const param = new LoginPageParam();
 * param.onLogin = async (u, p, e) => { ... };   // 窗口层调 AuthStore.login
 * param.onRegister = (u, p, e) => { ... };      // 窗口层跳转独立注册页
 * param.authBusy = AppStore.get().auth().loading;
 * param.authError = AppStore.get().auth().errorMsg;
 * ```
 *
 * ══════════════════ ★★ 本轮（登录页重构）为什么加 `@ObservedV2` / `@Trace` ══════════════════
 * 上一版这里有一个**假的假设**："登录页参数的字段都是 push 之前写一次、挂载后不再变"。
 * 实际上窗口层是在**每次登录请求返回之后**才回填 `authBusy / authError` 等字段的，
 * 那时登录页早就挂载好了。普通 class 的字段写入两耳不闻，于是：
 *   · 输入框下方那行错误文案不会出现（要等别的原因触发整页重渲染才"忽然"冒出来）；
 *   · 失败时按钮文案/禁用态也可能停在旧值。
 * 这与 `BUG清单.md` 的 BUG-11 是**同一条根因**（参数对象不可观察 → 挂载后改字段等于没写）。
 *
 * 判定标准只有一条（BUG-11 立的规矩）：
 * **给字段赋值的那一行，是在页面 `NavDestination` 挂载之后执行的吗？** 是 → 必须可观察。
 * 所以这里把"挂载后会变"的字段全部标 `@Trace`；回调与一次性字段保持普通字段，
 * 不给每次写入都白挂一层观察者。
 */
@ObservedV2
export class LoginPageParam extends PageParam {
  // ── 动作回调（push 之前挂一次，挂载后不再变 → 普通字段）──

  /** 点「登录」· 窗口层负责调 `AuthStore.login` */
  public onLogin: AuthAction = (username: string, password: string, email: string): Promise<boolean> => {
    return Promise.resolve(false);
  };

  /** 点「注册账号」· 窗口层负责跳转到独立的注册页（可携带已输入的用户名/密码去预填） */
  public onRegister: AuthAction = (username: string, password: string, email: string): Promise<boolean> => {
    return Promise.resolve(false);
  };

  /** 点「重新连接服务端」· 窗口层负责调 `AppStore.checkHealth()`；返回空串表示探活成功 */
  public onRetry: () => Promise<string> = (): Promise<string> => {
    return Promise.resolve('');
  };

  // ── 以下字段由窗口层在**页面已挂载之后**回填，必须 `@Trace` ──

  /** 是否正在鉴权（按钮禁用 + 文案变"登录中…"） */
  @Trace authBusy: boolean = false;

  /**
   * 鉴权失败文案 · 非空即展示（含"登录已过期，请重新登录"这类冷启动文案）
   * ★ 页面自行遵守一条显示规则：用户重新输入后，这条错误会被收起；
   *   窗口层不需要为此做任何事（详见 `docs/鸿蒙端页面框架与路由说明.md` 3.3 节）。
   */
  @Trace authError: string = '';

  /**
   * 失败弹窗的**标题**（本轮新增）· 由窗口层按 `AuthFailKind` 给：
   * "登录失败" / "无法连接服务端" / "账号已禁用" …
   * ★ 页面不自己判断错误类型（页面纪律），只负责把它画进弹窗。
   */
  @Trace authErrorTitle: string = '登录失败';

  /**
   * 失败弹窗的**诊断行**（本轮新增）· 窗口层拼好的一行事实陈述，例如：
   *   "服务端 100.122.178.113:8000 已回应 HTTP 401 —— 账号密码不匹配，可点「显示」核对密码"
   *   "请求没有到达服务端（100.122.178.113:8000）—— 检查网络/服务端是否启动"
   * ★ 作用：把「密码错」与「连不上服务端」在界面上彻底分开，
   *   这是本轮修「一直点登录都提示密码错误」时最缺的一条信息。
   */
  @Trace authErrorHint: string = '';

  /** 非空时在底部显示"错误 + 重新连接服务端"（网络不可达 / 服务端未启动） */
  @Trace retryMessage: string = '';

  /** 是否正在探活重连 */
  @Trace retrying: boolean = false;

  /**
   * 当前服务端地址文案（本轮新增 · 形如 100.122.178.113:8000）
   * ★ 登录页底部常驻一行小字：用户/开发者一眼能看到"这台手机连的是哪台服务器"。
   *   账号在 A 服务器、App 连 B 服务器时，401 的唯一解释就是"账号不在这一台"。
   */
  @Trace serverLabel: string = '';
}

// ══════════════════════════════════════════════════════════════════
//  二、注册页参数
// ══════════════════════════════════════════════════════════════════

/**
 * 注册页参数（`pages/RegisterPage.ets`）
 *
 * 注册页与登录页**相互独立**：自己的路由、自己的文件，通过 `onBackToLogin` 回到登录页。
 *
 * 业务事实（docs/鸿蒙端接口清单与登录注册实现.md 2.2 节）：
 *   注册成功响应里**没有用户信息**，但后端是"注册即登录"（直接返回 token），
 *   `AuthStore.register()` 内部已经接着调了 `/api/auth/me` 把用户信息补齐，
 *   所以窗口层只要调用它，页面侧就表现为"注册完成后自动登录"。
 *
 * ★ 本轮加 `@ObservedV2`：理由与登录页完全相同（失败文案是在页面挂载之后才回填的）。
 */
@ObservedV2
export class RegisterPageParam extends PageParam {
  // ── 动作回调（push 之前挂一次 → 普通字段）──

  /**
   * 点「注册」· 窗口层负责调 `AuthStore.register`（内部即自动登录）
   * @param email 空串表示用户没填邮箱（后端 `email` 为 Optional，窗口层会转成 null）
   */
  public onRegister: AuthAction = (username: string, password: string, email: string): Promise<boolean> => {
    return Promise.resolve(false);
  };

  /** 点「已有账号？返回登录」· 窗口层负责出栈 */
  public onBackToLogin: () => void = () => {};

  // ── 预填值（从登录页跳过来时带上，push 之前写一次 → 普通字段）──

  /** 预填用户名 */
  public presetUsername: string = '';

  /** 预填密码 */
  public presetPassword: string = '';

  // ── 以下字段在页面挂载之后才会被回填 → 必须 `@Trace`（判定标准见 `LoginPageParam` 顶部）──

  /** 是否正在提交注册 */
  @Trace authBusy: boolean = false;

  /** 注册失败文案 · 直接展示后端 detail（如"用户名已存在""邮箱已被注册"） */
  @Trace authError: string = '';

  /** 失败弹窗标题 · 与登录页同一套（见 `LoginPageParam.authErrorTitle`） */
  @Trace authErrorTitle: string = '注册失败';

  /** 失败弹窗诊断行 · 与登录页同一套（见 `LoginPageParam.authErrorHint`） */
  @Trace authErrorHint: string = '';
}

// ══════════════════════════════════════════════════════════════════
//  三、主界面参数
// ══════════════════════════════════════════════════════════════════

/**
 * 主界面参数（`pages/MainPage.ets`）
 *
 * 主界面只做三件事：画底部导航栏、维护 `NavPathStack`、把每个页签的参数注入页面。
 * 它需要从外部拿到的只有：登录态、用户名、服务端地址。
 *
 * ★ 页签的名字与顺序**不在这里** —— 那是表现层常量，统一从 `pages/PageRoutes.ets`
 *   的 `MAIN_TABS` 读取，避免出现第二份"文案表"或第二份"顺序表"。
 */
export class MainPageParam extends PageParam {
  /** 是否已登录 · false 时主界面不渲染（窗口层会切成登录流） */
  public signedIn: boolean = false;

  /** 当前用户名 · 供"我的"页展示 */
  public userName: string = '';

  /** 服务端地址展示文案 · 形如 100.122.178.113:8000 */
  public serverLabel: string = '';

  /**
   * 登出回调 · 由 **`Index`（登录流窗口层）** 实现
   *
   * ★ 为什么放在这里而不是让 `MainPage` 自己调 `AuthStore.logout()`：
   *   登出之后要把"登录流的栈"复位到登录页（否则用户注册过的话，
   *   退出后会落在注册页上），而那个栈属于 `Index`。
   *   由 `Index` 统一实现「清登录态 + 复位登录栈 + 刷新界面」三件事，
   *   `MainPage` 只负责把「我的」页上的点击转过来。
   */
  public onLogout: () => Promise<void> = (): Promise<void> => {
    return Promise.resolve();
  };
}

// ══════════════════════════════════════════════════════════════════
//  四、五个一级页签的公共参数
// ══════════════════════════════════════════════════════════════════

/**
 * 一级页签页面的公共参数 · 工作台 / 素材库 / 历史报告 / 统计 四个页面直接用，
 * "我的"页继承它（见 `ProfilePageParam`）
 *
 * 为什么给占位页也定义参数（而不是让它们无参）：
 *   ① 页签高亮需要知道"当前是哪个页签"；
 *   ② 「下一步操作」「返回」这类动作要回到导航栈上执行，而页面**不允许**自己拿 UI 上下文，
 *      所以由窗口层把栈引用注入进来；
 *   ③ 下一轮接入真实数据时（`busy` / `errorMsg` 已在下面预留），
 *      只需在窗口层填字段，页面结构不用改。
 */
export class TabPageParam extends PageParam {
  /** 当前选中的页签 · 页面据此高亮自身、也用于埋点 */
  public activeTab: MainTab = MainTab.workbench;

  /** 是否正在加载 · true 时页面渲染骨架屏（规范：加载时显示骨架屏） */
  public busy: boolean = false;

  /** 错误文案 · 非空时页面渲染"错误 + 重试按钮"（规范：网络失败时提供重试按钮） */
  public errorMsg: string = '';

  /**
   * 导航栈引用 · 由窗口层注入（页面自己拿不到，也不该拿）
   * 供页面执行"返回""下一步跳转"等动作；为 null 时页面按钮降级为不可用。
   */
  public pathStack: NavPathStack | null = null;
}

/**
 * 素材库页参数（`pages/MediaLibraryPage.ets`）· 在页签公共参数上追加素材数据与动作回调
 *
 * ★ 数据与动作全部由窗口层（`pages/MainPage.ets`）从 `AppStore` 取好后注入，
 *   页面**不 import 任何 store**，只读参数 + 调回调。
 */
export class MediaLibraryPageParam extends TabPageParam {
  // ── 数据（只读展示）──

  /** 视频素材列表（已按「患者 + 类型」筛好，页面直接 ForEach） */
  public videos: MediaItemModel[] = [];

  /** 图片素材列表（已按「患者 + 类型」筛好） */
  public images: MediaItemModel[] = [];

  /** 去重后的患者名列表（含「未命名」占位）· 顶部筛选器用 */
  public patients: string[] = [];

  /** 当前选中的患者名（空串 = 全部患者） */
  public selectedPatient: string = '';

  /** 当前选中的素材 id（空串 = 未选中） */
  public selectedMediaId: string = '';

  /** 是否正在分析中 */
  public analyzing: boolean = false;

  // ── 动作回调 ──

  /** 点「上传」· 窗口层负责调起相册选择器并上传（内部弹患者命名输入框） */
  public onUpload: () => void = () => {};

  /** 点某个素材 · 窗口层负责触发分析（跳转目标后续再接） */
  public onOpenMedia: (mediaId: string) => void = (mediaId: string) => {};

  /** 点删除 · 窗口层负责二次确认 + 调删除接口 */
  public onDelete: (mediaId: string) => void = (mediaId: string) => {};

  /** 点「重试」· 窗口层负责重新拉取素材列表 */
  public onRetry: () => void = () => {};

  /** 切换患者筛选 · 窗口层负责改筛选并刷新列表 */
  public onSelectPatient: (patient: string) => void = (patient: string) => {};

  /** 给素材命名/改所属患者 · 窗口层负责弹输入框 + 调重命名接口 */
  public onRename: (mediaId: string) => void = (mediaId: string) => {};
}

/**
 * 历史报告页参数
 *
 * 报告列表与加载态直接读 `AppStore`（异步数据经参数传递不可靠）；
 * 本类只承载窗口层动作：刷新、筛选、打开已保存报告。
 */
export class ReportsPageParam extends TabPageParam {
  /** 拉取全部历史报告 */
  public onRefresh: () => Promise<void> = (): Promise<void> => {
    return Promise.resolve();
  };

  /** 应用筛选 · 空串表示全部 */
  public onFilter: (severity: string, mediaType: string) => Promise<void> =
    (severity: string, mediaType: string): Promise<void> => {
      return Promise.resolve();
    };

  /** 打开某条已保存报告 */
  public onOpenReport: (report: ReportListItemModel) => void = (report: ReportListItemModel) => {};
}

/**
 * "我的"页参数（`pages/ProfilePage.ets`）· 在页签公共参数上追加账户信息
 *
 * ══════════════════ 本轮（我的页搭建轮）契约变更 ══════════════════
 * 上一版这里只有 `userName` / `serverLabel` 两个字段，且 `onLogout` 明确"本轮不赋值"。
 * 本轮把"我的"页真正做出来，参数随之补齐：
 *   · 展示类：账号 id / 邮箱 / 注册日期 / 服务端地址 / 版本号（全部由窗口层从 store 取好再传）；
 *   · 动作类：`onLogout` 改为 **返回 Promise**，页面据此显示"正在退出…"并在完成后收尾。
 *
 * ★ 为什么展示字段不直接让页面读 store：页面纪律（不 import store）优先；
 *   "我的"页的数据是"进页面时一次性拿到"的静态投影，走参数契约没有 BUG-10/11 的风险。
 */
export class ProfilePageParam extends TabPageParam {
  /** 当前用户名 · 空串表示未取到（本页仍能正常渲染） */
  public userName: string = '';

  /** 邮箱 · 后端 `email` 可为 null，窗口层统一转成空串表示"未填写" */
  public email: string = '';

  /** 账号 id 文案（数字已转成字符串）· 便于报障时对上服务端 `users.id` */
  public accountId: string = '';

  /** 注册日期 "YYYY-MM-DD" · 未取到为空串 */
  public registeredAt: string = '';

  /** 服务端地址展示文案 · 形如 100.122.178.113:8000 */
  public serverLabel: string = '';

  /** 应用版本展示文案 · 形如 1.0.0(1000000) */
  public appVersion: string = '';

  /**
   * 登出回调 · 由窗口层实现（后端**没有**登出接口，登出 = 客户端删令牌）
   *
   * ★ 为什么返回 Promise：页面要据此显示"正在退出…"并禁用按钮。
   *   `AuthStore.logout()` 内部要做三件事（清令牌 / 清业务缓存 / 清内存），
   *   期间重复点击会重复清理，所以必须让页面等它。
   */
  public onLogout: () => Promise<void> = (): Promise<void> => {
    return Promise.resolve();
  };
}

// ══════════════════════════════════════════════════════════════════
//  五、工作台（一级页签，但参数比其它页签多得多，故单独一个类）
// ══════════════════════════════════════════════════════════════════

/**
 * 工作台参数（`pages/WorkbenchPage.ets`）
 *
 * ★★ 这个类**只承载动作回调，不承载展示数据** —— 与其它页面都不一样，原因：
 *   工作台的展示数据来自 `/health` 探活与 WebSocket，都是**异步到达**的。
 *   而页面是经 `Navigation.navDestination` 挂载的：改参数对象的字段**不会**让
 *   已挂载的页面重新收到新值（现象就是"点刷新圆点不变色，切页签回来才更新"）。
 *   所以工作台改为直接订阅 `AppStore`（`@ObservedV2` + `@Trace`，变更必定触发重绘），
 *   本类于是退化为"路由分发器用来识别页面 + 携带回调"的载体。
 *
 * ★ 为什么还要保留 `instanceof WorkbenchPageParam` 这条判断：
 *   `MainPage.destination` 需要按路由名+参数类型分发到正确的页面组件，
 *   回调也必须有个地方存（由窗口层注入一次、页面只读）。
 */
export class WorkbenchPageParam extends TabPageParam {
  // ── 动作回调（全部由窗口层实现） ──

  /** 点右上角刷新 / 离线横幅的「重试」· 窗口层调 `AppStore.checkHealth()` */
  public onRefresh: () => void = () => {};

  /** 点「选择素材」或「开始新的辅助评估」卡片 · 窗口层跳素材选择页 */
  public onSelectMedia: () => void = () => {};

  /** 点「当前任务」卡片 · 窗口层重新打开分析详情页 */
  public onOpenTask: () => void = () => {};

  /** 点「查看全部」· 窗口层切到历史报告页签 */
  public onViewAll: () => void = () => {};

  /** 点某条最近素材 · 窗口层按该素材的报告快照打开分析详情页（**不是**切到历史报告页签） */
  public onSelectRecent: (mediaId: string) => void = (mediaId: string) => {};
}

// ══════════════════════════════════════════════════════════════════
//  六、工作台二级页面
// ══════════════════════════════════════════════════════════════════

/**
 * 素材选择页参数（`pages/MediaPickerPage.ets`）
 *
 * 这一页负责"系统选择器 → 上传服务端"的完整动作，页面自己不碰网络与系统能力：
 *   - 点按钮   → 调 `onPickRequest`（窗口层决定用系统选择器还是别的方式）
 *   - 上传     → 调 `onUpload`（窗口层调 `MediaStore.uploadMedia`）
 *   - 上传成功 → 窗口层用 `replacePathByName` 把本页换成分析详情页（页面不碰路由栈）
 *
 * ══════════════════ ★★ 为什么**只有这一个**参数类是 `@ObservedV2` ══════════════════
 * 本页是**选完素材后页面自己要立刻变样**的页面：预览要出现、按钮要从「选择素材」变成
 * 「开始分析」、上传态要亮、错误文案要显示。而这些字段是窗口层在
 * `await 系统选择器 / await 上传请求` **之后**才回填的 —— 也就是**页面已经挂载着**的时候。
 *
 * 参数对象是经 `Navigation.navDestination` 传进页面的：它不是 `@ObservedV2` 的话，
 * 改字段**不会**让已挂载的页面收到新值（这是本工程 BUG-10 的同一条根因）。
 * 实测现象就是 BUG-11：选完图片，页面一点变化都没有 —— "等于没选"。
 *
 * 其它参数类（登录 / 注册 / 页签 / 详情页）的字段都是"push 之前写一次、页面挂载后不再变"，
 * 页面靠自己的 `@Local` + 回调就能跑起来，所以**不要**给它们也加装饰
 * —— 装饰器不是免费的，它会给每次字段写入都挂一层观察者。
 */
@ObservedV2
export class MediaPickerPageParam extends PageParam {
  /** 页面标题（固定文案也走参数，方便将来改口径） */
  public title: string = '选择素材';

  /** 点「选择素材」· 窗口层打开系统选择器，返回是否选到了东西 */
  public onPickRequest: () => Promise<boolean> = (): Promise<boolean> => {
    return Promise.resolve(false);
  };

  /** 点「开始上传」· 窗口层调 MediaStore.uploadMedia；返回 true 表示上传成功（已跳转） */
  public onUpload: () => Promise<boolean> = (): Promise<boolean> => {
    return Promise.resolve(false);
  };

  /** 返回工作台 · 窗口层出栈 */
  public onBack: () => void = () => {};

  // ── 以下字段会被窗口层在页面挂载后改动，必须 `@Trace` 才会刷新界面 ──

  /** 是否已有选中的素材（决定是否显示预览与上传按钮） */
  @Trace hasPicked: boolean = false;

  /** 已选素材的展示名 */
  @Trace pickedName: string = '';

  /** 已选素材是否为视频（预览区据此显示播放图标而非缩略图） */
  @Trace pickedIsVideo: boolean = false;

  /** 已选素材的本地 URI · 图片可直接喂 `Image` 预览 */
  @Trace pickedUri: string = '';

  /** 是否正在上传 */
  @Trace uploading: boolean = false;

  /** 错误文案 · 非空即展示（含"格式不支持""上传失败"） */
  @Trace errorMsg: string = '';
}

/**
 * 分析详情页参数（`pages/AnalysisDetailPage.ets`）
 *
 * ══════════════════ ★★ 本轮（分析页实装轮）契约变更 ══════════════════
 * 旧实现把**实时数据也塞进参数**（`followLiveTask` / `status` / `progress` / `bdiScore` /
 * `severityLabel` / `severityColor` / `vlmText` / `frameCount`），再由窗口层的
 * `syncDetailParam()` 从 `AppStore` 抄一遍。那条链路有两个死结：
 *   ① `syncDetailParam()` 只在"切页签 / 入栈"时被调用，**WS 每来一帧不会触发它**
 *      → 分析跑完了，档位标签与智能解读也永远不出现（BUG-15），帧数还停在 0；
 *   ② "实时 / 历史快照"靠一个布尔开关区分，可真正的判据是"这条素材是不是当前会话"。
 *
 * 现在参数只承载**入栈那一刻就确定**的信息（素材元信息 + 报告回落值 + 回调），
 * 页面自己按 `mediaId` 从 `AppStore` 的 `@Trace` 会话里读实时数据：
 *   `AppStore.analysisSessionOf(pageParam.mediaId)`
 *     · 有  → 用会话（实时进行中 / 刚跑完 / 本机归档，三者同一条数据形状）；
 *     · 没有 → 回落到本参数里的报告分数（并提示"本机未保留逐帧数据"）。
 * `syncDetailParam()` 已整体删除，页面不再有两份真相。
 */
export class AnalysisDetailPageParam extends PageParam {
  /** 要展示的素材 id · 页面按它去取**该素材自己的**分析会话（绝不跨素材兜底） */
  public mediaId: string = '';

  /** 素材名 */
  public mediaName: string = '';

  /**
   * 素材类型 · 图片/视频的全部展示语义（单帧还是逐帧、直线还是折线、刻度尺还是饼图）
   * 都由它决定，所以必须显式传，不能靠"猜"
   */
  public mediaType: MediaType = MediaType.image;

  /** 该素材最近一次报告里的 BDI 分数（没有本机会话时的回落值；0 = 没有报告） */
  public reportScore: number = 0;

  /** 该素材最近一次分析时间（"YYYY-MM-DD HH:mm:ss"，空串 = 没有报告） */
  public reportTime: string = '';

  /** 点返回 · 窗口层出栈（**不停分析**，分析在 AppStore 上继续跑） */
  public onBack: () => void = () => {};

  /** 点「取消分析」· 窗口层调 AppStore.cancelAnalysis（★ 视频场景基本无效，按钮要弱化） */
  public onCancelAnalysis: () => void = () => {};

  /**
   * 点「重新分析」· 窗口层对**同一素材**重新起一次分析
   *
   * ★ 这是"本机没有逐帧数据"（App 重启后打开历史素材 / 归档被淘汰）时的出口：
   *   重新分析会覆盖该素材自己的会话，页面因 `analysisLiveMediaId === mediaId` 变真
   *   而自动切到实时数据，**不需要重新入栈**。
   */
  public onReanalyze: () => void = () => {};
}

