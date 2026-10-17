/**
 * AppStore · 面向 UI 的**统一门面**（UI 只跟它打交道）
 *
 * 设计要点：
 *  1. **单一读数入口**：页面写 `AppStore.get().mediaItems` 就能拿到媒体列表，
 *     不需要知道数据来自网络、RDB 还是内存。
 *  2. **状态镜像**：门面把各领域 store 里会被 UI 读的字段用 `@Trace` 重新声明一遍，
 *     调用 `sync()` 拉平。这样 UI 只需 `@Computed` 一个对象，改一个字段就刷新。
 *  3. **编排而不持有业务**：拉取、落盘、清理都在各自 store / DAO 里，
 *     门面只做「什么时候按什么顺序调谁」。
 *  4. **零循环依赖**：门面 → 领域 store → 数据层，单向；领域 store 之间不互相 import。
 *
 * 典型用法见 docs/鸿蒙端数据获取使用指南.md。
 */

import { ApiConfig, NetConfig } from '../common/ApiConfig';
import { Logger } from '../common/Logger';
import { HttpClient } from '../network/HttpClient';
import { StorageManager } from '../persistence/StorageManager';
import {
  ActionResultModel, AnalysisFrameModel, AnalysisSessionModel, BootPhase, BdiThreshold, CurrentTaskModel,
  BDI_MAX_SCORE, MediaItemModel, MediaType, normalizeMediaId, RecentMediaModel, ReportListItemModel,
  SeverityBucketModel, SocketState, StatsModel, TaskStatus, UiConstant, UserModel,
  WorkbenchAssessmentModel
} from '../types/Index';
import { AnalysisState, AppState, AuthState, MediaState, ReportState, StatsState } from '../types/storeState';
import { AnalysisStateHolder } from './AnalysisStateHolder';
import { AuthStore } from './AuthStore';
import { MediaStore } from './MediaStore';
import { ReportStore } from './ReportStore';
import { StatsStore } from './StatsStore';

/** 面向 UI 的统一门面 · 集中对外接口在顶部 */
@ObservedV2
export class AppStore {
  // ══════════════════ 对外字段（UI 直接读）══════════════════

  /** 启动阶段 · UI 据此决定显示骨架屏 / 登录页 / 内容页 */
  @Trace bootPhase: BootPhase = BootPhase.idle;

  /** 是否处于离线兜底（本地有数据、网络不可达） */
  @Trace offline: boolean = false;

  /**
   * 服务端连通性快照 · 工作台的"服务状态"圆点用它
   *
   * ★ 为什么不直接用 `offline`：`offline` 的判据是"媒体/报告/统计**三个**领域都失败"
   *   （见 `detectOffline`），属于"数据能否离线兜底"的语义；
   *   而工作台要回答的是"后端此刻是否在线"，应当以 `/health` 探活为准。
   *   两个概念分开，避免把"某个接口失败"误报成"服务端掉线"。
   */
  @Trace serverOnline: boolean = false;

  /** 服务状态文案（"在线" / "未连接"）· 由探活结果写入 */
  @Trace serverStatusLabel: string = '未连接';

  /** 是否正在探活（刷新按钮的忙碌态） */
  @Trace healthChecking: boolean = false;

  /**
   * 是否**至少完成过一次**探活
   *
   * ★ 为什么需要它：`serverOnline` 的默认值是 false，若 UI 只看 `!serverOnline`，
   *   冷启动那几十毫秒里会闪一条"无法连接服务器"的假告警。
   *   加上这个位，工作台的离线提示只在"真的探活过、并且失败了"时才出现。
   */
  @Trace healthChecked: boolean = false;

  /** 全局提示（如「登录已过期，请重新登录」）· 消费后请调用 clearGlobalMessage() */
  @Trace globalMessage: string = '';

  /** 当前服务端地址（设置页展示 / 修改） */
  @Trace serverHost: string = '';
  @Trace serverPort: number = 0;

  // ── 登录态镜像 ──
  @Trace signedIn: boolean = false;
  @Trace currentUser: UserModel | null = null;

  // ── 媒体库镜像 ──
  @Trace mediaItems: MediaItemModel[] = [];
  @Trace mediaLoading: boolean = false;
  @Trace mediaError: string = '';

  // ── 报告列表镜像 ──
  @Trace reportItems: ReportListItemModel[] = [];
  @Trace reportTotal: number = 0;
  @Trace reportHasMore: boolean = false;
  @Trace reportLoading: boolean = false;
  @Trace reportLoadingMore: boolean = false;
  @Trace reportError: string = '';

  // ── 统计镜像 ──
  @Trace statsSummary: StatsModel | null = null;
  @Trace statsBuckets: SeverityBucketModel[] = [];
  @Trace statsLoading: boolean = false;

