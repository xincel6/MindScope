/**
 * AnalysisDetailPage · 分析详情页
 *
 * 页面契约（★ 元信息与快照仍然全部走参数）：
 * ```ts
 * const param = new AnalysisDetailPageParam();
 * param.mediaName = 'interview.mp4';
 * param.status = TaskStatus.running;
 * param.progress = 0.63;
 * param.onBack = () => { stack.pop(); };
 * ```
 *
 * ────────────────── 本轮（热力图实装轮）改了什么 ──────────────────
 * ① **注意力热力图不再占位**：接入 `AttentionHeatmap`（大图 + 色带 + Top-3 解读）。
 * ② 新增**横向逐帧列表**：为"视频切分"预留的查看形态 ——
 *    视频素材服务端会按约 60 帧采样逐帧推送（`services/frame_processor.py:144`），
 *    所以这里用可横向滑动的一排小方块承载**每一帧各自的热力图**，
 *    点任意一格即可把主图固定到那一帧（再点最右一格回到最新帧）。
 * ③ 折线图、饼图仍是占位（本轮不在范围内，保持原样）。
 *
 * ────────────────── ★ 本页为什么打破了"页面不读 store"的纪律 ──────────────────
 * 工程通用纪律是「页面只吃参数、不 import store」。但热力图有一个绕不过去的硬约束：
 *
 *   **逐帧数据必须在帧到达的当下就进入 UI，而不是等窗口层来同步参数。**
 *
 *   窗口层的 `syncDetailParam()` 只在"切页签 / 点工作台卡片"这类时机被调用
 *   （`MainPage.ets` 的 `syncTabParam → syncWorkbenchParam → syncDetailParam`），
 *   WebSocket 帧到达时**不会**触发它。所以若只靠参数，页面上的热力图会停在
 *   "进入本页时那一帧"，看起来像卡死 —— 本轮验证会直接失败。
 *
 *   而 `AppStore.analysisFrameHistory()` 读的是桥接器里的 `@Trace` 数组本身，
 *   每来一帧都整体替换引用，`@Computed` 必然失效重算 —— 这是 ArkUI 里最可靠的
 *   一条响应式链路，也正是 `WorkbenchPage` 当初开这道口子的同一条理由
 *   （见 `WorkbenchPage.ets` 文件头）。
 *
 * 纪律的**核心部分仍然保留**：
 *   · 本页**只读** store，不调用任何写方法；
 *   · 动作（返回、取消分析）仍然走注入的回调，不碰路由栈、不发请求；
 *   · 媒体名/类型/快照分数等元信息仍然只认参数，不从 store 反推。
 *
 * ★ 返回不停止分析（用户既有要求）：分析会话挂在 `AppStore` 单例上，
 *   本页 `aboutToDisappear` **故意不调** `stopAnalysis()`，
 *   这样用户回到工作台后「当前任务」仍在推进，再点回来能看到最新进度。
 */

