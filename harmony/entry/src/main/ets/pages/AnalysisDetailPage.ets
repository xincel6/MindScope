/**
 * AnalysisDetailPage · 分析详情页（本轮**实装完成**）
 *
 * 页面契约（★ 参数只承载"入栈那一刻就确定"的信息）：
 * ```ts
 * const param = new AnalysisDetailPageParam();
 * param.mediaId = '12';
 * param.mediaName = 'interview.mp4';
 * param.mediaType = MediaType.video;   // 图片 / 视频的全部展示语义由它决定
 * param.reportScore = 18.4;            // 没有本机会话时的回落值
 * param.reportTime = '2026-10-20 10:31:02';
 * param.onBack = () => { stack.pop(); };
 * param.onReanalyze = () => { ... };   // 本机没逐帧数据时的出口
 * ```
 *
 * ────────────────── 本轮（分析页实装轮）做了什么 ──────────────────
 * ① **两个空组件换成真实图表**（原来只是 `chartPlaceholder()` 灰块）：
 *    · 情绪曲线 → `EmotionCurveCard`（视频=逐帧折线，图片=水平直线）；
 *    · 严重度分布 → `SeverityDistributionCard`（视频=帧级环形分布，图片=档位刻度尺）。
 * ② **图片与视频彻底分开**：类型徽标（`MediaTypeBadge`）+ 帧数口径 + 状态文案 +
 *    逐帧列表是否出现 + 两张图的形态，全部按 `pageParam.mediaType` 分叉。
 * ③ **数据按素材取**：页面只认 `AppStore.analysisSessionOf(pageParam.mediaId)`。
 *    旧实现没有会话时拿"全局最新一帧"顶替，导致
 *    「退出再回来只剩 1 帧」「所有素材的热力图都变成最近那个人」两个 bug（BUG-13/14）。
 * ④ **实时数据不再走参数**：进度/分数/档位/帧/VLM 全部从 `@Trace` 会话读，
 *    于是分析跑完档位标签和智能解读会自己出现（BUG-15）。
 *
 * ────────────────── ★ 本页为什么打破了"页面不读 store"的纪律 ──────────────────
 * 工程通用纪律是「页面只吃参数、不 import store」，但本页必须读 store，理由有两条，
 * 且都不是"图省事"：
 *
 *   1. **逐帧数据必须在帧到达的当下就进入 UI**。窗口层的参数投影只在
 *      "切页签 / 入栈"时被调用，WebSocket 帧到达时**不会**触发它。
 *      若只靠参数，页面会停在"进入本页时那一帧"，看起来像卡死。
 *      （旧代码正是靠这条口子才让热力图动起来；旧 `syncDetailParam()` 也因此
 *      永远抄不到分数与解读 —— 见 BUG-15。）
 *   2. **每个素材的结果必须按 mediaId 取**。哪条素材的帧、哪条素材的分数，
 *      只有会话归档知道；参数里放不下"所有素材"，也不该放。
 *
 * 纪律的**核心部分仍然保留**：
 *   · 本页**只读** store，不调用任何写方法；
 *   · 动作（返回、取消分析、重新分析）仍然走注入的回调，不碰路由栈、不发请求；
 *   · 素材名/类型/报告分数等元信息仍然只认参数，不从 store 反推。
 *
 * ★ 返回不停止分析（用户既有要求）：分析会话挂在 `AppStore` 单例上，
 *   本页 `aboutToDisappear` **故意不调** `stopAnalysis()`，
 *   这样用户回到工作台后「当前任务」仍在推进，再点回来能看到最新进度。
 */

