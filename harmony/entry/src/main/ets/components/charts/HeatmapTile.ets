/**
 * HeatmapTile · 注意力热力图**方块**（一个可复用的最小单元，尺寸可传）
 *
 * ────────────────── 它解决什么问题 ──────────────────
 * 工作台分析区不只显示"最新一帧"：
 *   · **图片**素材：**只有 1 帧**（服务端一次推理只推一帧；端上 `resolveFrames()`
 *     也按类型归一成 1 帧，即使旧服务端推了重复帧）；
 *   · **视频**素材：服务端按 ~60 帧采样逐帧推送，每一帧的对齐人脸与热度矩阵都不同。
 * 所以页面上必须能横向排开**很多张**热力图（视频切分视图，**图片不渲染这个列表**），
 * 而"最新一帧大图"只是其中最右边那张的放大版。
 *
 * 于是把"一张人脸 + 一层热度矩阵 + 4 个解剖区域框"抽成这个文件里的一个组件，
 * 用 `size` 参数区分用途：
 *   · `size = 200` → 工作台分析区主图（与 Web 端 `SIZE = 200` 同口径）
 *   · `size = 72/88` → 横向逐帧列表里的小方块（视频切分缩略）
 *
 * ────────────────── 与 Web 端的对应关系 ──────────────────
 * Web 实现：`dashboard/src/components/center-panel/FacePreview.vue`
 *   单张 200×200 Canvas：
 *     ① drawImage(人脸 JPEG) → 铺满画布
 *     ② 离屏 16×16 fillRect 网格（每格 fillStyle = heatColor(v)，alpha 固定 0.8）
 *     ③ 把离屏画布以 globalAlpha = 0.4 贴回 → 等效每像素 alpha = 0.8 × 0.4 = 0.32
 *     ④ 4 个解剖区域虚线圆角框 + 文字标注
 *
 * 鸿蒙实现：
 *   ③ 被两件事替代：16×16 矩阵 → 16×16 PixelMap（`image.createPixelMapSync`），
 *   再用 `<Image>` 放大铺满 + `.opacity(0.32)`。因为 16 个格子互不重叠，
 *   「逐格 0.32」与「整层 0.32」在数学上完全等价，不会出现边缘叠色。
 *   底图直接用 `<Image>` 吃 `data:image/jpeg;base64,...`（不需要自己解码），
 *   三层用 `Stack` 叠放，Canvas 只画标注框。
 *
 * ★ 关键 API 均已在 API 23 SDK 的 `.d.ts` 中核实（见报告"证据清单"一节）：
 *   image.createPixelMapSync(ArrayBuffer, InitializationOptions)  @since 9
 *   Image(src: PixelMap | ResourceStr | ...) / .interpolation() / .opacity()  @since 8/9
 *   CanvasRenderingContext2D.roundRect(...)  @since 20   ← 本工程 compatibleSdkVersion = 23，可用
 *   CanvasRenderingContext2D.setLineDash(...)  @since 8
 *
 * ★ 每个方块**自己持有并释放** PixelMap：横向列表里可能有几十个方块，
 *   把 PixelMap 集中放在父组件里会在列表重排时漏释放（native 内存不受 ArkTS GC 管辖）。
 */

import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UiTheme } from '../../common/UiTheme';

/** 规则人脸坐标系边长 · Web 端注释里的解剖关键点基准是 128×128 */
export const CANON_FACE_SIZE: number = 128;

/**
 * 热力图叠加不透明度
 * Web 端 = 每格 alpha 0.8 × globalAlpha 0.4 = 0.32
 */
export const HEAT_OVERLAY_ALPHA: number = 0.32;

/** 色带五段停靠点 · 与 Web 端 CSS `linear-gradient(to right, #00f, #0ff, #0f0, #ff0, #f00)` 一致 */
export const HEAT_COLORMAP: Array<[string, number]> = [
  ['#0000FF', 0.0],
  ['#00FFFF', 0.25],
  ['#00FF00', 0.5],
  ['#FFFF00', 0.75],
  ['#FF0000', 1.0]
];

/** 解剖区域标注框（canonical 128×128 坐标，逐值照搬 Web 端 `regions`） */
export class RegionBox {
  label: string;
  cx: number;
  cy: number;
  color: string;