import { UiTheme } from '../common/UiTheme';
import { display } from '@kit.ArkUI';
import { AppStore } from '../store/AppStore';
import { AnalysisDetailPageParam } from '../types/PageParams';
import { AnalysisFrameModel, TaskStatus } from '../types/Index';
import { PageHeader } from '../components/PageHeader';
import { RippleCard } from '../components/RippleCard';
import { ProgressBar } from '../components/common/ProgressBar';
import { AttentionHeatmap } from '../components/charts/AttentionHeatmap';
import { HeatmapTile } from '../components/charts/HeatmapTile';
import { makeSampleFrames } from '../components/charts/HeatmapSampleData';
import {
  buildHeatmapView, HeatmapView, HeatSource, heatSourceHint
} from '../components/charts/HeatmapViewModel';

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
 * ★ `display.getDefaultDisplaySync()` 自 API 9 起可用、**不需要任何权限**
 *   （`@ohos.display.d.ts:94`，权限申请只出现在虚拟屏相关接口上）。
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
  /** ★ 本页入参（元信息 / 历史快照 / 动作回调） */
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
   *   用户点"载入 3 帧合成演示数据"按钮才会填充（`loadSample()`）。
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

  /** 逐帧序列（帧一到就整体替换引用 → 本页立即重算） */
  @Computed
  get liveFrames(): AnalysisFrameModel[] {
    return this.app.analysisFrameHistory();
  }

  /** 热力图区的取数结果（主图与横向列表的**唯一**数据入口） */
  @Computed
  get heatView(): HeatmapView {
    return buildHeatmapView(
      this.liveFrames,
      this.sampleFrames,
      this.pageParam.followLiveTask,
      this.focusedIndex,
      this.app.analysisLastFrame
    );
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

  // ══════════════════ 实时读数（实时模式取 store，快照模式取参数）══════════════════

  /**
   * 帧数 · 实时模式必须取 store
   * ★ 因为它由 `AnalysisState.frameCount` 每帧自增，是这一轮唯一能证明"数据在流动"的
   *   实时量；而参数里的 `frameCount` 只在窗口层同步时被写入（不是每帧）。
   */
  @Computed
  get liveFrameCount(): number {
    return this.pageParam.followLiveTask ? this.app.analysisFrameCount : this.pageParam.frameCount;
  }

  /** 最新分数 · 实时模式取 store（每帧刷新），快照模式取参数（冻结的报告分数） */
  @Computed
  get liveScore(): number {
    return this.pageParam.followLiveTask ? this.app.analysisScore : this.pageParam.bdiScore;
  }

  /** 进度 0–1 */
  @Computed
  get liveProgress(): number {
    return this.pageParam.followLiveTask ? this.app.analysisProgress : this.pageParam.progress;
  }

  /** 服务端连接状态文案（自带 socket 状态，值直接来自桥接器的 @Trace 字段） */
  @Computed
  get liveScoreText(): string {
    const score: number = this.liveScore;
    return score > 0 ? score.toFixed(1) : '--';
  }

  // ══════════════════ 派生文案 ══════════════════

  /** 状态中文标签 */
  @Computed
  get statusLabel(): string {
    const status: TaskStatus = this.pageParam.status;
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
    const status: TaskStatus = this.pageParam.status;
    if (status === TaskStatus.failed) {
      return UiTheme.danger;
    }
    if (status === TaskStatus.done && this.pageParam.severityColor.length > 0) {
      return this.pageParam.severityColor;
    }
    return UiTheme.primary;
  }

  /** 进度百分比文案 */
  @Computed
  get progressText(): string {
    const ratio: number = this.liveProgress;
    if (!Number.isFinite(ratio) || ratio <= 0) {
      return '0%';
    }
    const percent: number = ratio >= 1 ? 100 : Math.round(ratio * 100);
    return `${percent}%`;
  }

  /** 是否已经有分数可展示 */
  @Computed
  get hasScore(): boolean {
    return this.liveScore > 0;
  }

  /** 顶部一句话状态说明 */
  @Computed
  get statusHint(): string {
    // ★ 历史快照（从「最近使用的素材」进入）：没有实时会话，不能承诺"收帧中"这类实时语义
    if (!this.pageParam.followLiveTask) {
      return '这是该素材最近一次分析的报告快照，逐帧图表不随实时数据刷新';
    }
    const status: TaskStatus = this.pageParam.status;
    if (status === TaskStatus.running) {
      return `服务端正在逐帧推理，已收到 ${this.liveFrameCount} 帧`;
    }
    if (status === TaskStatus.done) {
      return '分析已完成，报告已写入服务端';
    }
    if (status === TaskStatus.failed) {
      return '分析中断，可返回工作台重新发起';
    }
    return '等待开始';
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

  /** 横向列表的标题文案（把"有多少帧"直接写出来） */
  @Computed
  get stripTitle(): string {
    const count: number = this.heatView.frames.length;
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

  // ══════════════════ 图表占位块 ══════════════════

  /**
   * 占位块 · 明确写出"这里将来放什么、什么时候有"
   * ★ 不做灰色假图表：拿假数据画出来的图，评审时无法区分"画错了"与"还没画"。
   */
  @Builder
  chartPlaceholder(title: string, hint: string, chartHeight: number) {
    Column({ space: UiTheme.gapS }) {
      Text(title)
        .fontSize(UiTheme.fontSizeBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)

      Column({ space: UiTheme.gapXs }) {
        Text('图表组件待实现')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
        Text(hint)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height(chartHeight)
      .borderRadius(UiTheme.cardRadius)
      .backgroundColor(UiTheme.fillSoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ══════════════════ 注意力热力图 ══════════════════

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
    .backgroundColor(UiTheme.cardBackground)
    .onClick(() => {
      this.onPickFrame(index);
    })
  }

  /**
   * 横向逐帧列表 · **为视频切分预留的查看形态**
   *
   * 为什么是横向列表而不是网格：
   *   视频的热力图是**沿时间轴有序**的，横向排开才能一眼看出"注意力热点随时间的漂移"；
   *   网格会把时间顺序折行切断。等下一轮做真正的视频切分（自定义区间、导出片段）时，
   *   这里只要把"按顺序 ForEach"换成"按切分区间分组"即可，方块组件不用改。
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

  /** 横滑提示 + 演示按钮（没有真实数据时给出可点的验证入口） */
  @Builder
  stripFooter() {
    Column({ space: UiTheme.gapS }) {
      Text('← 左右滑动查看每一帧的热力图，点一格可固定主图 →')
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

  /** 注意力热力图卡片（本轮实装的主角） */
  @Builder
  heatmapCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapM }) {
        // ── 标题行 ──
        Row({ space: UiTheme.gapS }) {
          Text('注意力热力图（16×16）')
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
        //    ★ 用 `onAreaChange` 量出可用宽度再决定边长：视频切分视图将来会有
        //      左右分栏，写死 200 会在窄屏上溢出、宽屏上留白。
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

        // ── 这一帧来自哪里（演示数据 / 固定帧 / 实时 / 快照）──
        Text(this.heatHint)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(this.isSample ? UiTheme.accent : UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Divider().color(UiTheme.divider)

        // ── 横向逐帧列表（视频切分视图）──
        this.frameStrip()
        this.stripFooter()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
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

              Row({ space: UiTheme.gapS }) {
                Text(this.pageParam.mediaTypeLabel)
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
                Text('·')
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
                Text(`素材 id ${this.pageParam.mediaId}`)
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
                Text('·')
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
                Text(`${this.liveFrameCount} 帧`)
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
              }
              .width('100%')

              Text(this.statusHint)
                .fontSize(UiTheme.fontSizeBody)
                .fontColor(UiTheme.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Start)

              // 进度条（真实数据）
              ProgressBar({
                ratio: this.liveProgress,
                barColor: this.statusColor,
                barHeight: 8
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

          // ── ② 分数卡（重要分数用大字号 32vp，符合规范） ──
          RippleCard({ _enabled: false, _clickable: false }) {
            Column({ space: UiTheme.gapS }) {
              Text('辅助评估分数')
                .fontSize(UiTheme.fontSizeSection)
                .fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.textPrimary)
                .width('100%')
                .textAlign(TextAlign.Start)

              Row({ space: UiTheme.gapS }) {
                Text(this.liveScoreText)
                  .fontSize(UiTheme.fontSizeMetric)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.hasScore ? this.statusColor : UiTheme.textSecondary)

                Text('BDI')
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.textSecondary)
                  .margin({ bottom: UiTheme.gapS })

                if (this.pageParam.severityLabel.length > 0) {
                  Text(this.pageParam.severityLabel)
                    .fontSize(UiTheme.fontSizeBody)
                    .fontColor(this.pageParam.severityColor)
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
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ── ③ 注意力热力图（★ 本轮实装）──
          this.heatmapCard()

          // ── ④ 其余图表占位区（本轮不在范围内）──
          RippleCard({ _enabled: false, _clickable: false }) {
            Column({ space: UiTheme.gapL }) {
              this.chartPlaceholder(
                '情绪曲线（折线图）',
                '逐帧 BDI 分数的走势，按帧序号为横轴',
                140
              )
              this.chartPlaceholder(
                '严重度分布（饼图）',
                '本次分析各档位帧数占比',
                140
              )
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ── ⑤ VLM 文本解读（有才显示：不是所有素材都会触发） ──
          if (this.pageParam.vlmText.length > 0) {
            RippleCard({ _enabled: false, _clickable: false }) {
              Column({ space: UiTheme.gapS }) {
                Text('智能解读')
                  .fontSize(UiTheme.fontSizeSection)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(UiTheme.textPrimary)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                Text(this.pageParam.vlmText)
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.textPrimary)
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }

          // ── ⑥ 错误提示 ──
          if (this.pageParam.errorMsg.length > 0) {
            RippleCard({ _enabled: false, _clickable: false }) {
              Text(this.pageParam.errorMsg)
                .fontSize(UiTheme.fontSizeBody)
                .fontColor(UiTheme.danger)
                .width('100%')
                .textAlign(TextAlign.Start)
            }
          }

          // ── ⑦ 取消分析（弱化：★ 视频场景服务端早已算完，取消基本无效） ──
          //    ★ 只在"实时任务且正在跑"时出现：历史快照没有可取消的会话
          if (this.pageParam.followLiveTask && this.pageParam.status === TaskStatus.running) {
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