import { UiTheme } from '../common/UiTheme';
import { display } from '@kit.ArkUI';
import { AppStore } from '../store/AppStore';
import { AnalysisDetailPageParam } from '../types/PageParams';
import {
  AnalysisFrameModel, AnalysisSessionModel, MediaType, SeverityMeta, TaskStatus
} from '../types/Index';
import { PageHeader } from '../components/PageHeader';
import { RippleCard } from '../components/RippleCard';
import { ProgressBar } from '../components/common/ProgressBar';
import { MediaTypeBadge } from '../components/common/MediaTypeBadge';
import { AttentionHeatmap } from '../components/charts/AttentionHeatmap';
import { HeatmapTile } from '../components/charts/HeatmapTile';
import { makeSampleFrames } from '../components/charts/HeatmapSampleData';
import {
  buildHeatmapView, HeatmapView, HeatSource, heatSourceHint
} from '../components/charts/HeatmapViewModel';
import {
  buildCurveView, buildSeverityView, CurveView, displayFrameCount, latestScore, resolveFrames,
  severityMetaOf, SeverityView
} from '../components/charts/AnalysisChartModel';
import { EmotionCurveCard } from '../components/charts/EmotionCurveCard';
import { SeverityDistributionCard } from '../components/charts/SeverityDistributionCard';

/** 横向逐帧列表里小方块的边长（vp）· 一屏约能放下 3~4 格，滑动回看更多 */
const STRIP_TILE_SIZE: number = 72;

/**
 * 横向列表的**行高**
 *
 * ★ 这个值必须一次算准，否则最后一行的文字会被裁掉（实测踩过）：
 *   方块 72 + 间距 8 + 帧号行 ≈17 + 间距 8 + BDI 行 ≈17 + 格内上下 padding 8 = **130**
 *   再留 8 给滚动条（主轴方向上滚动条会占位），取 138。
 */
const STRIP_ROW_HEIGHT: number = STRIP_TILE_SIZE + 58 + 8;

/** 一条横向滚动条的粗细 */
const STRIP_SCROLLBAR_WIDTH: number = 4;

/** 帧序号两位数补零（ArkTS 的 String 没有 padStart，所以自己写） */
function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/**
 * 屏幕密度（px / vp）
 *
 * ★ 为什么需要它：实测（模拟器 1316×2832，API 23）`onAreaChange` 回填的
 *   `Area.width` 是**物理像素**，不是 vp。若直接把它当 vp 传给组件的 `panelSize`，
 *   在高密度屏上主图会被放大到远超卡片宽度（实测 3.25 倍屏上画到 1055px 宽，溢出卡片）。
 *   所以必须除以密度换算回 vp。
 *
 * ★ `display.getDefaultDisplaySync()` 自 API 9 起可用、**不需要任何权限**。
 *   拿不到时退回 3.0 —— 这是本项目目标设备（手机）的常见密度，
 *   即使猜错也只会让主图偏小一点，不会溢出。
 */
function screenDensity(): number {
  try {
    const info: display.Display = display.getDefaultDisplaySync();
    const density: number = info.densityPixels;
    if (!Number.isFinite(density) || density <= 0) {
      return 3.0;
    }
    return density;
  } catch (err) {
    return 3.0;
  }
}

@ComponentV2
export struct AnalysisDetailPage {
  /** ★ 本页入参（素材元信息 / 报告回落值 / 动作回调） */
  @Param pageParam: AnalysisDetailPageParam = new AnalysisDetailPageParam();

  // ══════════════════ 本地状态（纯视觉，不承载业务数据）══════════════════

  /** 卡片内容区实测宽度（由 `onAreaChange` 回填）· 决定主图方块的边长 */
  @Local contentWidth: number = 0;

  /** 主图方块边长（vp）· 随 `contentWidth` 收敛，避免"先画小再跳大" */
  @Local panelSize: number = 0;

  /** 用户手动选中的帧下标（-1 = 没选过，跟随最新一帧） */
  @Local focusedIndex: number = -1;

  /**
   * 合成演示帧（只在没有任何真实热度数据时使用，界面上会标注"演示数据"）
   * ★ 默认必须是**空数组**：有真实数据时绝不能拿合成帧顶替，那一帧的临床含义会被完全误读。
   *   用户点"载入合成演示数据"按钮才会填充（`loadSample()`）。
   */
  @Local sampleFrames: AnalysisFrameModel[] = [];