  constructor(label: string, cx: number, cy: number, color: string) {
    this.label = label;
    this.cx = cx;
    this.cy = cy;
    this.color = color;
  }
}

export const HEAT_REGIONS: RegionBox[] = [
  new RegionBox('眶周', 38, 52, 'rgba(0,230,180,0.5)'),
  new RegionBox('眶周', 90, 52, 'rgba(0,230,180,0.5)'),
  new RegionBox('口周', 64, 92, 'rgba(77,138,240,0.5)'),
  new RegionBox('眉间', 64, 36, 'rgba(240,160,40,0.5)')
];

/** Top-3 热点解读的一条 */
export class HeatHotspot {
  region: string;
  percent: string;

  constructor(region: string, percent: string) {
    this.region = region;
    this.percent = percent;
  }
}

/**
 * 热力图纯函数工具 · 无状态、无副作用
 * 这一层是 Web 端 `heatColor()` + `hotspots` computed 的逐行移植，
 * **算法口径必须与 Web 完全一致**，否则同一帧数据两端颜色对不上。
 *
 * 一致性由离线测试守卫：`node harmony/scripts/test-heatmap-consistency.mjs`
 * （1030 个采样点逐位比对 + 源码文本级检查）
 */
export class HeatmapUtil {
  /**
   * 注意力值 [0,1] → RGB 三通道（0–255）
   * 逐位等价于 Web 端：
   *   r = clamp(t<0.25 ? 0 : t<0.5 ? (t-0.25)*4 : 1)
   *   g = clamp(t<0.25 ? t*4 : t<0.75 ? 1 : (1-t)*4)
   *   b = clamp(t<0.5  ? (0.5-t)*4 : 0)
   */
  public static heatRgb(t: number): number[] {
    const v: number = t < 0 ? 0 : (t > 1 ? 1 : t);

    let r: number;
    if (v < 0.25) {
      r = 0;
    } else if (v < 0.5) {
      r = (v - 0.25) * 4;
    } else {
      r = 1;
    }

    let g: number;
    if (v < 0.25) {
      g = v * 4;
    } else if (v < 0.75) {
      g = 1;
    } else {
      g = (1 - v) * 4;
    }

    let b: number;
    if (v < 0.5) {
      b = (0.5 - v) * 4;
    } else {
      b = 0;
    }

    const rr: number = Math.round(Math.min(Math.max(r, 0), 1) * 255);
    const gg: number = Math.round(Math.min(Math.max(g, 0), 1) * 255);
    const bb: number = Math.round(Math.min(Math.max(b, 0), 1) * 255);
    return [rr, gg, bb];
  }

  /** Canvas `fillStyle` 用的颜色串（保留 Web 端的 0.8 alpha 口径，便于逐像素比对） */
  public static heatColor(t: number): string {
    const rgb: number[] = HeatmapUtil.heatRgb(t);
    return `rgba(${rgb[0]},${rgb[1]},${rgb[2]},0.8)`;
  }

  /**
   * Top-3 注意力热点 → 解剖区域名（移植 Web 端 `hotspots` computed）
   * 区域判定顺序与阈值**必须与 Web 端一致**：
   *   眉间/前额 → 眶周（眼轮匝肌）→ 口周（降口角肌）→ 鼻唇沟 → 面部中央区域
   */
  public static hotspots(data: number[][], topN: number): HeatHotspot[] {
    if (data.length === 0) {
      return [];
    }
    const h: number = data.length;
    const w: number = data[0].length;
    if (w === 0) {
      return [];
    }

    // 只保留 topN 个最大值的坐标（O(h*w*topN)，16×16 下可忽略；避免全量排序）
    const bestX: number[] = [];
    const bestY: number[] = [];
    const bestV: number[] = [];
    for (let y = 0; y < h; y++) {
      const row: number[] = data[y];
      for (let x = 0; x < w; x++) {
        const v: number = row[x];
        let insertAt: number = bestV.length;
        for (let k = 0; k < bestV.length; k++) {
          if (v > bestV[k]) {
            insertAt = k;
            break;
          }
        }
        if (insertAt < topN) {
          bestX.splice(insertAt, 0, x);
          bestY.splice(insertAt, 0, y);
          bestV.splice(insertAt, 0, v);
          if (bestV.length > topN) {
            bestX.pop();
            bestY.pop();
            bestV.pop();
          }
        }
      }
    }

    const out: HeatHotspot[] = [];
    for (let i = 0; i < bestV.length; i++) {
      const regionX: number = bestX[i] / w;
      const regionY: number = bestY[i] / h;
      out.push(new HeatHotspot(HeatmapUtil.regionOf(regionX, regionY), (bestV[i] * 100).toFixed(1)));
    }
    return out;
  }