  // ── 分析会话镜像 ──
  /**
   * ★★ 这些字段是"**live 会话指针对**的一次性投影"，只有 `sync()` 被调用时才刷新。
   *   逐帧数据（帧 / 分数）**不在这里**：它们由 `analysisSessionsOf()` /
   *   `analysisSessionOf()` 直接返回桥接器里 `@Trace` 的那个数组，
   *   于是每来一帧都能实时刷新，不依赖 `sync()` 的调用时机
   *   （这条纪律与本项目 BUG-10/BUG-15 同源：异步数据不要靠"父组件改参数"刷新）。
   */
  @Trace analyzing: boolean = false;
  @Trace analysisProgress: number = 0;
  @Trace analysisScore: number = 0;
  @Trace analysisFrameCount: number = 0;
  @Trace analysisLastFrame: AnalysisFrameModel | null = null;
  @Trace analysisVlmText: string = '';
  @Trace analysisError: string = '';
  @Trace socketState: SocketState = SocketState.idle;

  // ── 工作台「当前任务」镜像（★ 仅内存，重启 App 即消失，用户本轮确认不做持久化）──
  /** 当前任务的素材 id · 空串表示没有任务 */
  @Trace currentTaskMediaId: string = '';
  /** 当前任务的素材名（展示用） */
  @Trace currentTaskMediaName: string = '';
  /** 当前任务的素材类型（图片 / 视频） */
  @Trace currentTaskMediaType: MediaType = MediaType.image;
  /** 当前任务状态（none / running / done / failed） */
  @Trace currentTaskStatus: TaskStatus = TaskStatus.none;
  /** 当前任务最终分数（done 后才有值） */
  @Trace currentTaskScore: number = 0;
  /** 当前任务失败文案（status = failed 时非空） */
  @Trace currentTaskError: string = '';

  /**
   * 当前任务是否来自「重启后恢复的上一次评估」
   * ★ 只影响展示文案与阶段轨：恢复的评估显示「最近一次评估 / 上次分析 · 时间」，
   *   不画实时阶段轨；一旦开始新的分析就置回 false。
   */
  @Trace currentTaskRestored: boolean = false;

  // ══════════════════ 单例 ══════════════════

  private static instance: AppStore | null = null;

