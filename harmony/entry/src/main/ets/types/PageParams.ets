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

import { TaskStatus } from './enums';
import { CurrentTaskModel, RecentMediaModel } from './model';

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
 */
export class LoginPageParam extends PageParam {
  // ── 动作回调 ──

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

  // ── 忙碌态 ──

  /** 是否正在鉴权（按钮禁用 + 文案变"登录中…"） */
  public authBusy: boolean = false;

  // ── 错误文案 ──

  /**
   * 鉴权失败文案 · 非空即展示（含"登录已过期，请重新登录"这类冷启动文案）
   * ★ 页面自行遵守一条显示规则：用户重新输入后，这条错误会被收起；
   *   窗口层不需要为此做任何事（详见 `docs/鸿蒙端页面框架与路由说明.md` 3.3 节）。
   */
  public authError: string = '';

  // ── 连接兜底 ──

  /** 非空时在底部显示"错误 + 重新连接服务端"（网络不可达 / 服务端未启动） */
  public retryMessage: string = '';

  /** 是否正在探活重连 */
  public retrying: boolean = false;
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
 */
export class RegisterPageParam extends PageParam {
  // ── 动作回调 ──

  /**
   * 点「注册」· 窗口层负责调 `AuthStore.register`（内部即自动登录）
   * @param email 空串表示用户没填邮箱（后端 `email` 为 Optional，窗口层会转成 null）
   */
  public onRegister: AuthAction = (username: string, password: string, email: string): Promise<boolean> => {
    return Promise.resolve(false);
  };

  /** 点「已有账号？返回登录」· 窗口层负责出栈 */
  public onBackToLogin: () => void = () => {};

  // ── 忙碌态 ──

  /** 是否正在提交注册 */
  public authBusy: boolean = false;

  // ── 错误文案 ──

  /** 注册失败文案 · 直接展示后端 detail（如"用户名已存在""邮箱已被注册"） */
  public authError: string = '';

  // ── 预填值（从登录页跳过来时带上，减少重复输入） ──

  /** 预填用户名 */
  public presetUsername: string = '';

  /** 预填密码 */
  public presetPassword: string = '';
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
 * "我的"页参数（`pages/ProfilePage.ets`）· 在页签公共参数上追加只读展示文案
 */
export class ProfilePageParam extends TabPageParam {
  /** 当前用户名 · 空串表示未取到（本页仍能正常渲染） */
  public userName: string = '';

  /** 服务端地址展示文案 · 形如 100.122.178.113:8000 */
  public serverLabel: string = '';

  /** 登出回调 · 本轮不赋值（留空即不显示登出入口，用户已确认本轮不做登出） */
  public onLogout: () => void = () => {};
}

// ══════════════════════════════════════════════════════════════════
//  五、工作台（一级页签，但参数比其它页签多得多，故单独一个类）
// ══════════════════════════════════════════════════════════════════

/**
 * 工作台参数（`pages/WorkbenchPage.ets`）
 *
 * ★ 为什么在 `TabPageParam` 之外单开一个类，而不是往 `TabPageParam` 里塞字段：
 *   `TabPageParam` 是五个页签的公共契约，往里加"最近素材/当前任务"会让
 *   素材库、统计等页面白背一堆用不到的字段。工作台需要什么就继承后自己加。
 *
 * ★ 与上一轮占位页的差异：原注释说"本轮没有数据源，因此不渲染加载态"，
 *   本轮已接入 `AppStore`，所以 `busy` / `errorMsg` 开始真正被使用
 *   （离线横幅与最近素材的空态就是它们驱动的）。
 */
export class WorkbenchPageParam extends TabPageParam {
  // ── 服务状态 ──

  /** 服务端是否在线（绿色圆点 / 红色圆点） */
  public serverOnline: boolean = false;

  /** 服务状态文案（"在线" / "未连接"） */
  public serverStatusLabel: string = '未连接';

  /** 是否正在探活（刷新按钮忙碌态） */
  public healthChecking: boolean = false;