  /** 归一化坐标 → 解剖区域名（阈值逐条照搬 Web 端） */
  private static regionOf(regionX: number, regionY: number): string {
    if (regionY < 0.3 && regionX > 0.3 && regionX < 0.7) {
      return '眉间/前额区域';
    }
    if (regionY > 0.25 && regionY < 0.45 && (regionX < 0.35 || regionX > 0.65)) {
      return '眶周区域（眼轮匝肌）';
    }
    if (regionY > 0.5 && regionX > 0.3 && regionX < 0.7) {
      return '口周区域（降口角肌）';
    }
    if (regionY > 0.4 && regionY < 0.55 && regionX > 0.35 && regionX < 0.65) {
      return '鼻唇沟区域';
    }
    return '面部中央区域';
  }
}

/**
 * 注意力热力图方块 · **尺寸可传的最小复用单元**
 *
 * 用法（父组件）：
 * ```ts
 * HeatmapTile({
 *   heatmap: frame.heatmapData,          // number[][] 16×16，值域 0..1
 *   faceDataUrl: frame.alignedFace,      // 'data:image/jpeg;base64,...' 或裸 base64
 *   size: 88,                            // 方块边长（vp）
 *   smooth: true
 * })
 * ```
 */
@ComponentV2
export struct HeatmapTile {
  /** 16×16 注意力矩阵（行优先，`data[y][x]`），空数组表示尚无数据 */
  @Param heatmap: number[][] = [];

  /** 对齐人脸图 · 支持 `data:image/...;base64,` 前缀，也支持裸 base64（内部自动补前缀） */
  @Param faceDataUrl: string = '';

  /**
   * 方块边长（vp）· 工作台分析区主图用 200，横向列表缩略用 72～88
   *
   * ★ 字段名**不能叫 `size`**：`@Component` 基类 `CustomComponent` 已有一个
   *   `size(value: SizeOptions)` 属性方法，同名会报
   *   `Property 'size' ... is not assignable to the same property in base type 'CustomComponent'`。
   *   这是**只有组件从入口可达时才会暴露**的编译错误（本项目未引用的 .ets 不进编译器）。
   */
  @Param panelSize: number = 200;

  /**
   * 是否把 16×16 平滑放大
   *  · true  → `ImageInterpolation.High`，观感接近连续热力图（更适合临床阅读）
   *  · false → `ImageInterpolation.None`，逐像素方块，与 Web 端截图**逐格一致**
   */
  @Param smooth: boolean = true;

  /** 是否画 4 个解剖区域虚线框与文字（缩略方块太小，字会糊，所以可关） */
  @Param showAnnotations: boolean = true;

  /** 16×16 PixelMap（把矩阵"物化"成图片，交给 Image 组件放大） */
  @Local private heatPm: image.PixelMap | undefined = undefined;

  /** 标注层画布上下文（只有 4 个虚线框 + 4 个文字） */
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private annCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;

  /**
   * 本方块当前的边长快照
   * ★ 不能在 `drawAnnotations()` 里直接读 `this.size`：@Param 在绘制期读值虽可行，
   *   但把"几何量"固定成一次快照，能保证"画框用的比例"与"Stack 实际尺寸"永远一致。
   */
  @Local private boxSize: number = 200;

  aboutToAppear(): void {
    this.boxSize = this.panelSize;
    this.rebuildHeatPixelMap();
  }

  /** 新的一帧到达 · ⚠️ 依赖上游"整体替换数组"（`state.lastFrame = frame` / 序列 concat），不是原地改元素 */
  @Monitor('heatmap')
  private onHeatmapChanged(): void {
    this.rebuildHeatPixelMap();
    if (this.canvasReady) {
      this.drawAnnotations();
    }
  }

