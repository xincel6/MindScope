/**
 * 响应式状态类型 · **ArkTS 专用**，所以后缀是 `.ets` 而不是 `.ts`
 *
 * 判定依据（docs/本轮开发交接.md 第 5.2 节）：
 *   `@ObservedV2` / `@Trace` 是 ArkTS 专有装饰器，纯 TS 无法解析 →
 *   凡是用到它们的类型代码，一律放 `.ets`；
 *   纯类型 / 纯常量放 `.ts`，这样 Web 端也能直接 import 同一份。
 *
 * ★ 为什么状态类要放在 `types/` 而不是散落在 store/：
 *   用户要求「应归入数据类型文件夹的类型，全部收拢到统一文件夹」，
 *   `@Trace` 字段的**类型形状**属于数据类型，`store/` 只放**行为**。
 *
 * ★ ArkTS 响应式规则：普通 class 的字段变化**不会**刷新 UI，
 *   只有 `@ObservedV2` 类上的 `@Trace` 字段才会触发重建。所以：
 *   - 所有会被 UI 直接读的字段，都必须在这里用 `@Trace` 声明；
 *   - 子类必须**显式重复声明**自己要暴露的 `@Trace` 字段（不依赖继承的装饰器）。
 *   - `@Trace` 只能修饰 `@ObservedV2` 类里、在构造阶段即完成声明的字段；
 *     **不要**给 `@Trace` 字段赋 `undefined` 初始值，用 `null` 或空值兜底。
 */

import { BootPhase, MediaType, SocketState } from './enums';
import {
  AnalysisFrameModel, AnalysisSessionModel, DiagnosisReportModel, MediaItemModel, ReportFilterModel,
  ReportListItemModel, SeverityBucketModel, StatsModel, UserModel
} from './model';

/** 媒体库响应式状态 */
@ObservedV2
export class MediaState {
  /** 媒体列表（UI 唯一的读数来源） */
  @Trace items: MediaItemModel[] = [];
  /** 单条详情（详情页用） */
  @Trace current: MediaItemModel | null = null;
  @Trace loading: boolean = false;
  @Trace errorMsg: string = '';
  /** 最近一次同步时间（毫秒），0 表示从未同步 */
  @Trace lastSyncAt: number = 0;
}

/** 报告响应式状态 */
@ObservedV2
export class ReportState {
  @Trace items: ReportListItemModel[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  @Trace pageSize: number = 20;
  @Trace hasMore: boolean = false;
  /** 正在浏览的媒体详情报告（GET /api/report/{mediaId}）· 明细形状，含 notes */
  @Trace detailItems: DiagnosisReportModel[] = [];
  /** 当前筛选条件（UI 双向绑定它） */
  @Trace filter: ReportFilterModel = { severity: '', mediaType: '', page: 1, pageSize: 20 };
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace errorMsg: string = '';
  @Trace lastSyncAt: number = 0;
}

/** 统计响应式状态 */
@ObservedV2
export class StatsState {
  /** 完整体（含趋势点与最近报告） */
  @Trace data: StatsModel | null = null;
  /** 严重度分布摊平后的数组（UI 图例/柱状图直接 ForEach 它） */
  @Trace buckets: SeverityBucketModel[] = [];
  @Trace loading: boolean = false;
  @Trace errorMsg: string = '';
  @Trace lastSyncAt: number = 0;
}

/** 登录态响应式状态 */
@ObservedV2
export class AuthState {
  @Trace token: string = '';
  @Trace user: UserModel | null = null;
  /** 是否已登录（有非空令牌即视为已登录，用户名可能还没拉到） */
  @Trace signedIn: boolean = false;
  @Trace loading: boolean = false;
  @Trace errorMsg: string = '';
}

/**
 * 分析会话的响应式状态（WS 推送驱动）
 *
 * ★★ 本轮（分析页实装轮）结构变更：**"一份全局帧缓冲" → "按素材归档的会话列表"**
 *   旧实现把逐帧数据放在 `frameHistory` / `scoreHistory` 两个**全局**数组里，
 *   于是出现两个必然后果：
 *     · 开始分析素材 B 时 `reset()` 把 A 的帧清空（用户看到"后上传的覆盖了前面的"）；
 *     · 历史素材页没有自己的帧，只能拿"全局最后一帧"顶替
 *       → 所有素材的热力图都变成最近分析的那个人。
 *   现在逐帧数据**只存在于 `sessions` 里那一条属于该素材的会话**，全局状态退化为
 *   "当前 live 会话的指针"（mediaId / running / 进度 / 末帧…），两份职责分清。
 */
@ObservedV2
export class AnalysisState {
  @Trace running: boolean = false;
  @Trace mediaId: string = '';
  @Trace socketState: SocketState = SocketState.idle;
  /** 0–1；★ 服务端会从 0 直接跳到 1，UI 请做过渡动画而不是逐帧重绘 */
  @Trace progress: number = 0;
  /** 最新一帧的 BDI 分数 */
  @Trace bdiScore: number = 0;
  /** 已收到的帧数（live 会话的计数，与 `sessions` 里那一条保持一致） */
  @Trace frameCount: number = 0;
  /** 最近一帧（人脸图渲染 / 推理耗时展示用） */
  @Trace lastFrame: AnalysisFrameModel | null = null;
  /**
   * **按素材归档的分析会话**（一个 mediaId 一条）
   *
   * · 同一素材再次分析 = 覆盖它自己那一条，其它素材的结果保留；
   * · 每收到一帧就整体替换数组引用（`concat` + `slice` 后赋值），
   *   保证 V2 的 `@Trace` 一定感知到变化 —— 原地改元素不会触发刷新；
   * · live 会话即 `mediaId === 上面那个 mediaId` 的那一条，**没有第二份帧数据**；
   * · 上限见 `store/AnalysisStateHolder.ets`：会话数 6、单会话帧 90（收尾裁到 30）、
   *   分数点 120。
   */
  @Trace sessions: AnalysisSessionModel[] = [];
  /** VLM 文本解读 */
  @Trace vlmText: string = '';
  /** done 消息里的最终分数 */
  @Trace finalScore: number = 0;
  @Trace errorMsg: string = '';
}

/**
 * 应用级响应式状态 · UI 侧的**总入口**
 *
 * 页面里统一这样取数（详见 docs/鸿蒙端数据获取使用指南.md）：
 * ```ts
 * @Computed get media() { return AppStore.get().media.items; }
 * ```
 */
@ObservedV2
export class AppState {
  /** 启动引导阶段 */
  @Trace bootPhase: BootPhase = BootPhase.idle;
  /** 是否处于离线兜底（本地数据可读、网络不可达） */
  @Trace offline: boolean = false;
  /** 服务端地址（联调时 UI 可修改） */
  @Trace serverHost: string = '';
  @Trace serverPort: number = 0;
  /** 全局提示（如「登录已过期，请重新登录」） */
  @Trace globalMessage: string = '';
  /** 媒体类型筛选（媒体库页用） */
  @Trace mediaTypeFilter: MediaType | null = null;
}