  /** 横向列表的滚动控制器（用于"把最新一帧滚进视野"） */
  private scroller: Scroller = new Scroller();

  /** 屏幕密度（px / vp）· 用于把 onAreaChange 报的物理像素换算成 vp */
  private density: number = 3.0;

  aboutToAppear(): void {
    this.density = screenDensity();
  }

  // ══════════════════ 响应式读数（只读 store，见文件头说明）══════════════════

  /** store 门面 · 只读 */
  @Computed
  get app(): AppStore {
    return AppStore.get();
  }

  /**
   * **本素材自己的**分析会话（null = 本机没有这条素材的分析数据）
   *
   * ★ 这是本页唯一的帧数据入口。取不到就是 null，页面老实显示
   *   "本机未保留逐帧数据"，**绝不跨素材兜底**（BUG-14 的根因就是那条兜底）。
   */
  @Computed
  get session(): AnalysisSessionModel | null {
    return this.app.analysisSessionOf(this.pageParam.mediaId);
  }

  /** 门面里正在跑/刚跑完的会话是不是本页这一条（决定文案与"取消分析"按钮） */
  @Computed
  get isLive(): boolean {
    const live: string = this.app.analysisLiveMediaIdOf();
    const mine: string = this.pageParam.mediaId;
    return mine.length > 0 && live.length > 0 && live === mine;
  }

  /** 是否图片素材（本页所有"图片/视频分叉"的唯一判据） */
  @Computed
  get isImage(): boolean {
    return this.pageParam.mediaType === MediaType.image;
  }

  /** 要展示的帧（图片恒为最多 1 帧） */
  @Computed
  get frames(): AnalysisFrameModel[] {
    return resolveFrames(this.session, this.pageParam.mediaType);
  }

  /** 当前分数（会话优先，否则回落报告分数） */
  @Computed
  get score(): number {
    return latestScore(this.session, this.pageParam.reportScore);
  }

  /** 分数文案 · 没出分时给中性占位，不显示 0.0（会被误读成"分数是零"） */
  @Computed
  get scoreText(): string {
    return this.score > 0 ? this.score.toFixed(1) : '--';
  }

  /** 档位配置（判档 + 取色**统一口径** · 不再从参数里读快照值，见 BUG-15） */
  @Computed
  get severityMeta(): SeverityMeta {
    return severityMetaOf(this.score);
  }

  /** 档位中文标签（分数为 0 时留空，避免显示"正常"误导） */
  @Computed
  get severityLabel(): string {
    return this.score > 0 ? this.severityMeta.label : '';
  }

  /** 档位颜色 */
  @Computed
  get severityColor(): string {
    return this.score > 0 ? this.severityMeta.color : UiTheme.textSecondary;
  }

  /** 会话状态（没有会话时：有报告分数 = 已完成，否则 = 未开始） */
  @Computed
  get status(): TaskStatus {
    const session: AnalysisSessionModel | null = this.session;
    if (session !== null) {
      return session.status;
    }
    return this.pageParam.reportScore > 0 ? TaskStatus.done : TaskStatus.none;
  }

  /** 状态中文标签 */
  @Computed
  get statusLabel(): string {
    const status: TaskStatus = this.status;
    if (status === TaskStatus.running) {
      return '分析中';
    }
    if (status === TaskStatus.done) {
      return '已完成';
    }
    if (status === TaskStatus.failed) {
      return '分析失败';
    }
    return '未开始';
  }

  /** 状态标签颜色 · 运行中用主色，完成用分数档位色，失败用错误色 */
  @Computed
  get statusColor(): string {
    const status: TaskStatus = this.status;
    if (status === TaskStatus.failed) {
      return UiTheme.danger;
    }
    if (status === TaskStatus.done) {
      return this.severityColor;
    }
    return UiTheme.primary;
  }

