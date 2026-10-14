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
  ActionResultModel, AnalysisFrameModel, BootPhase, MediaItemModel, MediaType,
  normalizeMediaId, ReportListItemModel, SeverityBucketModel, SocketState, StatsModel,
  UserModel
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
  @Trace analyzing: boolean = false;
  @Trace analysisProgress: number = 0;
  @Trace analysisScore: number = 0;
  @Trace analysisFrameCount: number = 0;
  @Trace analysisLastFrame: AnalysisFrameModel | null = null;
  @Trace analysisVlmText: string = '';
  @Trace analysisError: string = '';
  @Trace socketState: SocketState = SocketState.idle;

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

  /** 分析桥接器（懒建，避免未登录时就建 WS 相关对象） */
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

  /** 分析收尾后刷新统计与报告（服务端此刻已写入 diagnosis_report） */
  public async onAnalysisFinished(): Promise<void> {
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
    }
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
    try {
      const out = await HttpClient.health();
      const ok: boolean = out.status === 'ok';
      this.offline = !ok;
      const result: ActionResultModel = {
        ok: ok,
        message: ok ? `服务端正常 · ${ApiConfig.baseUrl()}` : `服务端响应异常 · ${out.status}`
      };
      return result;
    } catch (err) {
      this.offline = true;
      const result: ActionResultModel = {
        ok: false,
        message: `无法连接 ${ApiConfig.baseUrl()}，请确认后端已启动且监听 0.0.0.0`
      };
      return result;
    }
  }

  // ══════════════════ 分析会话（转发到桥接器，并对齐门面状态）══════════════════

  /**
   * 开始分析一段媒体（WS 通道）
   * @param mediaId 服务端媒体 id
   */
  public startAnalysis(mediaId: string): ActionResultModel {
    const item: MediaItemModel | null = this.findMedia(mediaId);
    const id: string = item === null ? normalizeMediaId(mediaId) : item.id;
    try {
      this.analysis().start(id);
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
