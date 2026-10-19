/**
 * AnalysisHeatmapCard · 工作台分析区的**注意力热力图卡**（从原分析详情页搬入）
 *
 * 内容与原「分析详情」的热力图区逐项一致：
 *   · 16×16 热度矩阵 + 对齐人脸 + 色带图例 + Top-3 医学解读；
 *   · **视频**：横向逐帧列表（最多 24 格），点一格固定主图，可「回到最新」；
 *   · **图片**：只有 1 帧，不渲染横向列表（画了会让人误以为还有别的帧）；
 *   · 无真实数据时提供「载入合成演示数据」入口，界面会明确标注「演示数据」。
 *
 * ────────────────── 数据来源与硬规则 ──────────────────
 * 本组件**不读 store**：`frames` 由工作台按当前查看素材的 mediaId 从
 * `AppStore.analysisSessionOf()` 取好后传入。取不到就是空数组，界面老实说
 * "本机未保留逐帧数据"，**绝不跨素材兜底**（BUG-14 的根因就是那条兜底）。
 * 图片的"最多 1 帧"由调用方的 `resolveFrames()` 归一，本组件不再另算。
 *
 * ────────────────── 尺寸测量的坑（沿用原实现）──────────────────
 * `onAreaChange` 回填的 `Area.width` 是**物理像素**，不是 vp；必须除以屏幕密度
 * 再传给 `AttentionHeatmap.panelSize`，否则高密度屏上主图会溢出卡片。
 * 主图边长夹在 [200, 300] 并向下取整，避免非整数边长在格子缝处出现细线。
 *
 * ★ 本组件只画卡片**内容**，白卡底/圆角/投影由调用方套 `RippleCard` 提供
 *   （与 `EmotionCurveCard` / `SeverityDistributionCard` 的用法一致）。
 */

import { display } from '@kit.ArkUI';
import { UiTheme } from '../../common/UiTheme';
import { AnalysisFrameModel, MediaType } from '../../types/Index';
import { AttentionHeatmap } from '../charts/AttentionHeatmap';
import { HeatmapTile } from '../charts/HeatmapTile';
import { makeSampleFrames } from '../charts/HeatmapSampleData';
import {
  buildHeatmapView, HeatmapView, HeatSource, heatSourceHint
} from '../charts/HeatmapViewModel';

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
export struct AnalysisHeatmapCard {
  /** 本素材的帧（按 mediaId 取好；图片应已归一为最多 1 帧） */
  @Param frames: AnalysisFrameModel[] = [];

  /** 素材类型 · 决定是否画逐帧列表 */
  @Param mediaType: MediaType = MediaType.image;

  /** 本素材是不是当前 live 会话（决定文案与 heatView 的 live/snapshot 标记） */
  @Param isLive: boolean = false;

  /** 是否有本机会话（false 时明确提示"本机未保留逐帧数据"） */
  @Param hasSession: boolean = false;

  /** 横向列表的滚动控制器（用于把最新一帧滚进视野） */
  private scroller: Scroller = new Scroller();

  /** 屏幕密度（px / vp）· 用于把 onAreaChange 报的物理像素换算成 vp */
  private density: number = 3.0;

  /** 主图方块边长（vp）· 随卡片内容宽度收敛，避免"先画小再跳大" */
  @Local panelSize: number = 0;

  /** 用户手动选中的帧下标（-1 = 没选过，跟随最新一帧） */
  @Local focusedIndex: number = -1;

  /**
   * 合成演示帧（只在没有任何真实热度数据时使用，界面上会标注"演示数据"）
   * ★ 默认必须是**空数组**：有真实数据时绝不能拿合成帧顶替，那一帧的临床含义会被完全误读。
   *   用户点"载入合成演示数据"按钮才会填充（`loadSample()`）。
   */
  @Local sampleFrames: AnalysisFrameModel[] = [];

  aboutToAppear(): void {
    this.density = screenDensity();
  }

  /** 是否图片（本卡所有"画不画逐帧列表"的分叉都看它） */
  @Computed
  get isImage(): boolean {
    return this.mediaType === MediaType.image;
  }

  /** 热力图区的取数结果（主图与横向列表的唯一数据入口） */
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

  /**
   * 是否正在使用演示数据（用于把标题旁边打上标注）
   * ★ 必须同时要求 frames 非空：`buildHeatmapView` 在"既没有真实帧、也没有演示帧"时
   *   也会返回 source = sample，但那是空态，不是演示数据 —— 否则标题会挂着
   *   「演示数据」牌子、方块里却写着「等待推理数据」，自相矛盾（真机截图已复现）。
   */
  @Computed
  get isSample(): boolean {
    return this.heatView.source === HeatSource.sample && this.heatView.frames.length > 0;
  }