  /** 进度 0–1 */
  @Computed
  get progress(): number {
    const session: AnalysisSessionModel | null = this.session;
    if (session !== null) {
      return session.progress;
    }
    return this.status === TaskStatus.done ? 1 : 0;
  }

  /** 进度百分比文案 */
  @Computed
  get progressText(): string {
    const ratio: number = this.progress;
    if (!Number.isFinite(ratio) || ratio <= 0) {
      return '0%';
    }
    return ratio >= 1 ? '100%' : `${Math.round(ratio * 100)}%`;
  }

  /** 帧数文案（图片恒为 1 帧；视频按实际收到的帧数） */
  @Computed
  get frameCountText(): string {
    const session: AnalysisSessionModel | null = this.session;
    if (session === null) {
      return this.isImage ? '单次推理（本机无逐帧数据）' : '逐帧数据未保留';
    }
    const count: number = displayFrameCount(session, this.pageParam.mediaType);
    if (this.isImage) {
      return count > 0 ? '1 帧（单次推理）' : '等待推理结果';
    }
    return count > 0 ? `共 ${count} 帧（逐帧采样）` : '等待逐帧数据';
  }

  /** 推理耗时文案（取最后一帧的实测值） */
  @Computed
  get inferenceText(): string {
    const session: AnalysisSessionModel | null = this.session;
    if (session === null || session.frames.length === 0) {
      return '';
    }
    const last: AnalysisFrameModel = session.frames[session.frames.length - 1];
    return last.inferenceTimeMs > 0 ? `本次推理 ${last.inferenceTimeMs.toFixed(1)} ms` : '';
  }

  /** 报告时间文案（只在"本机没有会话、靠报告回落"时显示） */
  @Computed
  get reportTimeText(): string {
    if (this.session !== null || this.pageParam.reportTime.length === 0) {
      return '';
    }
    return `该素材最近一次分析：${this.pageParam.reportTime}`;
  }

  /** 是否已经有任何可展示的数据（会话 或 报告分数） */
  @Computed
  get hasData(): boolean {
    return this.session !== null || this.pageParam.reportScore > 0;
  }

  /** 是否可以重新分析（本机没数据 / 上一次失败） */
  @Computed
  get canReanalyze(): boolean {
    if (this.pageParam.mediaId.length === 0) {
      return false;
    }
    const session: AnalysisSessionModel | null = this.session;
    if (session === null) {
      return true;
    }
    return session.status === TaskStatus.failed;
  }

  /** 顶部一句话状态说明（图片/视频口径不同） */
  @Computed
  get statusHint(): string {
    const session: AnalysisSessionModel | null = this.session;
    if (session === null) {
      return this.pageParam.reportScore > 0
        ? '本机未保留这次分析的逐帧数据，只能显示报告分数；点下方「重新分析」可重跑一次'
        : '这个素材还没有分析结果';
    }
    const status: TaskStatus = session.status;
    if (status === TaskStatus.running) {
      return this.isImage
        ? '正在对这张图片做单次推理（图片只有 1 帧结果）'
        : `服务端正在逐帧推理，已收到 ${session.frameCount} 帧`;
    }
    if (status === TaskStatus.done) {
      return this.isImage
        ? '分析已完成：图片只做 1 次推理，报告已写入服务端'
        : `分析已完成：共 ${session.frameCount} 帧，报告已写入服务端`;
    }
    if (status === TaskStatus.failed) {
      return '分析中断，可点下方「重新分析」重试';
    }
    return '等待开始';
  }

  /** VLM 文本解读（会话里才有：实时收尾即出现） */
  @Computed
  get vlmText(): string {
    const session: AnalysisSessionModel | null = this.session;
    return session === null ? '' : session.vlmText;
  }

