/**
 * WorkbenchPage · 工作台（一级页签）· **应用主页面**
 *
 * ══════════════════ 本轮（工作台主页重构 + 评估持久化）做了什么 ══════════════════
 * 用户第一阶段要求：工作台把主要内容都放到了「分析详情」二级页里，导致主页面很空；
 *   **拆掉分析页面，组成一个更丰富好看的主页面**。
 * 用户第二阶段要求：页面已经足够长，「最近使用的素材」失去了作用；
 *   **删除该区块，并把工作台目前的评估持久化**。
 *
 * 现在工作台是一张纵向长页；分析内容内联，独立详情页只给历史报告用，也没有最近素材列表：
 * ```
 * 页头（标题 + 问候/日期 + 累计概览 + 刷新）          order 0
 * 离线横幅（仅探活失败时出现）                         order 0.5（条件插入位）
 * 本次评估 hero（素材 / 状态 / 分数环 / 阶段 / 动作）   order 1
 * 开始新的辅助评估                                    order 2
 * 注意力热力图（16×16 + 逐帧列表）                     order 3
 * 情绪曲线                                            order 4
 * 严重度分布                                          order 5
 * 智能解读（VLM）                                      order 6
 * 诊断意见（本轮新增 · 结论 / 依据 / 医师确认）          order 7
 * ```
 * 3~7 号卡只在"有查看目标"时渲染；没有数据时页面是 hero 空态 + 开始评估，
 * 不会出现五张空卡片堆在一起。
 *
 * ────────────────── 查看目标与持久化 ──────────────────
 * 优先级：**当前任务（含重启后恢复的上一次评估）→ 最新一条报告 → 无**。
 *   · 分析完成后，`AppStore` 把当前任务 + 该素材的最终会话（分数/帧/热度/VLM）
 *     写入 RDB；下次启动/登录后自动恢复，hero 与四张分析卡直接还原；
 *   · 恢复的评估显示「最近一次评估 / 上次分析 · 时间」，并保留「重新分析该素材」；
 *   · 首次安装或尚未持久化时用报告列表首条兜底（只用于 hero，不渲染列表）；
 *   · 上传完成后窗口层出栈回本页并把 `scrollTopTick` +1，页面回到顶部看实时进度。
 *
 * ────────────────── ★ 本页为什么直接读 AppStore（唯一纪律例外）──────────────────
 * 页面通用纪律是「页面只吃参数」，但工作台展示的数据（探活、WS 逐帧、进度、分数）
 * 都是 `await` / 回调之后才到的，而经 `navDestination` 改参数字段不会让已挂载页面
 * 收到新值（BUG-10/11）。`AppStore` 是 `@ObservedV2` + `@Trace`，字段变化必定触发重绘，
 * 所以：**读**走 AppStore（响应式），**写**仍走 `pageParam` 注入的回调（不碰路由栈、
 * 不发请求）。`pageParam` 只承载回顶信号、刷新忙碌态与动作回调。
 *
 * ────────────────── 语法纪律 ──────────────────
 * · `build()` / `@Builder` 体内不能声明局部变量（ArkTS 踩坑），所有取值走 `@Computed`；
 * · 新增 builder 一律无参，避免 @Builder 按值传参导致"一半新一半旧"（BUG-19）；
 * · 分析卡片的取数继续复用 `AnalysisChartModel` / `HeatmapViewModel` 的纯函数，
 *   图片=1 帧/直线/刻度尺、视频=逐帧/折线/环形，且**只按 mediaId 取本素材会话**。
 */

import { UiTheme } from '../common/UiTheme';
import { AppStore } from '../store/AppStore';
import {
  AnalysisFocusModel, AnalysisFrameModel, AnalysisSessionModel, BDI_MAX_SCORE, CurrentTaskModel,
  MediaType, RecentMediaModel, SeverityMeta, TaskStatus, WorkbenchHeroModel
} from '../types/Index';
import { WorkbenchPageParam } from '../types/PageParams';
import { RevealCard } from '../components/RevealCard';
import { RippleCard } from '../components/RippleCard';
import { StatusDot } from '../components/workbench/StatusDot';
import { StartAssessmentCard } from '../components/workbench/StartAssessmentCard';
import { AnalysisHeroCard } from '../components/workbench/AnalysisHeroCard';
import { AnalysisHeatmapCard } from '../components/analysis/AnalysisHeatmapCard';
import { AnalysisVlmCard } from '../components/analysis/AnalysisVlmCard';
import {
  DiagnosisEvidenceModel, DiagnosisOpinionCard, DiagnosisOpinionModel
} from '../components/analysis/DiagnosisOpinionCard';
import {
  buildCurveView, buildSeverityView, CurveView, displayFrameCount, latestScore,
  resolveFrames, SeverityView, severityMetaOf
} from '../components/charts/AnalysisChartModel';
import { HeatHotspot, HeatmapUtil } from '../components/charts/HeatmapTile';
import { EmotionCurveCard } from '../components/charts/EmotionCurveCard';
import { SeverityDistributionCard } from '../components/charts/SeverityDistributionCard';