  @Monitor('panelSize', 'showAnnotations')
  private onGeometryChanged(): void {
    this.boxSize = this.panelSize;
    if (this.canvasReady) {
      this.drawAnnotations();
    }
  }

  @Monitor('faceDataUrl')
  private onFaceChanged(): void {
    if (this.canvasReady) {
      this.drawAnnotations();
    }
  }

  aboutToDisappear(): void {
    // ★ 组件销毁必须释放 PixelMap，否则 native 内存不回收。
    //   横向列表里方块会被反复创建/销毁，这一条尤其重要。
    this.releaseHeatPixelMap();
  }

  /** 裸 base64 → 补上 data URL 前缀（服务端可能两种都给） */
  @Computed
  get faceSrc(): string {
    const raw: string = this.faceDataUrl;
    if (raw.length === 0) {
      return '';
    }
    if (raw.startsWith('data:')) {
      return raw;
    }
    // ★ 服务端 `_encode_base64()` 实际编码的是 JPEG（不是 Web 端注释写的 PNG）
    return `data:image/jpeg;base64,${raw}`;
  }

  @Computed
  get hasData(): boolean {
    return this.heatPm !== undefined;
  }

  /** 医学解读文案（与 Web 端 `medical-notes` 的句子结构一致） */
  @Computed
  get hotspotText(): string {
    const list: HeatHotspot[] = HeatmapUtil.hotspots(this.heatmap, 3);
    if (list.length === 0) {
      return '';
    }
    let text: string = `重点关注 ${list[0].region}（${list[0].percent}%）`;
    if (list.length > 1) {
      text += `，其次 ${list[1].region}（${list[1].percent}%）`;
    }
    return text;
  }

  /** 矩阵 → 16×16 RGBA PixelMap（本工程里唯一的"矩阵变图片"入口） */
  private rebuildHeatPixelMap(): void {
    const data: number[][] = this.heatmap;
    if (data.length === 0 || data[0].length === 0) {
      this.releaseHeatPixelMap();
      return;
    }
    const rows: number = data.length;
    const cols: number = data[0].length;

    const bytes: Uint8Array = new Uint8Array(rows * cols * 4);
    for (let y = 0; y < rows; y++) {
      const row: number[] = data[y];
      for (let x = 0; x < cols; x++) {
        const rgb: number[] = HeatmapUtil.heatRgb(row[x]);
        const i: number = (y * cols + x) * 4;
        bytes[i] = rgb[0];
        bytes[i + 1] = rgb[1];
        bytes[i + 2] = rgb[2];
        bytes[i + 3] = 255;
      }
    }

    const opts: image.InitializationOptions = {
      size: { width: cols, height: rows } as image.Size,
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.UNPREMUL,
      editable: false
    };

    // ★ 先放旧的再建新的：PixelMap 持有 **native 内存**（不受 ArkTS GC 管辖）。
    this.releaseHeatPixelMap();

    // ★ ArkTS 编译器会对 createPixelMapSync 报 "Function may throw exceptions" 告警，
    //   必须显式 try/catch：参数不合法（如宽高为 0）时会抛 BusinessError。
    try {
      this.heatPm = image.createPixelMapSync(bytes.buffer as ArrayBuffer, opts);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      console.error(`createPixelMapSync 失败: ${e.code} ${e.message}`);
      this.heatPm = undefined;
    }
  }

  /** 释放持有的 PixelMap（组件销毁 / 数据清空 / 换新帧时调用） */
  private releaseHeatPixelMap(): void {
    const old: image.PixelMap | undefined = this.heatPm;
    this.heatPm = undefined;
    if (old === undefined || old.isReleased()) {
      return;
    }
    old.release();
  }