  /** 错误文案（会话错误 或 实时连接错误） */
  @Computed
  get errorMsg(): string {
    const session: AnalysisSessionModel | null = this.session;
    if (session !== null && session.errorMsg.length > 0) {
      return session.errorMsg;
    }
    return this.isLive ? this.app.analysisErrorOf() : '';
  }

  // ══════════════════ 图表取数（纯函数在 AnalysisChartModel.ets，可离线测）══════════════════

  /** 情绪曲线：视频=逐帧折线，图片=水平直线 */
  @Computed
  get curveView(): CurveView {
    return buildCurveView(this.session, this.pageParam.reportScore, this.pageParam.mediaType);
  }

  /** 严重度分布：视频=帧级环形图，图片=档位刻度尺 */
  @Computed
  get severityView(): SeverityView {
    return buildSeverityView(this.session, this.pageParam.reportScore, this.pageParam.mediaType);
  }

  // ══════════════════ 热力图区取数 ══════════════════

  /** 热力图区的取数结果（主图与横向列表的**唯一**数据入口） */
  @Computed
  get heatView(): HeatmapView {
    return buildHeatmapView(this.frames, this.sampleFrames, this.focusedIndex, this.isLive);
  }

  /** 主图那一帧 */
  @Computed
  get activeFrame(): AnalysisFrameModel | null {
    const view: HeatmapView = this.heatView;
    if (view.index < 0 || view.index >= view.frames.length) {
      return null;
    }
    return view.frames[view.index];
  }

  /** 是否正在使用演示数据（用于把标题旁边打上标注） */
  @Computed
  get isSample(): boolean {
    return this.heatView.source === HeatSource.sample;
  }

  /** 主图说明文案（说清"这一格画的是哪一帧、数据从哪来"） */
  @Computed
  get heatHint(): string {
    const frame: AnalysisFrameModel | null = this.activeFrame;
    const view: HeatmapView = this.heatView;
    if (frame === null) {
      return '尚无热度数据';
    }
    return heatSourceHint(view.source, frame.frameId, frame.bdiScore);
  }

  /** 逐帧区的标题文案（图片 / 视频口径不同） */
  @Computed
  get stripTitle(): string {
    const count: number = this.heatView.frames.length;
    if (this.isImage) {
      return '单帧热力图（图片只有 1 次推理）';
    }
    if (count === 0) {
      return '逐帧热力图（视频切分视图）';
    }
    return `逐帧热力图（视频切分视图）· 共 ${count} 帧`;
  }

  // ══════════════════ 交互 ══════════════════

  /**
   * 测量卡片内容区宽度 → 收敛主图边长
   * ★ 传入的是**物理像素**（`onAreaChange` 的口径），必须先除以密度换算成 vp。
   */
  private onContentArea(widthPx: number): void {
    if (!Number.isFinite(widthPx) || widthPx <= 0) {
      return;
    }
    const widthVp: number = widthPx / this.density;
    const next: number = this.sizeForWidth(widthVp);
    if (next === this.panelSize) {
      return;
    }
    this.panelSize = next;
    console.info(`[Heatmap] 卡片内容区 ${widthPx.toFixed(0)}px / ${this.density} = ${widthVp.toFixed(0)}vp → 主图 ${next}vp`);
  }

  /** 边长收敛：夹在 [200, 300] 并向下取整（避免非整数边长在格子缝处产生细线） */
  private sizeForWidth(width: number): number {
    if (width <= 0) {
      return 0;
    }
    const clamped: number = width < 200 ? 200 : (width > 300 ? 300 : width);
    return Math.floor(clamped);
  }

  /** 点某一格：固定到那一帧；点已经固定的那一格 = 取消固定，回到最新帧 */
  private onPickFrame(index: number): void {
    this.focusedIndex = this.focusedIndex === index ? -1 : index;
  }