/** 星期的中文短名 · 下标与 `Date.getDay()` 一致（0 = 周日） */
const WEEKDAY_LABELS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

/** 根据小时给一句问候（只影响文案，不承载业务） */
function greetingOfHour(hour: number): string {
  if (hour < 6) {
    return '夜深了';
  }
  if (hour < 12) {
    return '早上好';
  }
  if (hour < 14) {
    return '中午好';
  }
  if (hour < 18) {
    return '下午好';
  }
  return '晚上好';
}

/** 今天的中文日期 · 形如「10月17日 · 周六」 */
function formatToday(): string {
  const now: Date = new Date();
  return `${now.getMonth() + 1}月${now.getDate()}日 · 周${WEEKDAY_LABELS[now.getDay()]}`;
}

/**
 * 报告时间的短文案 · "YYYY-MM-DD HH:mm:ss" → "MM-DD HH:mm"
 * ★ 只截字符串，不构造 Date：报告时间本来就是服务端本地时间文案，
 *   再解析时区反而可能跨天。
 */
function shortDateText(raw: string): string {
  if (raw.length >= 16) {
    return `${raw.substring(5, 10)} ${raw.substring(11, 16)}`;
  }
  return raw;
}

/** 两位补零（ArkTS 的 String 没有 padStart） */
function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/**
 * 毫秒时间戳 → "MM-DD HH:mm"
 * ★ 用于恢复上一次评估后显示「上次分析 · …」：
 *   这不是服务端文案，必须自己构造 Date；取本地时区的月/日/时/分。
 */