  public static get(): AppStore {
    if (AppStore.instance === null) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  private readonly log = Logger.scope('AppStore');
  private readonly domainMedia: MediaStore = MediaStore.get();
  private readonly domainReport: ReportStore = ReportStore.get();
  private readonly domainStats: StatsStore = StatsStore.get();
  private readonly domainAuth: AuthStore = AuthStore.get();
  private analysisHolder: AnalysisStateHolder | null = null;

  private constructor() {
    // 登出时顺带清业务缓存，避免换账号看到上一个用户的数据
    this.domainAuth.setCleanup(async (): Promise<void> => {
      await StorageManager.clearBusinessCache();
      this.clearAll();
      this.bootPhase = BootPhase.anonymous;
      this.sync();
    });
    // 401 全局处理：任何 REST 请求拿到 401 都会走这里（JWT 7 天且无 refresh）
    HttpClient.onUnauthorized((message: string): void => {
      this.handleUnauthorized(message);
    });

    // ★★ 提前建好分析桥接器（BUG-23 的修复 · 不建立任何网络连接）
    //
    // 工作台主页在"本次启动还没有开始过分析"时就会读会话归档。旧实现里
    // `analysisHolder` 是懒建的，此时 `analysisSessionOf()` 会**提前 return null**，
    // 页面的 `@Computed session` 首次求值因此**没有读到** `AnalysisState.sessions`
    // 这个 @Trace 数组。等用户点「重新分析」写入会话时，这个 Computed 不会失效，
    // 页面就一直显示"本机无逐帧数据 / 等待推理数据"，而日志里分析其实已经跑完。
    // （真机复现：hero 停在"分析中 0%"，完成后热力图也不出现；切页签重建页面才恢复。）
    //
    // `AnalysisSocket` 的构造函数只保存 listener，`start()` 才会 openSocket，
    // 所以提前建桥接器不会在未登录时发起任何连接；登出时 `clearAll()` 仍会 stop + 清会话。
    this.analysis();
  }

  // ══════════════════ 领域 store 访问器（需要调用方法时用）══════════════════

  /** 登录态 store（login / register / logout 等方法在它身上） */
  public auth(): AuthStore {
    return this.domainAuth;
  }

  /** 媒体库 store */
  public media(): MediaStore {
    return this.domainMedia;
  }

  /** 报告 store */
  public reports(): ReportStore {
    return this.domainReport;
  }

  /** 统计 store */
  public statsStore(): StatsStore {
    return this.domainStats;
  }

  /**
   * 分析桥接器
   * ★ 在 `AppStore` 构造函数里就已经建好（见 constructor 的 BUG-23 说明）：
   *   构造本身不建立网络连接，只保证页面第一次读会话归档时能读到 @Trace 的
   *   `sessions` 数组，后续写入才会触发重算。
   */
  public analysis(): AnalysisStateHolder {
    if (this.analysisHolder === null) {
      const state: AnalysisState = new AnalysisState();
      this.analysisHolder = new AnalysisStateHolder(state, async (): Promise<void> => {
        await this.onAnalysisFinished();
      });
    }
    return this.analysisHolder;
  }

  // ══════════════════ 生命周期 ══════════════════

  /**
   * 启动引导 · 由 `AppBootstrap` 调用，UI 不要直接调
   *
   * 时序（对应交接文档第六节）：
   *   ① StorageManager.init      preferences + RDB 建表
   *   ② ApiConfig.load           读回 host/port/token（在 StorageManager 内完成）
   *   ③ 冷启动预热               从 RDB 灌内存，UI 立刻有数据
   *   ④ AuthStore.restore        有 token 则校验 /me
   *   ⑤ 并发拉 media / reports / stats
   *   ⑥ 失败/无 token            标记未登录或离线，UI 照常渲染
   */
  public async boot(): Promise<void> {
    this.bootPhase = BootPhase.preparing;
    this.refreshServerInfo();
    this.sync();

    // ③ 冷启动预热：先给 UI 数据，再谈联网
    const mediaWarm: boolean = await this.domainMedia.warmUp();
    const reportWarm: boolean = await this.domainReport.warmUp();
    const statsWarm: boolean = await this.domainStats.warmUp();
    this.sync();
    this.log.i(`冷启动预热 · 媒体=${mediaWarm} 报告=${reportWarm} 统计=${statsWarm}`);

    // ④ 校验令牌
    const restored: boolean = await this.domainAuth.restore();
    this.sync();
    if (!restored) {
      this.bootPhase = BootPhase.anonymous;
      if (this.domainAuth.errorMsg.length > 0) {
        this.globalMessage = this.domainAuth.errorMsg;
      }
      this.log.i('无有效登录态 · 停在未登录阶段');
      return;
    }

    // ⑤ 并发拉取（任一失败不清空已有缓存）
    await this.loadAll();
    this.bootPhase = BootPhase.authenticated;
    this.sync();
  }

  /**
   * 并发拉取媒体 / 报告 / 统计
   * 登录成功后由 UI 调用（`await AppStore.get().loadAll()`），也可主动下拉刷新。
   */
  public async loadAll(): Promise<void> {
    await Promise.all([
      this.domainMedia.refresh(),
      this.domainReport.refresh(),
      this.domainStats.refresh()
    ]);
    this.offline = this.detectOffline();
    this.sync();
    // ★ 引导完成/登录成功后恢复上一次评估（工作台 hero + 分析区原样还原）
    await this.restoreAssessment();
  }

  /** 主动刷新单个领域（下拉刷新按页调用，比全量刷新省流量） */
  public async refreshMedia(): Promise<void> {
    await this.domainMedia.refresh();
    this.offline = this.detectOffline();
    this.sync();
  }

  /** 主动刷新报告列表（沿用当前筛选条件） */
  public async refreshReports(): Promise<void> {
    await this.domainReport.refresh();
    this.offline = this.detectOffline();
    this.sync();
  }

  /** 主动刷新统计 */
  public async refreshStats(): Promise<void> {
    await this.domainStats.refresh();
    this.offline = this.detectOffline();
    this.sync();
  }

  /**
   * 分析收尾：**先持久化评估**，再刷新统计/报告/媒体
   *
   * ★ 持久化放在刷新之前：刷新要走网络，离线或慢网时可能拖很久；
   *   评估一旦收尾就应该立刻落盘，避免用户在等待刷新时杀掉 App 丢结果。
   */
  public async onAnalysisFinished(): Promise<void> {
    // 先把 holder 的 done/finalScore 折进 currentTask 镜像，落盘时才是 done + 最终分
    this.sync();
    await this.persistAssessment();
    await this.domainStats.refresh();
    await this.domainReport.refresh();
    await this.domainMedia.refresh();
    this.sync();
  }

  /** 清空全部门面状态（登出、缓存清理时调用） */
  public clearAll(): void {
    this.domainMedia.clear();
    this.domainReport.clear();
    this.domainStats.clear();
    this.analysisHolder?.stop();
    // ★ 换账号后不能看到上一个用户的分析结果：归档会话一并清掉
    this.analysisHolder?.clearSessions();
    // 换账号后不该看到上一个用户的任务
    this.clearCurrentTask();
    this.sync();
  }

  // ══════════════════ 状态镜像 ══════════════════

  /**
   * 把各领域 store 的状态拉平到门面上 · **每次改完子 store 都要调一次**
   * 页面里 `await AppStore.get().refreshMedia()` 之后不需要手动调，上面几个 refresh 已经代劳。
   */
  public sync(): void {
    // 登录态
    this.signedIn = this.domainAuth.signedIn;
    this.currentUser = this.domainAuth.user;

    // 媒体库
    this.mediaItems = this.domainMedia.items;
    this.mediaLoading = this.domainMedia.loading;
    this.mediaError = this.domainMedia.errorMsg;

    // 报告
    this.reportItems = this.domainReport.items;
    this.reportTotal = this.domainReport.total;
    this.reportHasMore = this.domainReport.hasMore;
    this.reportLoading = this.domainReport.loading;
    this.reportLoadingMore = this.domainReport.loadingMore;
    this.reportError = this.domainReport.errorMsg;

    // 统计
    this.statsSummary = this.domainStats.data;
    this.statsBuckets = this.domainStats.buckets;
    this.statsLoading = this.domainStats.loading;

    // 分析会话（桥接器可能还没建，此时保持默认值）
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    if (holder !== null) {
      this.analyzing = holder.isRunning();
      this.analysisError = holder.errorOf();
      this.analysisProgress = holder.progressOf();
      this.analysisScore = holder.scoreOf();
      this.analysisFrameCount = holder.frameCountOf();
      this.analysisLastFrame = holder.lastFrameOf();
      this.analysisVlmText = holder.vlmTextOf();
      this.socketState = holder.socketStateOf();
      this.syncCurrentTask(holder);
    }
  }

  // ══════════════════ 工作台：当前任务 ══════════════════

  /**
   * 记录"开始一次新分析"· 由窗口层在**上传成功后、启动 WS 之前**调用
   * 此后工作台的 hero 就能显示它，即使用户不在分析区所在的位置。
   */
  public setCurrentTask(mediaId: string, mediaName: string, mediaType: MediaType): void {
    this.currentTaskMediaId = normalizeMediaId(mediaId);
    this.currentTaskMediaName = mediaName;
    this.currentTaskMediaType = mediaType;
    this.currentTaskStatus = TaskStatus.running;
    this.currentTaskScore = 0;
    this.currentTaskError = '';
    // 新任务开始：不再处于"上次评估"的展示态；完成后再由持久化覆盖旧记录
    this.currentTaskRestored = false;
    this.sync();
  }

  /**
   * 当前任务快照 · 没有任务时返回 null
   * ★ 页面只读这个投影对象，不必自己访问 `analysis()`
   * ★ 进度与分数**优先取该素材自己的会话**：镜像字段只在 `sync()` 时刷新，
   *   而会话是 `@Trace` 的，每来一帧都变 —— 工作台进度条因此真正"动起来"
   *   （旧实现只看镜像字段，进度会一直停在开始分析那一刻）。
   * ★ 首帧照片、BDI 填充比例、档位色也在这里一起算好：卡片组件只负责画，
   *   不再自己判断"该用会话还是镜像、该退到缩略图还是占位块"。
   */
  public currentTask(): CurrentTaskModel | null {
    if (this.currentTaskStatus === TaskStatus.none || this.currentTaskMediaId.length === 0) {
      return null;
    }
    const session: AnalysisSessionModel | null = this.analysisSessionOf(this.currentTaskMediaId);
    const progress: number = session === null ? this.analysisProgress : session.progress;
    const score: number =
      session !== null ? session.score : (this.currentTaskStatus === TaskStatus.done ? this.currentTaskScore : this.analysisScore);
    const level = BdiThreshold.levelOf(score);
    const task: CurrentTaskModel = {
      mediaId: this.currentTaskMediaId,
      mediaName: this.currentTaskMediaName,
      mediaType: this.currentTaskMediaType,
      status: this.currentTaskStatus,
      progress: progress,
      bdiScore: score,
      errorMsg: this.currentTaskError,
      // ★ 首帧取数与「查看历史素材」共用同一套逻辑（公开入口见 firstFrameUrlOfMedia）
      firstFrameUrl: this.firstFrameUrlOf(this.currentTaskMediaId, session),
      // 条长 = 分数 / 满分（工作台统一的严重度口径：越长越严重）
      scoreRatio: score <= 0 ? 0 : (score >= BDI_MAX_SCORE ? 1 : score / BDI_MAX_SCORE),
      // 没出分时不能说"正常"：给空标签 + 中性色，避免把"还没算"读成"结果正常"
      severityLabel: score > 0 ? UiConstant.severityLabelOf(level) : '',
      // ★ 中性色取 `UiConstant`（数据层常量）而不是 `UiTheme`：门面不该 import 表现层主题，
      //   两者色值一致（#64748b），语义上这里只是"本档位无结论"的占位。
      severityColor: score > 0 ? UiConstant.severityColorOf(level) : UiConstant.textSecondaryColor
    };
    return task;
  }

  /**
   * 任意素材的首帧照片地址（工作台 hero / 历史素材查看共用）
   *
   * ① 会话里的**首帧对齐人脸**优先（图片=那唯一一帧，视频=采样出的第一帧）；
   * ② 首帧还没到、但媒体库有缩略图（图片上传后后端会生成）→ 用缩略图顶上，
   *    这样"刚上传、还在等第一帧"的卡片也能立刻有画面；
   * ③ 视频没有缩略图，且帧还没到 → 空串，由组件画占位块（不拿 .mp4 直链喂 Image）。
   *
   * ★ 只在**图片**上退到缩略图：视频的 `thumbnailUrl` 会回落到 `item.url`（一个 .mp4 地址），
   *   `Image` 组件吃它只会得到一片空白，反而掩盖了"帧还没到"这件事。
   * ★ 按 mediaId 取**该素材自己的**会话；取不到就退到图片缩略图/占位，
   *   绝不拿别的素材的首帧顶替（与 BUG-14 的根因相对）。
   */
  public firstFrameUrlOfMedia(mediaId: string): string {
    const normalized: string = normalizeMediaId(mediaId);
    if (normalized.length === 0) {
      return '';
    }
    return this.firstFrameUrlOf(normalized, this.analysisSessionOf(normalized));
  }

  /** 首帧取数的内部实现 · 允许调用方传入已取好的会话来省一次查找 */
  private firstFrameUrlOf(mediaId: string, session: AnalysisSessionModel | null): string {
    if (session !== null && session.firstFrameFace.length > 0) {
      const raw: string = session.firstFrameFace;
      return raw.startsWith('data:') ? raw : `data:image/jpeg;base64,${raw}`;
    }
    const media: MediaItemModel | null = this.domainMedia.findById(normalizeMediaId(mediaId));
    if (media === null || media.type !== MediaType.image) {
      return '';
    }
    return this.domainMedia.thumbnailUrl(media);
  }

  /** 清掉当前任务（工作台「清除」按钮 / 登出时调用） */
  public clearCurrentTask(): void {
    this.currentTaskMediaId = '';
    this.currentTaskMediaName = '';
    this.currentTaskStatus = TaskStatus.none;
    this.currentTaskScore = 0;
    this.currentTaskError = '';
    this.currentTaskRestored = false;
  }

  // ══════════════════ 工作台：当前评估持久化 ══════════════════

  /** 当前用户归属 key（持久化载荷校验，避免换号串数据） */
  private userKeyOf(user: UserModel): string {
    return `${user.id}`;
  }

  /**
   * 持久化「当前评估」：当前任务元信息 + 该素材的最终分析会话
   *
   * ★ 只在 `done` 时落盘：
   *   · running 态落盘会在重启后留下永远"分析中 42%"的幽灵任务；
   *   · failed 不落盘，保留上一次成功评估更有用。
   * ★ 会话包含逐帧人脸 base64 与 16×16 热度矩阵（最多 30 帧，约 0.5MB），
   *   所以放 RDB 的整包 JSON，而不是 preferences 小配置。
   * ★ 任何异常都不打断分析收尾（日志留痕即可）。
   */
  public async persistAssessment(): Promise<void> {
    const user: UserModel | null = this.currentUser;
    if (user === null) {
      return;
    }
    const task: CurrentTaskModel | null = this.currentTask();
    if (task === null || task.status !== TaskStatus.done) {
      return;
    }
    const session: AnalysisSessionModel | null = this.analysisSessionOf(task.mediaId);
    const payload: WorkbenchAssessmentModel = {
      version: 1,
      userKey: this.userKeyOf(user),
      savedAt: Date.now(),
      mediaId: task.mediaId,
      mediaName: task.mediaName,
      mediaType: task.mediaType,
      status: task.status,
      score: task.bdiScore,
      error: task.errorMsg,
      session: session
    };
    try {
      const json: string = JSON.stringify(payload);
      const ok: boolean = await StorageManager.assessmentDao().save(json, payload.savedAt);
      this.log.i(
        `评估已持久化 · mediaId=${payload.mediaId} 会话=${session === null ? '无' : '有'} ok=${ok}`
      );
    } catch (err) {
      this.log.e('评估持久化失败', err as Object);
    }
  }

  /**
   * 恢复上一次评估（App 启动 / 登录成功后由 `loadAll()` 调用）
   *
   * 顺序：
   *   ① 校验 RDB 载荷存在、版本与 userKey 匹配（换号/旧版本直接丢弃）；
   *   ② 写回当前任务镜像（mediaId / name / type / status / score / error）；
   *   ③ 把最终会话注入桥接器归档（热力图/曲线/严重度/VLM 全部回来）；
   *   ④ `sync()` 让门面镜像与 currentTask 投影一致。
   *
   * ★ 恢复出来的不是 live 会话：无取消按钮、无实时进度；页面会按
   *   `currentTaskRestored` 显示「最近一次评估 / 上次分析 · 时间」。
   * ★ 若本次会话已经开始了新任务（currentTaskMediaId 非空），不覆盖。
   */
  public async restoreAssessment(): Promise<void> {
    const user: UserModel | null = this.currentUser;
    if (user === null || this.currentTaskMediaId.length > 0) {
      return;
    }
    const json: string = await StorageManager.assessmentDao().loadPayload();
    if (json.length === 0) {
      return;
    }

    let payload: WorkbenchAssessmentModel;
    try {
      payload = JSON.parse(json) as WorkbenchAssessmentModel;
    } catch (err) {
      this.log.w('评估快照解析失败，已丢弃');
      await StorageManager.assessmentDao().deleteAll();
      return;
    }

    if (
      payload.version !== 1 ||
      payload.userKey !== this.userKeyOf(user) ||
      payload.mediaId.length === 0
    ) {
      // 版本不兼容 / 换号：直接清掉，避免看到别的用户或半截数据
      await StorageManager.assessmentDao().deleteAll();
      this.log.i('评估快照版本或归属不匹配，已丢弃');
      return;
    }

    this.currentTaskMediaId = payload.mediaId;
    this.currentTaskMediaName = payload.mediaName;
    this.currentTaskMediaType = payload.mediaType;
    this.currentTaskStatus = payload.status;
    this.currentTaskScore = payload.score;
    this.currentTaskError = payload.error;
    this.currentTaskRestored = true;

    if (payload.session !== null && payload.session.mediaId === payload.mediaId) {
      this.analysis().restoreSession(payload.session);
    }

    this.sync();
    this.log.i(`已恢复上一次评估 · mediaId=${payload.mediaId} status=${payload.status as number}`);
  }

  /**
   * 把 WS 桥接器的实时状态折进"当前任务"
   *
   * 为什么要单独一个函数：`done` / `error` 这两个终态**不会**再被 `sync()` 改写，
   * 所以这里只在"任务还在跑"时做状态推进，避免收尾后被后续的 `sync()` 打回 running。
   */
  private syncCurrentTask(holder: AnalysisStateHolder): void {
    if (this.currentTaskStatus === TaskStatus.none || this.currentTaskMediaId.length === 0) {
      return;
    }
    const error: string = holder.errorOf();
    if (error.length > 0) {
      this.currentTaskStatus = TaskStatus.failed;
      this.currentTaskError = error;
      return;
    }
    if (holder.isRunning()) {
      this.currentTaskStatus = TaskStatus.running;
      return;
    }
    // 不在跑且没有错误：如果拿到过分（帧或 done 的 finalScore），视为已完成
    const score: number = holder.scoreOf();
    if (score > 0) {
      this.currentTaskStatus = TaskStatus.done;
      this.currentTaskScore = score;
    }
  }

  // ══════════════════ 工作台：最近使用的素材 ══════════════════

  /**
   * 最新报告投影（按报告时间倒序、按素材去重）
   *
   * ★ 「最近使用的素材」列表已删除；本方法现在只用于工作台 hero 在
   *   **没有当前任务 / 没有持久化评估**时的首条报告回退（页面取 1 条）。
   * ★ 为什么是从**报告**推导而不是从媒体库：
   *   "评估过"= 跑过分析 = 服务端写了 `diagnosis_report`；
   *   而分数只存在于报告侧（`/api/media/list` 不返回任何评分）。
   * ★ 为什么要去重：同一素材重复分析会产生多条报告（`routers/ws.py` 每次落一条），
   *   不去重的话首条可能只是同一个文件的两次分析。
   * ★ `reportItems` 已由服务端按 `detected_at desc` 排序，这里保持顺序即最新在前。
   */
  public recentMedia(limit: number): RecentMediaModel[] {
    const out: RecentMediaModel[] = [];
    const seen: string[] = [];
    for (let i = 0; i < this.reportItems.length; i++) {
      const report: ReportListItemModel = this.reportItems[i];
      const mediaId: string = normalizeMediaId(report.mediaId);
      if (seen.indexOf(mediaId) >= 0) {
        continue;
      }
      seen.push(mediaId);
      out.push(this.buildRecentMedia(report, mediaId));
      if (out.length >= limit) {
        break;
      }
    }
    return out;
  }

  /** 单条最近素材 · 报告 + 媒体库关联出缩略图 */
  private buildRecentMedia(report: ReportListItemModel, mediaId: string): RecentMediaModel {
    const media: MediaItemModel | null = this.domainMedia.findById(mediaId);
    const score: number = report.bdiScore;
    const level = BdiThreshold.levelOf(score);
    const ratio: number = score <= 0 ? 0 : (score >= BDI_MAX_SCORE ? 1 : score / BDI_MAX_SCORE);
    const item: RecentMediaModel = {
      mediaId: mediaId,
      name: media === null || media.name.length === 0 ? report.mediaName : media.name,
      type: report.mediaType,
      thumbnailUrl: media === null ? '' : this.domainMedia.thumbnailUrl(media),
      bdiScore: score,
      severity: level,
      severityLabel: UiConstant.severityLabelOf(level),
      severityColor: UiConstant.severityColorOf(level),
      scoreRatio: ratio,
      detectedAt: report.detectedAt
    };
    return item;
  }

  // ══════════════════ 便捷查询（UI 少写判断）══════════════════

  /** 是否已完成引导（UI 的骨架屏判据） */
  public isBooted(): boolean {
    return this.bootPhase === BootPhase.authenticated || this.bootPhase === BootPhase.anonymous;
  }

  /** 显示用户名的安全写法（未登录 → 空串） */
  public username(): string {
    const user: UserModel | null = this.currentUser;
    return user === null ? '' : user.username;
  }

  /** 按 id 找媒体（★ 内部归一化，规避字符串/数字混用） */
  public findMedia(mediaId: string): MediaItemModel | null {
    return this.domainMedia.findById(normalizeMediaId(mediaId));
  }

  /** 只读一次，供 UI 断言「数据是否为空」 */
  public isEmptyMedia(): boolean {
    return this.mediaItems.length === 0;
  }

  /** 空态文案（媒体库） */
  public mediaEmptyHint(): string {
    if (this.mediaLoading) {
      return '加载中…';
    }
    if (this.offline && this.mediaItems.length === 0) {
      return '离线且无本地缓存，请连接服务端后下拉刷新';
    }
    return '还没有素材，先上传一张图片吧';
  }

  /** 消费掉全局提示（UI 弹完 toast 后调用，避免反复弹） */
  public clearGlobalMessage(): void {
    this.globalMessage = '';
  }

  /** 设置媒体库筛选（null = 全部）· 会同步到门面 */
  public setMediaTypeFilter(type: MediaType | null): void {
    this.domainMedia.setFilter(type);
    this.sync();
  }

  /** 当前媒体库筛选（null = 全部） */
  public mediaTypeFilter(): MediaType | null {
    return this.domainMedia.typeFilter;
  }

  /** 应用筛选后的媒体列表（UI 的 ForEach 用它） */
  public visibleMediaItems(): MediaItemModel[] {
    return this.domainMedia.visibleItems();
  }

  // ══════════════════ 服务端地址与连通性 ══════════════════

  /** 当前地址快照 */
  public serverConfig(): NetConfig {
    return ApiConfig.snapshot();
  }

  /**
   * 切换服务端地址（答辩现场改 IP 不必重装）
   * 改完会立刻探活一次，并把结果写进 `offline`。
   */
  public async changeServer(host: string, port: number): Promise<ActionResultModel> {
    await ApiConfig.saveHost(host, port);
    this.refreshServerInfo();
    const health: ActionResultModel = await this.checkHealth();
    this.sync();
    return health;
  }

  /** 探活 · GET /health（无需令牌，用于「后端是否启动」的一键检测） */
  public async checkHealth(): Promise<ActionResultModel> {
    this.healthChecking = true;
    try {
      const out = await HttpClient.health();
      const ok: boolean = out.status === 'ok';
      this.offline = !ok;
      this.applyHealth(ok);
      const result: ActionResultModel = {
        ok: ok,
        message: ok ? `服务端正常 · ${ApiConfig.baseUrl()}` : `服务端响应异常 · ${out.status}`
      };
      return result;
    } catch (err) {
      this.offline = true;
      this.applyHealth(false);
      const result: ActionResultModel = {
        ok: false,
        message: `无法连接 ${ApiConfig.baseUrl()}，请确认后端已启动且监听 0.0.0.0`
      };
      return result;
    } finally {
      this.healthChecking = false;
    }
  }

  /** 把探活结果写进服务状态镜像 */
  private applyHealth(ok: boolean): void {
    this.serverOnline = ok;
    this.serverStatusLabel = ok ? '在线' : '未连接';
    this.healthChecked = true;
  }

  // ══════════════════ 分析会话（转发到桥接器，并对齐门面状态）══════════════════

  /**
   * 开始分析一段媒体（WS 通道）
   * @param mediaId 服务端媒体 id
   * ★ 素材类型必须一起交给桥接器：图片（单次推理 = 1 帧）与视频（逐帧采样）
   *   的展示语义完全不同，页面靠它决定"画折线还是画直线、画饼图还是画刻度尺"。
   */
  public startAnalysis(mediaId: string): ActionResultModel {
    const item: MediaItemModel | null = this.findMedia(mediaId);
    const id: string = item === null ? normalizeMediaId(mediaId) : item.id;
    const type: MediaType = item === null ? MediaType.image : item.type;
    // 新一轮分析开始：清掉"上次评估恢复"标记（即便调用方没走 setCurrentTask）
    this.currentTaskRestored = false;
    try {
      this.analysis().start(id, type);
      this.sync();
      return AppStore.ok('已开始分析');
    } catch (err) {
      this.log.e('WebSocket 启动失败', err as Object);
      this.analysisError = 'WebSocket 启动失败，请稍后重试';
      this.sync();
      return AppStore.fail(this.analysisError);
    }
  }

  /** 请求取消当前分析（视频场景基本无效，UI 不要承诺可中断） */
  public cancelAnalysis(): void {
    this.analysisHolder?.cancel();
  }

  /** 停止分析并释放连接（页面 aboutToDisappear 必须调用） */
  public stopAnalysis(): void {
    this.analysisHolder?.stop();
    this.sync();
  }

  /** 最新一帧的人脸图 DataURL（可直接喂 Image 组件） */
  public analysisFaceDataUrl(): string {
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    return holder === null ? '' : holder.alignedFaceDataUrl();
  }

  /** 最新一帧的热力图矩阵（16×16） */
  public analysisHeatmap(): number[][] {
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    return holder === null ? [] : holder.heatmap();
  }

  /**
   * **按素材归档的分析会话列表**（工作台分析区的唯一帧数据入口）
   *
   * ★ 返回的是桥接器里那个 `@Trace` 数组**本身**，不是副本：
   *   页面在 `@Computed` 里读它，每来一帧（整体替换引用）就会失效重算，
   *   不依赖窗口层 `sync()` 的调用时机 —— 这是"逐帧实时"最可靠的一条链路。
   * ★ 桥接器还没建时返回空数组（页面走占位态）。
   */
  public analysisSessionsOf(): AnalysisSessionModel[] {
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    return holder === null ? [] : holder.sessionsOf();
  }

  /**
   * 取某一素材自己的分析会话（没有则 null）
   * ★ 工作台分析区只认这个入口：**看哪个素材就只拿那个素材的结果**，
   *   取不到就老实显示"本机未保留逐帧数据"，绝不拿别的素材兜底。
   */
  public analysisSessionOf(mediaId: string): AnalysisSessionModel | null {
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    return holder === null ? null : holder.sessionOf(normalizeMediaId(mediaId));
  }

  /** 当前 live 会话对应的素材 id（空串 = 还没有任何会话） */
  public analysisLiveMediaIdOf(): string {
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    return holder === null ? '' : holder.liveMediaIdOf();
  }

  /**
   * 实时错误文案（含"重连中"这类状态提示）
   * ★ 用访问器而不是 `analysisError` 镜像：镜像是 `sync()` 快照，会滞后一条消息。
   */
  public analysisErrorOf(): string {
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    return holder === null ? '' : holder.errorOf();
  }

  /** 进度百分比文案 */
  public analysisProgressText(): string {
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    return holder === null ? '0%' : holder.progressText();
  }

  /** 最新分数的严重度中文标签 */
  public analysisSeverityLabel(): string {
    const holder: AnalysisStateHolder | null = this.analysisHolder;
    return holder === null ? '' : holder.severityLabel();
  }

  // ══════════════════ 内部实现（全部下压）══════════════════

  private refreshServerInfo(): void {
    const config: NetConfig = ApiConfig.snapshot();
    this.serverHost = config.host;
    this.serverPort = config.port;
  }

  /** 三个领域 store 是否都处于网络失败态 */
  private detectOffline(): boolean {
    const mediaFailed: boolean = this.domainMedia.errorMsg.length > 0;
    const reportFailed: boolean = this.domainReport.errorMsg.length > 0;
    const statsFailed: boolean = this.domainStats.errorMsg.length > 0;
    return mediaFailed && reportFailed && statsFailed;
  }

  /** 401 全局落地 · 清令牌 + 清缓存 + 记一条全局提示 */
  private handleUnauthorized(message: string): void {
    this.globalMessage = message;
    this.log.w(`收到 401 · ${message}`);
    this.domainAuth.onUnauthorized(message).catch((err: Object) => {
      this.log.e('处理 401 登出失败', err);
    });
  }

  /** 领域 state 快照 · 供非 UI 代码（日志 / 测试）使用 */
  public authState(): AuthState {
    return this.domainAuth.snapshot();
  }

  /** 媒体库 state 快照 */
  public mediaState(): MediaState {
    const state: MediaState = new MediaState();
    state.items = this.domainMedia.items;
    state.current = this.domainMedia.current;
    state.loading = this.domainMedia.loading;
    state.errorMsg = this.domainMedia.errorMsg;
    state.lastSyncAt = this.domainMedia.lastSyncAt;
    return state;
  }

  /** 报告 state 快照 */
  public reportState(): ReportState {
    const state: ReportState = new ReportState();
    state.items = this.domainReport.items;
    state.total = this.domainReport.total;
    state.page = this.domainReport.page;
    state.pageSize = this.domainReport.pageSize;
    state.hasMore = this.domainReport.hasMore;
    state.detailItems = this.domainReport.detailItems;
    state.filter = this.domainReport.buildFilter();
    state.loading = this.domainReport.loading;
    state.loadingMore = this.domainReport.loadingMore;
    state.errorMsg = this.domainReport.errorMsg;
    state.lastSyncAt = this.domainReport.lastSyncAt;
    return state;
  }

  /** 统计 state 快照 */
  public statsState(): StatsState {
    const state: StatsState = new StatsState();
    state.data = this.domainStats.data;
    state.buckets = this.domainStats.buckets;
    state.loading = this.domainStats.loading;
    state.errorMsg = this.domainStats.errorMsg;
    state.lastSyncAt = this.domainStats.lastSyncAt;
    return state;
  }

  /** 应用级 state 快照 */
  public appState(): AppState {
    const state: AppState = new AppState();
    state.bootPhase = this.bootPhase;
    state.offline = this.offline;
    state.serverHost = this.serverHost;
    state.serverPort = this.serverPort;
    state.globalMessage = this.globalMessage;
    state.mediaTypeFilter = this.domainMedia.typeFilter;
    return state;
  }

  private static ok(message: string): ActionResultModel {
    const result: ActionResultModel = { ok: true, message: message };
    return result;
  }

  private static fail(message: string): ActionResultModel {
    const result: ActionResultModel = { ok: false, message: message };
    return result;
  }
}