  /** 载入合成演示帧（没有真实数据时用来验证渲染链路） */
  private loadSample(): void {
    this.sampleFrames = makeSampleFrames();
    this.focusedIndex = -1;
    // 新数据到位后把列表滚到最右（最新一帧），与实时跟随时的心智模型一致
    this.scroller.scrollEdge(Edge.End);
  }

  // ══════════════════ ① 素材与状态卡 ══════════════════

  @Builder
  materialCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapM }) {
        Row({ space: UiTheme.gapS }) {
          Text(this.pageParam.mediaName)
            .fontSize(UiTheme.fontSizeSection)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)

          Text(this.statusLabel)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(this.statusColor)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 类型徽标 + 素材 id + 帧数（图片/视频一眼可辨）
        Row({ space: UiTheme.gapS }) {
          MediaTypeBadge({ mediaType: this.pageParam.mediaType })

          Text(`素材 id ${this.pageParam.mediaId}`)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)

          Text('·')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)

          Text(this.frameCountText)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.statusHint)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        // 进度条（真实数据）
        // ★ 轨道显式取 `fillSoft`：组件默认的 `progressTrack` 几乎与白卡同色，
        //   在白底卡片里看不出"轨道还剩多少"，只能看到填充段。
        ProgressBar({
          ratio: this.progress,
          barColor: this.statusColor,
          barHeight: 8,
          trackColor: UiTheme.fillSoft
        })

        Row() {
          Text('分析进度')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
          Text(this.progressText)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textPrimary)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // ══════════════════ ② 分数卡 ══════════════════

  @Builder
  scoreCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapS }) {
        Text(this.isImage ? '辅助评估分数（单帧图片）' : '辅助评估分数（取最终帧）')
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Row({ space: UiTheme.gapS }) {
          Text(this.scoreText)
            .fontSize(UiTheme.fontSizeMetric)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.score > 0 ? this.severityColor : UiTheme.textSecondary)

          Text('BDI')
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textSecondary)
            .margin({ bottom: UiTheme.gapS })

          if (this.severityLabel.length > 0) {
            Text(this.severityLabel)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(this.severityColor)
              .margin({ bottom: UiTheme.gapS })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        Text('分数范围为 0–63，越高表示抑郁倾向越明显')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.inferenceText.length > 0) {
          Text(this.inferenceText)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
        }

        if (this.reportTimeText.length > 0) {
          Text(this.reportTimeText)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // ══════════════════ ③ 注意力热力图卡 ══════════════════

  /** 横向列表里的一格（缩略方块 + 帧号 + 该帧分数） */
  @Builder
  frameTile(frame: AnalysisFrameModel, index: number) {
    Column({ space: UiTheme.gapXs }) {
      HeatmapTile({
        heatmap: frame.heatmapData,
        faceDataUrl: frame.alignedFace,
        panelSize: STRIP_TILE_SIZE,
        // ★ 缩略方块统一用"逐格方块"（None）：72vp 上做平滑插值只会糊成一团，
        //   而且逐格观感与 Web 端截图逐格一致，便于比对。
        smooth: false,
        // ★ 72vp 放不下 4 个解剖区域框的文字，缩略图只承载"热点在哪"
        showAnnotations: false
      })

      Text(`#${pad2(frame.frameId)}`)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(
          index === this.heatView.focusedIndex ? UiTheme.primary : UiTheme.textPrimary
        )

      Text(`BDI ${frame.bdiScore.toFixed(1)}`)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
    }
    .padding(UiTheme.gapXs)
    .borderRadius(UiTheme.cardRadius)
    .borderWidth(index === this.heatView.focusedIndex ? 2 : 1)
    .borderColor(index === this.heatView.focusedIndex ? UiTheme.primary : UiTheme.divider)
    // ★ 缩略格底取 `fillSoft`：这一格嵌在白卡内部，用卡片白只会在白卡上"消失"，
    //   浅灰填充才让它自带边界，选中态的主色描边也才跳得出来。
    .backgroundColor(UiTheme.fillSoft)
    .onClick(() => {
      this.onPickFrame(index);
    })
  }

  /**
   * 横向逐帧列表 · **视频专用**
   *
   * 为什么是横向列表而不是网格：
   *   视频的热力图是**沿时间轴有序**的，横向排开才能一眼看出"注意力热点随时间的漂移"；
   *   网格会把时间顺序折行切断。
   * ★ **图片素材不渲染这个列表**：一张图只有 1 帧，画一条横滑列表只会诱导用户以为
   *   "还有别的帧"（这正是"分不清图片和视频"的来源之一）。
   */
  @Builder
  frameStrip() {
    Column({ space: UiTheme.gapS }) {
      Row({ space: UiTheme.gapS }) {
        Text(this.stripTitle)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        if (this.focusedIndex >= 0) {
          Text('回到最新')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.accent)
            .onClick(() => {
              this.focusedIndex = -1;
              this.scroller.scrollEdge(Edge.End);
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      List({ space: UiTheme.gapS, scroller: this.scroller }) {
        ForEach(this.heatView.frames, (frame: AnalysisFrameModel, index: number) => {
          ListItem() {
            this.frameTile(frame, index)
          }
        }, (frame: AnalysisFrameModel, index: number) => `heat-${frame.frameId}-${index}`)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(STRIP_SCROLLBAR_WIDTH)
      // ★ 主轴留 12vp 给滚动条：否则滚动条会盖住最后一格的右边框
      .padding({ bottom: UiTheme.gapM })
      // ★ 与页面外层纵向 Scroll 的嵌套滚动：本列表只吃横向手势，纵向交给外层
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
      .height(STRIP_ROW_HEIGHT)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 逐帧区底部：横滑提示（视频）/ 演示入口（无真实数据时） */
  @Builder
  stripFooter() {
    Column({ space: UiTheme.gapS }) {
      Text(
        this.isImage
          ? '图片素材只有 1 帧推理结果，没有可横滑的其它帧'
          : '← 左右滑动查看每一帧的热力图，点一格可固定主图 →'
      )
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)

      if (this.heatView.frames.length === 0) {
        Button('载入 3 帧合成演示数据（验证渲染）')
          .width('100%')
          .height(40)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.accent)
          .backgroundColor(Color.Transparent)
          .borderWidth(1)
          .borderColor(UiTheme.accent)
          .borderRadius(UiTheme.buttonRadius)
          .onClick(() => {
            this.loadSample();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 注意力热力图卡片 */
  @Builder
  heatmapCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapM }) {
        // ── 标题行 ──
        Row({ space: UiTheme.gapS }) {
          Text(this.isImage ? '注意力热力图（16×16 · 单帧图片）' : '注意力热力图（16×16 · 逐帧）')
            .fontSize(UiTheme.fontSizeSection)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.textPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)

          if (this.isSample) {
            Text('演示数据')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.accent)
              .borderWidth(1)
              .borderColor(UiTheme.accent)
              .borderRadius(UiTheme.gapXs)
              .padding({ left: UiTheme.gapS, right: UiTheme.gapS, top: 2, bottom: 2 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // ── 主图：大图 + 色带 + Top-3 解读（面板组件自带后两者） ──
        Column() {
          AttentionHeatmap({
            heatmap: this.heatView.heatmap,
            faceDataUrl: this.activeFrame === null ? '' : this.activeFrame.alignedFace,
            panelSize: this.panelSize > 0 ? this.panelSize : 200,
            smooth: true,
            showAnnotations: true
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.onContentArea(Number(newArea.width));
        })

        // ── 这一帧来自哪里（演示数据 / 固定帧 / 实时 / 归档）──
        Text(this.heatHint)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(this.isSample ? UiTheme.accent : UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Divider().color(UiTheme.divider)

        // ── 横向逐帧列表：**只给视频**（图片只有 1 帧，画列表是误导）──
        if (!this.isImage) {
          this.frameStrip()
        }
        this.stripFooter()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // ══════════════════ ④ 情绪曲线 + ⑤ 严重度分布（本轮实装）══════════════════

  /** 情绪曲线卡（视频=逐帧折线，图片=水平直线） */
  @Builder
  curveCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      EmotionCurveCard({ view: this.curveView })
    }
  }

  /** 严重度分布卡（视频=帧级环形图，图片=档位刻度尺） */
  @Builder
  severityCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      SeverityDistributionCard({ view: this.severityView })
    }
  }

  // ══════════════════ ⑥ 智能解读 / 错误 / 动作 ══════════════════

  @Builder
  vlmCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapS }) {
        Text('智能解读')
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(this.vlmText)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  errorCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Text(this.errorMsg)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.danger)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
  }

  /** 空态（既没有本机会话，也没有报告分数） */
  @Builder
  emptyCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapS }) {
        Text('尚无分析数据')
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('这个素材还没有跑过分析，或者本机缓存已被清理。点下方按钮可以现在开始分析。')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 重新分析（本机没有逐帧数据 / 上一次失败时的唯一出口） */
  @Builder
  reanalyzeRow() {
    Column({ space: UiTheme.gapXs }) {
      Button('重新分析该素材')
        .width('100%')
        .height(44)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.cardBackground)
        .backgroundColor(UiTheme.primary)
        .borderRadius(UiTheme.buttonRadius)
        .onClick(() => {
          this.pageParam.onReanalyze();
        })

      Text(this.isImage
        ? '图片只会跑一次推理，几秒内就能出结果'
        : '视频会按采样逐帧重新推理，耗时取决于时长')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 取消分析（弱化：★ 视频场景服务端早已算完，取消基本无效） */
  @Builder
  cancelRow() {
    Column({ space: UiTheme.gapXs }) {
      Button('取消分析')
        .width('100%')
        .height(44)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textSecondary)
        .backgroundColor(Color.Transparent)
        .borderWidth(1)
        .borderColor(UiTheme.divider)
        .borderRadius(UiTheme.buttonRadius)
        .onClick(() => {
          this.pageParam.onCancelAnalysis();
        })

      Text('提示：视频分析在服务端处理得很快，取消可能不会生效')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: UiTheme.gapL }) {
      PageHeader({
        title: '分析详情',
        subtitle: this.pageParam.mediaName,
        showBack: true,
        onBack: () => {
          this.pageParam.onBack();
        }
      })

      Scroll() {
        Column({ space: UiTheme.gapL }) {
          // ── ① 素材与状态卡 ──
          this.materialCard()

          if (this.hasData) {
            // ── ② 分数卡 ──
            this.scoreCard()

            // ── ③ 注意力热力图（大图 + 视频的逐帧列表）──
            this.heatmapCard()

            // ── ④ 情绪曲线（本轮的"空组件"之一）──
            this.curveCard()

            // ── ⑤ 严重度分布（本轮的"空组件"之二）──
            this.severityCard()

            // ── ⑥ VLM 文本解读（有才显示：不是所有素材都会触发）──
            if (this.vlmText.length > 0) {
              this.vlmCard()
            }
          } else {
            // 既没有本机会话也没有报告分数：一个都不画，避免四张空卡片堆在一起
            this.emptyCard()
          }

          // ── ⑦ 错误提示 ──
          if (this.errorMsg.length > 0) {
            this.errorCard()
          }

          // ── ⑧ 动作：重新分析 / 取消分析 ──
          if (this.canReanalyze && this.status !== TaskStatus.running) {
            this.reanalyzeRow()
          }
          if (this.isLive && this.status === TaskStatus.running) {
            this.cancelRow()
          }
        }
        .width('100%')
        .padding({ bottom: UiTheme.gapXl })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: UiTheme.pagePadding, right: UiTheme.pagePadding, top: UiTheme.gapL })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }
}