function formatStamp(stamp: number): string {
  if (!Number.isFinite(stamp) || stamp <= 0) {
    return '';
  }
  const date: Date = new Date(stamp);
  return `${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

/** 进度比例 → 百分比文案（0 给 0%，1 给 100%） */
function percentText(ratio: number): string {
  if (!Number.isFinite(ratio) || ratio <= 0) {
    return '0%';
  }
  if (ratio >= 1) {
    return '100%';
  }
  return `${Math.round(ratio * 100)}%`;
}

/**
 * 热点区域全名 → 短名 · 给诊断意见「依据」行的窄列用
 * 例：眶周区域（眼轮匝肌）→ 眶周区域；口周区域（降口角肌）→ 口周区域
 * ★ 只截「区域」二字之前的部分，不改 HeatmapUtil 的解剖学命名，
 *   避免两处文案口径漂移。
 */
function shortRegion(region: string): string {
  const cut: number = region.indexOf('区域');
  if (cut < 0) {
    return region;
  }
  return `${region.substring(0, cut)}区域`;
}

@ComponentV2
export struct WorkbenchPage {
  /** ★ 本页唯一入参：动作回调 + scrollTopTick / refreshing（挂载后会变，参数类已可观察） */
  @Param pageParam: WorkbenchPageParam = new WorkbenchPageParam();

  /** 外层滚动控制器 · 上传完成出栈后把页面拉回顶部（新任务的 hero 在顶部） */
  private scroller: Scroller = new Scroller();

  // ══════════════════ 读数（只读 store，见文件头）══════════════════

  @Computed
  get app(): AppStore {
    return AppStore.get();
  }

  /** 当前任务 · null = 没有进行中的分析 */
  @Computed
  get currentTask(): CurrentTaskModel | null {
    return this.app.currentTask();
  }

  /**
   * 最新一条报告的投影（工作台 hero 在没有当前任务时的回退）
   *
   * ★ 「最近使用的素材」区块已按用户要求删除，但 hero 仍需要一条"上次评估"：
   *   首次安装/清缓存后还没有持久化评估时，用报告列表的首条兜底，
   *   否则主页面会重新变成空页。这里只取 1 条，页面上不再渲染列表。
   */
  @Computed
  get latestReport(): RecentMediaModel | null {
    const list: RecentMediaModel[] = this.app.recentMedia(1);
    return list.length > 0 ? list[0] : null;
  }

  /** 报告是否仍在加载（只有"没有任何回退数据且正在拉"才算） */
  @Computed
  get latestLoading(): boolean {
    return this.app.reportLoading && this.latestReport === null;
  }

  /** 服务端是否在线（离线横幅用） */
  @Computed
  get serverOnline(): boolean {
    return this.app.serverOnline;
  }

  /** 是否至少完成过一次探活（挡住冷启动的假离线告警） */
  @Computed
  get healthChecked(): boolean {
    return this.app.healthChecked;
  }

  /** 是否展示离线横幅 */
  @Computed
  get showOfflineBanner(): boolean {
    return this.healthChecked && !this.serverOnline;
  }

  /** 刷新按钮 / 离线重试的忙碌态（窗口层在页头刷新时写入） */
  @Computed
  get refreshing(): boolean {
    return this.pageParam.refreshing;
  }

  // ══════════════════ 页头文案 ══════════════════

  /** 问候 + 用户名（未登录时只有问候） */
  @Computed
  get greetingLine(): string {
    const greeting: string = greetingOfHour(new Date().getHours());
    const name: string = this.app.username();
    return name.length > 0 ? `${greeting}，${name}` : greeting;
  }

  /** 今天的日期文案 */
  @Computed
  get todayText(): string {
    return formatToday();
  }

  /** 累计概览 · 统计还没到时整行不渲染 */
  @Computed
  get statsCaption(): string {
    const stats = this.app.statsSummary;
    if (stats === null) {
      return '';
    }
    return `累计 ${stats.totalAnalyses} 次评估 · ${stats.totalMedia} 份素材`;
  }

  // ══════════════════ 查看目标（focus）══════════════════

  /**
   * 当前查看目标
   * 优先级：当前任务（含重启后恢复的评估）→ 最新一条报告 → 无
   * ★ 「最近使用的素材」列表已删除，不再有用户固定查看的历史素材；
   *   最新报告只作为首装/无持久化评估时的 hero 回退，页面上没有列表入口。
   * ★ 返回的是**投影对象**，不是 store 里的引用；分数/时间仍会在下面按会话校正。
   */
  @Computed
  get focus(): AnalysisFocusModel | null {
    const task: CurrentTaskModel | null = this.currentTask;
    if (task !== null) {
      const fromTask: AnalysisFocusModel = {
        mediaId: task.mediaId,
        mediaName: task.mediaName,
        mediaType: task.mediaType,
        reportScore: task.bdiScore,
        reportTime: ''
      };
      return fromTask;
    }

    const latest: RecentMediaModel | null = this.latestReport;
    if (latest !== null) {
      const fromRecent: AnalysisFocusModel = {
        mediaId: latest.mediaId,
        mediaName: latest.name,
        mediaType: latest.type,
        reportScore: latest.bdiScore,
        reportTime: latest.detectedAt
      };
      return fromRecent;
    }
    return null;
  }

  /** 是否有查看目标 */
  @Computed
  get hasFocus(): boolean {
    return this.focus !== null;
  }

  /** 当前目标是否为「重启后恢复的上一次评估」 */
  @Computed
  get restored(): boolean {
    return this.app.currentTaskRestored;
  }

  /** 当前目标的素材类型（无目标时按图片兜底） */
  @Computed
  get focusMediaType(): MediaType {
    const current: AnalysisFocusModel | null = this.focus;
    return current === null ? MediaType.image : current.mediaType;
  }

  /** **该素材自己的**分析会话（null = 本机没有这条素材的数据） */
  @Computed
  get session(): AnalysisSessionModel | null {
    const current: AnalysisFocusModel | null = this.focus;
    if (current === null) {
      return null;
    }
    return this.app.analysisSessionOf(current.mediaId);
  }

  /** 是否有会话（历史素材可能只有报告分数） */
  @Computed
  get hasSession(): boolean {
    return this.session !== null;
  }

  /** 门面正在跑/刚跑完的会话是不是当前看的目标 */
  @Computed
  get isLive(): boolean {
    const current: AnalysisFocusModel | null = this.focus;
    return current !== null && this.app.analysisLiveMediaIdOf() === current.mediaId;
  }

  /** 当前看的目标是不是「当前任务」 */
  @Computed
  get isCurrentFocus(): boolean {
    const current: AnalysisFocusModel | null = this.focus;
    const task: CurrentTaskModel | null = this.currentTask;
    return current !== null && task !== null && current.mediaId === task.mediaId;
  }

  // ══════════════════ 分数 / 状态 / 进度 ══════════════════

  /** 当前分数：会话优先，否则回落到报告分数 */
  @Computed
  get score(): number {
    const current: AnalysisFocusModel | null = this.focus;
    if (current === null) {
      return 0;
    }
    return latestScore(this.session, current.reportScore);
  }

  /** 档位配置 · 判档与取色统一走 BdiThreshold + UiConstant */
  @Computed
  get severityMeta(): SeverityMeta {
    return severityMetaOf(this.score);
  }

  /** 档位中文标签 · 未出分时为空串（不能被读成"结果正常"） */
  @Computed
  get severityLabel(): string {
    return this.score > 0 ? this.severityMeta.label : '';
  }

  /** 档位色 · 未出分用中性色 */
  @Computed
  get severityColor(): string {
    return this.score > 0 ? this.severityMeta.color : UiTheme.textSecondary;
  }

  /** 分数文案 */
  @Computed
  get scoreText(): string {
    return this.score > 0 ? this.score.toFixed(1) : '--';
  }

  /** BDI 填充比例 = score / 63（0–1） */
  @Computed
  get scoreRatio(): number {
    if (this.score <= 0) {
      return 0;
    }
    return this.score >= BDI_MAX_SCORE ? 1 : this.score / BDI_MAX_SCORE;
  }

  /**
   * 状态：会话优先；当前任务尚未建会话时用当前任务状态；
   * 历史素材只有报告分数时视为已完成。
   */
  @Computed
  get status(): TaskStatus {
    const current: AnalysisFocusModel | null = this.focus;
    if (current === null) {
      return TaskStatus.none;
    }
    const own: AnalysisSessionModel | null = this.session;
    if (own !== null) {
      return own.status;
    }
    const task: CurrentTaskModel | null = this.currentTask;
    if (task !== null && task.mediaId === current.mediaId && task.status !== TaskStatus.none) {
      return task.status;
    }
    return current.reportScore > 0 ? TaskStatus.done : TaskStatus.none;
  }

  /** 分析进度 0–1 */
  @Computed
  get progress(): number {
    const own: AnalysisSessionModel | null = this.session;
    if (own !== null) {
      return own.progress;
    }
    const current: AnalysisFocusModel | null = this.focus;
    const task: CurrentTaskModel | null = this.currentTask;
    if (current !== null && task !== null && task.mediaId === current.mediaId) {
      return task.progress;
    }
    return this.status === TaskStatus.done ? 1 : 0;
  }

  /** 进度百分比文案 */
  @Computed
  get progressText(): string {
    return percentText(this.progress);
  }

  /**
   * 阶段下标：0 上传 / 1 逐帧推理 / 2 汇总评分
   * ★ done 直接收敛到 2：服务端落库后 progress 可能停在 0.99，不能只靠阈值兜底。
   * ★ failed 不跳阶段：停在 progress 指向的那一段，用户才知道"挂在哪一步"。
   */
  @Computed
  get stageIndex(): number {
    if (this.status === TaskStatus.done || this.progress >= 0.95) {
      return 2;
    }
    if (this.progress < 0.15) {
      return 0;
    }
    return 1;
  }

  /** 状态文案 · 运行中带进度百分比（进度条已被 BDI/阶段占用，进度只走文字） */
  @Computed
  get statusLabel(): string {
    if (this.status === TaskStatus.running) {
      if (this.progress <= 0) {
        return '分析中';
      }
      return `分析中 ${percentText(this.progress)}`;
    }
    if (this.status === TaskStatus.done) {
      return '已完成';
    }
    if (this.status === TaskStatus.failed) {
      return '分析失败';
    }
    return '未开始';
  }

  /** 状态颜色（胶囊文字 + 圆点共用；失败用错误色，完成用档位色） */
  @Computed
  get statusColor(): string {
    if (this.status === TaskStatus.failed) {
      return UiTheme.danger;
    }
    if (this.status === TaskStatus.done) {
      return this.score > 0 ? this.severityMeta.color : UiTheme.statusOnline;
    }
    if (this.status === TaskStatus.running) {
      return UiTheme.primary;
    }
    return UiTheme.textSecondary;
  }

  /** 首帧照片地址（会话首帧 → 图片缩略图 → 空串占位） */
  @Computed
  get firstFrameUrl(): string {
    const current: AnalysisFocusModel | null = this.focus;
    if (current === null) {
      return '';
    }
    return this.app.firstFrameUrlOfMedia(current.mediaId);
  }

  /** 帧数文案（图片恒为 1 帧；视频按实际收到的帧数） */
  @Computed
  get frameCountText(): string {
    const current: AnalysisFocusModel | null = this.focus;
    if (current === null) {
      return '';
    }
    const own: AnalysisSessionModel | null = this.session;
    if (own === null) {
      // ★ 历史素材没有本机会话时最多只有一个报告分数；文案要短，
      //   hero 右栏是窄列，长句会被省略号截断（真机截图已复现）。
      return current.mediaType === MediaType.image
        ? '单次推理 · 无逐帧数据'
        : '逐帧数据未保留';
    }
    const count: number = displayFrameCount(own, current.mediaType);
    if (current.mediaType === MediaType.image) {
      return count > 0 ? '1 帧（单次推理）' : '等待推理结果';
    }
    return count > 0 ? `共 ${count} 帧（逐帧采样）` : '等待逐帧数据';
  }

  /** 推理耗时文案（取最后一帧的实测值） */
  @Computed
  get inferenceText(): string {
    const own: AnalysisSessionModel | null = this.session;
    if (own === null || own.frames.length === 0) {
      return '';
    }
    const last: AnalysisFrameModel = own.frames[own.frames.length - 1];
    return last.inferenceTimeMs > 0 ? `本次推理 ${last.inferenceTimeMs.toFixed(1)} ms` : '';
  }

  /** 错误文案（会话错误 / 实时连接错误 / 当前任务错误） */
  @Computed
  get errorMsg(): string {
    const own: AnalysisSessionModel | null = this.session;
    if (own !== null && own.errorMsg.length > 0) {
      return own.errorMsg;
    }
    if (this.isLive) {
      const liveError: string = this.app.analysisErrorOf();
      if (liveError.length > 0) {
        return liveError;
      }
    }
    const current: AnalysisFocusModel | null = this.focus;
    const task: CurrentTaskModel | null = this.currentTask;
    if (
      current !== null && task !== null && task.mediaId === current.mediaId &&
      task.status === TaskStatus.failed
    ) {
      return task.errorMsg;
    }
    return '';
  }

  /** 右栏一句话说明（错误优先由 hero 处理，这里只给正常态语义） */
  @Computed
  get hintText(): string {
    if (this.restored && this.status === TaskStatus.done) {
      return '本机保存的上一次评估结果，可直接重新分析或发起新评估';
    }
    if (this.status === TaskStatus.failed) {
      return '分析中断，可点「重新分析该素材」重试';
    }
    if (this.status === TaskStatus.running) {
      return this.focusMediaType === MediaType.image
        ? '正在对这张图片做单次推理，几秒内出结果'
        : '服务端正在逐帧推理，图表会随帧更新';
    }
    if (this.status === TaskStatus.done) {
      return this.session === null
        ? '该素材最近一次分析的报告分数'
        : '分数越高表示抑郁倾向越明显';
    }
    return '等待开始';
  }

  /** 来源标签 */
  @Computed
  get sourceLabel(): string {
    if (this.isCurrentFocus && !this.restored) {
      return '当前任务';
    }
    return '最近一次评估';
  }

  /**
   * 时间文案
   * · 当前任务（本次运行）→「本次分析」/ 实时更新；
   * · 重启后恢复的上一次评估 →「上次分析 · MM-DD HH:mm」；
   * · 只有报告、没有本机会话 →「报告时间 MM-DD HH:mm」。
   */
  @Computed
  get timeText(): string {
    const current: AnalysisFocusModel | null = this.focus;
    if (current === null) {
      return '';
    }
    if (this.isCurrentFocus) {
      if (this.restored) {
        const own: AnalysisSessionModel | null = this.session;
        const stamp: string = own === null ? '' : formatStamp(own.updatedAt);
        return stamp.length > 0 ? `上次分析 · ${stamp}` : '上次分析';
      }
      return this.status === TaskStatus.running ? '本次分析 · 实时更新' : '本次分析';
    }
    if (current.reportTime.length > 0) {
      return `报告时间 ${shortDateText(current.reportTime)}`;
    }
    if (this.isLive) {
      return '本次分析 · 实时更新';
    }
    return '本次分析';
  }

  /**
   * 是否可「重新分析该素材」
   * · 本机没会话（只有报告分数）/ 上一次失败 → 给出口；
   * · 重启后恢复的上一次评估 → 给出口（用户不必重新选一遍素材就能再跑）；
   * · 本次运行刚完成 → 不给（避免误触重新跑一遍）。
   */
  @Computed
  get canReanalyze(): boolean {
    const current: AnalysisFocusModel | null = this.focus;
    if (current === null || current.mediaId.length === 0) {
      return false;
    }
    if (this.restored) {
      return true;
    }
    const own: AnalysisSessionModel | null = this.session;
    if (own === null) {
      return true;
    }
    return own.status === TaskStatus.failed;
  }

  /** 是否可「取消分析」：只有当前 live 且仍在跑时 */
  @Computed
  get canCancel(): boolean {
    return this.isLive && this.status === TaskStatus.running;
  }

  // ══════════════════ 图表取数（纯函数在 AnalysisChartModel.ets）══════════════════

  /** 要展示的帧（图片恒为最多 1 帧） */
  @Computed
  get frames(): AnalysisFrameModel[] {
    const current: AnalysisFocusModel | null = this.focus;
    return current === null ? [] : resolveFrames(this.session, current.mediaType);
  }

  /** 情绪曲线：视频=逐帧折线，图片=水平直线 */
  @Computed
  get curveView(): CurveView {
    const current: AnalysisFocusModel | null = this.focus;
    return buildCurveView(
      this.session,
      current === null ? 0 : current.reportScore,
      current === null ? MediaType.image : current.mediaType
    );
  }

  /** 严重度分布：视频=帧级环形图，图片=档位刻度尺 */
  @Computed
  get severityView(): SeverityView {
    const current: AnalysisFocusModel | null = this.focus;
    return buildSeverityView(
      this.session,
      current === null ? 0 : current.reportScore,
      current === null ? MediaType.image : current.mediaType
    );
  }

  /** VLM 文本（没有会话时为空） */
  @Computed
  get vlmText(): string {
    const own: AnalysisSessionModel | null = this.session;
    return own === null ? '' : own.vlmText;
  }

  /** VLM 空态说明 */
  @Computed
  get vlmEmptyHint(): string {
    if (this.status === TaskStatus.running) {
      return '分析完成后会生成一段文字解读';
    }
    if (this.session === null) {
      return '本机未保留本次分析的文字解读';
    }
    return '本次分析没有生成文字解读';
  }

  // ══════════════════ 诊断意见取数（只读投影，组件不碰 store）══════════════════

  /** 最后一帧 · 面部线索取它的热力图 */
  @Computed
  get latestFrame(): AnalysisFrameModel | null {
    const own: AnalysisSessionModel | null = this.session;
    if (own === null || own.frames.length === 0) {
      return null;
    }
    return own.frames[own.frames.length - 1];
  }

  /** Top-2 注意力热点 · 与热力图卡共用同一套纯函数（口径不会分叉） */
  @Computed
  get topHotspots(): HeatHotspot[] {
    const frame: AnalysisFrameModel | null = this.latestFrame;
    if (frame === null || frame.heatmapData.length === 0) {
      return [];
    }
    return HeatmapUtil.hotspots(frame.heatmapData, 2);
  }

  /** 「依据」行的面部线索文案 */
  @Computed
  get facialClue(): string {
    const spots: HeatHotspot[] = this.topHotspots;
    if (spots.length === 0) {
      return '本机未保留逐帧面部数据';
    }
    let text: string = `${shortRegion(spots[0].region)} ${spots[0].percent}%`;
    if (spots.length > 1 && spots[1].region !== spots[0].region) {
      text += ` / ${shortRegion(spots[1].region)} ${spots[1].percent}%`;
    }
    return text;
  }

  /** 初稿里的面部短句 · 「口周区域（18.3%）」 */
  @Computed
  get topRegionPhrase(): string {
    const spots: HeatHotspot[] = this.topHotspots;
    if (spots.length === 0) {
      return '';
    }
    return `${shortRegion(spots[0].region)}（${spots[0].percent}%）`;
  }

  /** 本素材逐帧评分的极差 · 无帧时为 0 */
  @Computed
  get scoreSpan(): number {
    const own: AnalysisSessionModel | null = this.session;
    if (own === null || own.frames.length === 0) {
      return 0;
    }
    let min: number = own.frames[0].bdiScore;
    let max: number = min;
    for (let i = 1; i < own.frames.length; i++) {
      const value: number = own.frames[i].bdiScore;
      if (value < min) {
        min = value;
      }
      if (value > max) {
        max = value;
      }
    }
    return max - min;
  }

  /** 时序依据：帧数 + 波动 + 稳定度（图片不编造时序） */
  @Computed
  get trendClue(): string {
    if (this.focusMediaType === MediaType.image) {
      return '单次推理 · 无时序数据';
    }
    const own: AnalysisSessionModel | null = this.session;
    if (own === null || own.frames.length === 0) {
      return '本机未保留逐帧时序数据';
    }
    const count: number = displayFrameCount(own, MediaType.video);
    const span: number = this.scoreSpan;
    let stability: string = '整体平稳';
    if (span > 7) {
      stability = '波动明显';
    } else if (span > 3) {
      stability = '轻度波动';
    }
    return `${count} 帧 · 波动 ${span.toFixed(1)} 分 · ${stability}`;
  }

  /** 是否已出分、可写诊断意见 */
  @Computed
  get opinionReady(): boolean {
    return this.status === TaskStatus.done && this.score > 0;
  }

  /** 诊断意见空态说明 */
  @Computed
  get opinionEmptyHint(): string {
    if (this.status === TaskStatus.running) {
      return this.focusMediaType === MediaType.image
        ? '正在对图片做单次推理，完成后自动生成诊断意见初稿'
        : '正在逐帧分析，完成后自动生成诊断意见初稿';
    }
    if (this.status === TaskStatus.failed) {
      return '本次分析中断，重新分析后可生成诊断意见';
    }
    if (this.focus === null) {
      return '等待分析数据';
    }
    if (this.status === TaskStatus.none) {
      return '尚未开始分析，完成后自动生成诊断意见初稿';
    }
    if (this.score <= 0) {
      return '本次分析没有产生有效评分，暂无法生成诊断意见';
    }
    return '分析完成后生成诊断意见';
  }

  /** 签名医师（未登录时用中性称谓，不冒充真实姓名） */
  @Computed
  get doctorName(): string {
    const name: string = this.app.username();
    return name.length > 0 ? name : '当前医师';
  }

  /** 模型初稿 · 分数 + 面部线索 + 时序 + 档位建议，一段话可编辑 */
  @Computed
  get opinionDraft(): string {
    if (!this.opinionReady) {
      return '';
    }
    const scoreLine: string = `BDI-II 得分 ${this.score.toFixed(1)} 分（${this.severityLabel}）`;
    const faceLine: string = this.topRegionPhrase.length > 0
      ? `面部注意力主要集中于${this.topRegionPhrase}`
      : '本机未保留逐帧面部线索';
    const trendLine: string = this.focusMediaType === MediaType.image
      ? '图片为单次推理，无时序数据'
      : this.trendClue;
    return `综合本次评估，${scoreLine}；${faceLine}；${trendLine}。` +
      `${this.severityMeta.advice}需结合临床访谈、睡眠与社交功能信息综合判断。`;
  }

  /** 判断依据三行（量表 / 面部 / 时序） */
  @Computed
  get opinionEvidence(): DiagnosisEvidenceModel[] {
    const list: DiagnosisEvidenceModel[] = [];
    const scoreRow: DiagnosisEvidenceModel = {
      label: '量表评分',
      value: `${this.score.toFixed(1)} 分 · ${this.severityLabel}`
    };
    const faceRow: DiagnosisEvidenceModel = {
      label: '面部线索',
      value: this.facialClue
    };
    const trendRow: DiagnosisEvidenceModel = {
      label: '时序特征',
      value: this.trendClue
    };
    list.push(scoreRow);
    list.push(faceRow);
    list.push(trendRow);
    return list;
  }

  /** 诊断意见卡投影 */
  @Computed
  get opinionModel(): DiagnosisOpinionModel {
    const current: AnalysisFocusModel | null = this.focus;
    return {
      mediaId: current === null ? '' : current.mediaId,
      status: this.status,
      progress: this.progress,
      ready: this.opinionReady,
      mediaName: current === null ? '' : this.app.mediaLabel(current.mediaId, current.mediaName),
      scoreText: this.scoreText,
      severityLabel: this.severityLabel,
      severityColor: this.severityColor,
      conclusion: this.opinionReady
        ? `综合量表评分与面部线索，本次评估结果为「${this.severityLabel}」，需医师结合临床访谈复核。`
        : '',
      evidence: this.opinionEvidence,
      aiDraft: this.opinionDraft,
      doctorName: this.doctorName,
      timeText: this.timeText,
      emptyHint: this.opinionEmptyHint
    };
  }

  /** hero 的只读展示投影 · 组件只负责画（见 AnalysisHeroCard） */
  @Computed
  get heroModel(): WorkbenchHeroModel {
    const current: AnalysisFocusModel | null = this.focus;
    return {
      hasFocus: current !== null,
      loading: current === null && this.latestLoading,
      mediaId: current === null ? '' : current.mediaId,
      mediaName: current === null ? '' : this.app.mediaLabel(current.mediaId, current.mediaName),
      mediaType: this.focusMediaType,
      firstFrameUrl: this.firstFrameUrl,
      sourceLabel: current === null ? '' : this.sourceLabel,
      timeText: current === null ? '' : this.timeText,
      score: this.score,
      scoreText: this.scoreText,
      scoreRatio: this.scoreRatio,
      severityLabel: this.severityLabel,
      severityColor: this.severityColor,
      status: this.status,
      statusLabel: this.statusLabel,
      statusColor: this.statusColor,
      progress: this.progress,
      progressText: this.progressText,
      stageIndex: this.stageIndex,
      stageFailed: this.status === TaskStatus.failed,
      // 阶段轨只画"本次运行正在走流程"；重启恢复的上一次评估 / 纯报告不画
      showStageRail: this.isCurrentFocus && !this.restored,
      isLive: this.isLive,
      isImage: this.focusMediaType === MediaType.image,
      frameCountText: this.frameCountText,
      inferenceText: this.inferenceText,
      hintText: this.hintText,
      errorMsg: this.errorMsg,
      canReanalyze: this.canReanalyze,
      canCancel: this.canCancel
    };
  }

  // ══════════════════ 动作 ══════════════════

  /** 把「重新分析该素材」转交窗口层（页面不碰网络/路由） */
  private handleReanalyze(): void {
    const current: AnalysisFocusModel | null = this.focus;
    if (current === null) {
      return;
    }
    this.pageParam.onReanalyze(current.mediaId, current.mediaName, current.mediaType);
  }

  /** 取消分析 · 窗口层调 AppStore.cancelAnalysis() */
  private handleCancel(): void {
    this.pageParam.onCancelAnalysis();
  }

  /**
   * 上传完成出栈后回顶
   * ★ 用户可能是在页面底部点「选择素材」的；新任务的 hero 在顶部，
   *   不回顶就会错过实时进度。窗口层出栈前把 `scrollTopTick` +1。
   */
  @Monitor('pageParam.scrollTopTick')
  private onScrollTopRequested(): void {
    try {
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: 0,
        animation: { duration: 260, curve: Curve.EaseOut }
      });
    } catch (err) {
      // 页面刚挂载 / 滚动容器还未绑定时不阻塞数据更新
      console.warn(`[Workbench] 回顶失败：${err}`);
    }
  }

  // ══════════════════ 页头 ══════════════════

  /**
   * 刷新按钮 · 与背景完全重合；忙碌态显示省略号并禁用
   * ★ 图标尚未选定：原来用 `⟳` 占位，但真机字体把它渲染成了半个括号（截图可见）。
   *   在拿到图标资源前改用「刷新」文字占位，语义明确且不依赖字体符号；
   *   将来换成 `Image($r('app.media.ic_refresh'))` 时只改这一处。
   */
  @Builder
  refreshButton() {
    Button(this.refreshing ? '…' : '刷新')
      .fontSize(UiTheme.fontSizeCaption)
      .fontColor(UiTheme.textSecondary)
      .backgroundColor(Color.Transparent)
      .borderRadius(UiTheme.cardRadius)
      .width(48)
      .height(40)
      // ★ Button 默认自带左右内边距；宽度只有 48 时会把「刷新」两个字挤成省略号。
      //   显式压到 4vp，两个 12fp 汉字才放得下（这也解释了旧 `⟳` 为什么显示成半个括号）。
      .padding({ left: UiTheme.gapXs, right: UiTheme.gapXs })
      .enabled(!this.refreshing)
      .onClick(() => {
        this.pageParam.onRefresh();
      })
  }

  @Builder
  pageHeader() {
    Column({ space: UiTheme.gapXs }) {
      Row() {
        Text('工作台')
          .fontSize(UiTheme.fontSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        this.refreshButton()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(`${this.greetingLine} · ${this.todayText}`)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.statsCaption.length > 0) {
        Text(this.statsCaption)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ══════════════════ 离线横幅（只在离线时出现）══════════════════

  @Builder
  offlineBanner() {
    RippleCard({ _padding: UiTheme.gapM, _enabled: false, _clickable: false }) {
      Row({ space: UiTheme.gapS }) {
        // 红点：只用颜色表达状态对色觉障碍用户不可读，所以紧跟着就是文字
        StatusDot({ dotColor: UiTheme.statusOffline, dotSize: 8 })

        Column({ space: UiTheme.gapXs }) {
          Text('无法连接服务器')
            .fontSize(UiTheme.fontSizeBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.danger)
            .width('100%')
            .textAlign(TextAlign.Start)

          Text('已显示本地缓存的数据，点右侧重试或右上角刷新')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(this.refreshing ? '重连中…' : '重试')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.danger)
          .backgroundColor(Color.Transparent)
          .borderWidth(1)
          .borderColor(UiTheme.danger)
          .borderRadius(UiTheme.buttonRadius)
          .height(36)
          .padding({ left: UiTheme.gapL, right: UiTheme.gapL })
          .enabled(!this.refreshing)
          .onClick(() => {
            this.pageParam.onRefresh();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  // ══════════════════ 各区块（★ 无参 builder）══════════════════

  /** 本次评估 hero */
  @Builder
  heroSection() {
    AnalysisHeroCard({
      model: this.heroModel,
      onReanalyze: () => {
        this.handleReanalyze();
      },
      onCancel: () => {
        this.handleCancel();
      }
    })
  }

  /** 开始新的辅助评估 */
  @Builder
  startSection() {
    StartAssessmentCard({
      onPick: () => {
        this.pageParam.onSelectMedia();
      }
    })
  }

  /** 注意力热力图卡（内容）· 白卡由 RippleCard 提供 */
  @Builder
  heatmapSection() {
    RippleCard({ _enabled: false, _clickable: false }) {
      AnalysisHeatmapCard({
        frames: this.frames,
        mediaType: this.focusMediaType,
        isLive: this.isLive,
        hasSession: this.hasSession
      })
    }
  }

  /** 情绪曲线卡（内容） */
  @Builder
  curveSection() {
    RippleCard({ _enabled: false, _clickable: false }) {
      EmotionCurveCard({ view: this.curveView })
    }
  }

  /** 严重度分布卡（内容） */
  @Builder
  severitySection() {
    RippleCard({ _enabled: false, _clickable: false }) {
      SeverityDistributionCard({ view: this.severityView })
    }
  }

  /** 智能解读卡（内容） */
  @Builder
  vlmSection() {
    RippleCard({ _enabled: false, _clickable: false }) {
      AnalysisVlmCard({
        text: this.vlmText,
        emptyHint: this.vlmEmptyHint
      })
    }
  }

  /**
   * 诊断意见卡（本轮新增）
   * ★ 放在智能解读之后：证据（图表 / 解读）→ 结论（意见），顺序符合临床阅片习惯，
   *   也不会让原有 3–6 号卡的 order 全部改号。
   */
  @Builder
  opinionSection() {
    RippleCard({ _enabled: false, _clickable: false }) {
      DiagnosisOpinionCard({ model: this.opinionModel })
    }
  }

  build() {
    Column() {
      Scroll(this.scroller) {
        Column({ space: UiTheme.gapL }) {
          // ── 页头（0 号位）──
          RevealCard({ order: 0 }) {
            this.pageHeader()
          }

          // ── 离线横幅：只在探活失败后出现（0.5 = 插在页头与 hero 之间的条件位）──
          // ★ 用 0.5 而不是把 1~7 全部改号：离线是偶发态，若占一个整数槽位，
          //   在线时 hero 之后整页会凭空多等一个 stepMs（110ms），切页签的离场等待
          //   也会被 CARDS_WORKBENCH 一起拉长；小数位只让横幅自己在 55ms 处错峰，
          //   其余卡片的节拍与在线路径完全不变。
          if (this.showOfflineBanner) {
            RevealCard({ order: 0.5 }) {
              this.offlineBanner()
            }
          }

          // ── 本次评估 hero（1 号位）──
          RevealCard({ order: 1 }) {
            this.heroSection()
          }

          // ── 开始新的辅助评估（2 号位）──
          RevealCard({ order: 2 }) {
            this.startSection()
          }

          // ── 分析区：没有查看目标时整段不渲染（避免五张空卡片）──
          if (this.hasFocus) {
            RevealCard({ order: 3 }) {
              this.heatmapSection()
            }
            RevealCard({ order: 4 }) {
              this.curveSection()
            }
            RevealCard({ order: 5 }) {
              this.severitySection()
            }
            RevealCard({ order: 6 }) {
              this.vlmSection()
            }
            RevealCard({ order: 7 }) {
              this.opinionSection()
            }
          }
        }
        .width('100%')
        .padding({
          left: UiTheme.pagePadding,
          right: UiTheme.pagePadding,
          top: UiTheme.gapL,
          bottom: UiTheme.gapXxl
        })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }
}