  /** 只画标注层：4 个虚线圆角框 + 区域名（尺寸按 `boxSize` 缩放，与 Web 端 `scale = SIZE / 128` 同口径） */
  private drawAnnotations(): void {
    const ctx: CanvasRenderingContext2D = this.annCtx;
    const side: number = this.boxSize;
    ctx.clearRect(0, 0, side, side);
    if (!this.hasData || !this.showAnnotations) {
      return;
    }

    const scale: number = side / CANON_FACE_SIZE;
    ctx.lineWidth = 1.5;
    // ★ 字号随尺寸缩放：缩略方块用 14px 会糊成一团（Web 端也是 `9 * scale`）
    //   ArkUI Canvas 的 font 单位必填（px / vp 都收）
    const fontPx: number = Math.max(8, Math.round(9 * scale * 1.4));
    ctx.font = `${fontPx}px sans-serif`;
    ctx.textAlign = 'center';

    for (let i = 0; i < HEAT_REGIONS.length; i++) {
      const r: RegionBox = HEAT_REGIONS[i];
      const cx: number = r.cx * scale;
      const cy: number = r.cy * scale;
      const rw: number = 26 * scale;
      const rh: number = 18 * scale;

      ctx.strokeStyle = r.color;
      ctx.setLineDash([4, 3]);
      ctx.beginPath();
      HeatmapTile.roundRectPath(ctx, cx - rw / 2, cy - rh / 2, rw, rh, 4);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = r.color;
      ctx.fillText(r.label, cx, cy - rh / 2 - 4);
    }
  }

  /**
   * 圆角矩形路径 · **双保险**
   *
   * 首选 `ctx.roundRect()`（写法与 Web 端 `ctx.roundRect(...)` 完全一致），
   * 但它有两个坑：
   *   ① `@since 20` —— compatibleSdkVersion 降到 18 及以下就没有这个 API；
   *   ② ArkTS 把它标记为"可能抛异常"，编译器会报
   *      `Function may throw exceptions. Special handling is required.` 告警。
   * 所以这里 try/catch 兜底，失败时用 arcTo 手写等价路径。
   * 两条路径画出的形状**逐点相同**，因此视觉上不会有差异。
   */
  private static roundRectPath(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    w: number,
    h: number,
    r: number
  ): void {
    try {
      ctx.roundRect(x, y, w, h, r);
      return;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      console.warn(`roundRect 不可用（${e.code}），回退到 arcTo 手写圆角`);
    }
    // ── 降级路径：arcTo 手写圆角矩形（moveTo/lineTo/arcTo/closePath）──
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.arcTo(x + w, y, x + w, y + r, r);
    ctx.lineTo(x + w, y + h - r);
    ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
    ctx.lineTo(x + r, y + h);
    ctx.arcTo(x, y + h, x, y + h - r, r);
    ctx.lineTo(x, y + r);
    ctx.arcTo(x, y, x + r, y, r);
    ctx.closePath();
  }

  build() {
    Stack() {
      // ① 对齐人脸（ArkUI Image 直接吃 data URL，无需手动 base64 解码）
      if (this.faceSrc.length > 0) {
        Image(this.faceSrc)
          .width(this.boxSize)
          .height(this.boxSize)
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.Medium)
      } else {
        // 没有人脸底图时（纯矩阵视图 / 缩略方块）用浅色底，避免出现黑块
        Column()
          .width(this.boxSize)
          .height(this.boxSize)
          .backgroundColor(UiTheme.fillSoft)
      }

      // ② 16×16 热力图放大铺满 —— 等价于 Web 端的「离屏网格 × globalAlpha 0.4」
      if (this.hasData) {
        Image(this.heatPm)
          .width(this.boxSize)
          .height(this.boxSize)
          .objectFit(ImageFit.Fill)
          .interpolation(this.smooth ? ImageInterpolation.High : ImageInterpolation.None)
          .opacity(HEAT_OVERLAY_ALPHA)
      } else {
        // 占位：等待推理数据
        Column() {
          Text('等待推理数据...')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
        }
        .width(this.boxSize)
        .height(this.boxSize)
        .justifyContent(FlexAlign.Center)
      }

      // ③ 标注层（透明画布，只画框和字）
      if (this.showAnnotations) {
        Canvas(this.annCtx)
          .width(this.boxSize)
          .height(this.boxSize)
          .onReady(() => {
            this.canvasReady = true;
            this.drawAnnotations();
          })
      }
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .borderRadius(UiTheme.cardRadius)
    .clip(true)
    .borderWidth(1)
    .borderColor(UiTheme.divider)
  }
}