  /** 服务端地址展示 · 形如 100.122.178.113:8000 */
  public serverLabel: string = '';

  // ── 当前任务 ──

  /** 当前任务 · null 表示「暂无进行中的分析」 */
  public currentTask: CurrentTaskModel | null = null;

  // ── 最近使用的素材 ──

  /** 最近 2 条素材（含分数与严重度进度条） */
  public recentItems: RecentMediaModel[] = [];

  /** 最近素材是否仍在加载（首次进入且无缓存时才有意义） */
  public recentLoading: boolean = false;

  /** 最近素材加载失败文案 · 非空即展示 */
  public recentError: string = '';

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
 *   - 上传成功 → 窗口层负责本页内刷新状态 + 跳转分析详情页（页面不碰路由栈）
 */
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

  /** 是否已有选中的素材（决定是否显示预览与上传按钮） */
  public hasPicked: boolean = false;

  /** 已选素材的展示名 */
  public pickedName: string = '';

  /** 已选素材是否为视频（预览区据此显示播放图标而非缩略图） */
  public pickedIsVideo: boolean = false;

  /** 已选素材的本地 URI · 图片可直接喂 `Image` 预览 */
  public pickedUri: string = '';

  /** 是否正在上传 */
  public uploading: boolean = false;

  /** 错误文案 · 非空即展示（含"格式不支持""上传失败"） */
  public errorMsg: string = '';
}

/**
 * 分析详情页参数（`pages/AnalysisDetailPage.ets`）· **本轮为占位页**
 *
 * 折线图 / 饼图 / 热力图组件尚未实现，所以本页只放：
 *   - 素材名与类型（证明跳转链路通了）
 *   - 真实的分析进度与实时分数（数据来自 WS，不是假数据）
 *   - 明确的"图表区待实现"占位块
 *
 * ★ 状态语义：`status` 直接取 `TaskStatus`，页面按它决定显示
 *   「分析中 / 已完成 / 失败」三种文案，不去读 `AppStore.analyzing`。
 */
export class AnalysisDetailPageParam extends PageParam {
  /**
   * 本页数据是否**跟随当前正在跑的分析任务**（窗口层每次同步都会覆盖本页字段）
   *
   * ★ true  → 从工作台「当前任务」进入：进度/分数随 WS 实时刷新；
   * ★ false → 从「最近使用的素材」进入历史快照：本页字段是**冻结**的一次性投影，
   *           窗口层的 `syncDetailParam()` 会直接跳过本页，不再覆盖。
   *   没有这个开关的话，查看历史素材时页面会被"当前任务"的数据反复改写 —— 本轮修掉的 bug 之一。
   */
  public followLiveTask: boolean = true;

  /** 素材 id（当前任务 id） */
  public mediaId: string = '';

  /** 素材名 */
  public mediaName: string = '';

  /** 素材类型中文（"图片" / "视频"） */
  public mediaTypeLabel: string = '';

  /** 任务状态 */
  public status: TaskStatus = TaskStatus.none;

  /** 分析进度 0–1 */
  public progress: number = 0;

  /** 已收到帧数（占位区用来证明数据在流动） */
  public frameCount: number = 0;

  /** 最新 BDI 分数（0 表示还没出分） */
  public bdiScore: number = 0;

  /** 分数档位中文标签（"正常"/"轻度"/"中度"/"重度"）· 分数为 0 时为空串 */
  public severityLabel: string = '';

  /** 分数档位颜色 */
  public severityColor: string = '';

  /** 服务端 VLM 文本解读 · 可能一直为空（不是所有素材都会触发） */
  public vlmText: string = '';

  /** 错误文案 · 非空即展示 */
  public errorMsg: string = '';

  /** 点返回 · 窗口层出栈（**不停分析**，分析在 AppStore 上继续跑） */
  public onBack: () => void = () => {};

  /** 点「取消分析」· 窗口层调 AppStore.cancelAnalysis（★ 视频场景基本无效，按钮要弱化） */
  public onCancelAnalysis: () => void = () => {};
}