  /** 没有任何真实热度数据时的原因说明（比"尚无热度数据"更可行动） */
  @Computed
  get emptyHint(): string {
    if (this.isLive) {
      return '等待首帧推理结果…';
    }
    if (this.hasSession) {
      return '本次分析没有产出可用的热度矩阵';
    }
    return '本机未保留逐帧数据；重新分析该素材后即可查看热力图';
  }

  /** 主图说明文案（说清"这一格画的是哪一帧、数据从哪来"） */
  @Computed
  get heatHint(): string {
    const frame: AnalysisFrameModel | null = this.activeFrame;
    const view: HeatmapView = this.heatView;
    if (frame === null) {
      return this.emptyHint;
    }
    // ★ 图片只有 1 帧：服务端的 frame_id 可能是复用的计数（实测图片也拿到 10），
    //   再套 `heatSourceHint` 会显示"左右滑动可回看任意一帧"，与下方"没有可横滑的其它帧"矛盾。
    if (this.isImage) {
      if (view.source === HeatSource.sample) {
        return '当前为演示数据（不是真实推理结果）';
      }
      return `单帧图片的推理结果 · BDI ${frame.bdiScore.toFixed(1)}`;
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
    // ★ 列表是"按时间均匀抽取"的渲染窗口，不是"最后 N 帧"：说清它覆盖整段，
    //   否则用户会以为视频只有这 24 帧（服务端一批就是 24 帧，正好全同）。
    return `逐帧热力图（视频切分视图）· 均匀抽取 ${count} 格`;
  }

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
   *   "还有别的帧"。
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

  /** 逐帧区底部：横滑提示（视频）/ 图片单帧说明 */
  @Builder
  stripFooter() {
    Text(
      this.isImage
        ? '图片素材只有 1 帧推理结果，没有可横滑的其它帧'
        : '← 左右滑动查看；热力图每 2 帧一张，BDI 每 24 帧推理一次 →'
    )
      .fontSize(UiTheme.fontSizeCaption)
      .fontColor(UiTheme.textSecondary)
      .width('100%')
      .textAlign(TextAlign.Center)
  }

  /**
   * 无热度数据时的**紧凑空态**
   *
   * ★ 不能把 300vp 的灰色占位方块直接摆在主页面：历史素材没有逐帧数据时，
   *   它会占掉大半屏，而且方块里那句「等待推理数据…」会让人以为分析还在跑。
   *   这里换成"原因说明 + 演示数据入口"，高度约原来的三分之一；
   *   载入演示帧后自动切回完整的热力图面板。
   */
  @Builder
  emptyBlock() {
    Column({ space: UiTheme.gapM }) {
      Row({ space: UiTheme.gapM }) {
        Column() {
          Text('热')
            .fontSize(20)
            .fontColor(UiTheme.textSecondary)
        }
        .width(48)
        .height(48)
        .borderRadius(12)
        .backgroundColor(UiTheme.fillSoft)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(this.emptyHint)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 次要入口：只是验证渲染用，不让它抢走"重新分析"的主按钮感
      Button('载入演示热力图（仅验证渲染）')
        .width('100%')
        .height(36)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.accent)
        .backgroundColor(Color.Transparent)
        .borderWidth(1)
        .borderColor(UiTheme.divider)
        .borderRadius(UiTheme.buttonRadius)
        .onClick(() => {
          this.loadSample();
        })
    }
    .width('100%')
    .padding({ top: UiTheme.gapS, bottom: UiTheme.gapS })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: UiTheme.gapM }) {
      // ── 标题行：标题 + 副标题 + 演示数据标记（标题不再带长括号，避免窄屏折行）──
      Row({ space: UiTheme.gapS }) {
        Column({ space: UiTheme.gapXs }) {
          Text('注意力热力图')
            .fontSize(UiTheme.fontSizeSection)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.textPrimary)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)

          Text(this.isImage ? '16×16 · 单帧图片 · 单次推理' : '16×16 · 逐帧采样（每 24 帧推理一次）')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

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

      if (this.heatView.frames.length === 0) {
        // 没有真实帧、也没有演示帧：用紧凑空态，不画 300vp 灰色方块
        this.emptyBlock()
      } else {
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
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
