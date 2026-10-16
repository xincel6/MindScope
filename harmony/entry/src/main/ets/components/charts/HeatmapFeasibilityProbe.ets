/**
 * HeatmapFeasibilityProbe · 注意力热力图 **备选实现路径的 API 探测**（不参与业务，仅供编译期验证）
 *
 * ⚠️ 本文件的存在意义只有一个：**把"报告里声称可用的 API"逐个写进真实代码并让编译器验收**。
 *    它不渲染任何 UI，也没有被任何页面引用；确认可行性后可以整个文件删掉。
 *
 * 覆盖的备选路径：
 *   路径 B · 单 Canvas 全量绘制（最贴近 Web 端 FacePreview.vue 的写法）
 *           base64 → PixelMap → ctx.drawImage 铺底 → 16×16 fillRect 网格 → 标注框
 *   路径 C · 离屏画布（OffscreenCanvas + transferToImageBitmap，对应 Web 端离屏 canvas）
 *   路径 D · 端侧像素后处理（getImageData / putImageData，将来若要自己做双三次上采样）
 *   路径 E · 色带用 Canvas 渐变（备选：主方案用的是 ArkUI 原生 linearGradient）
 *
 * ★ 每个 API 的 since 版本都在本地 SDK（API 23）`.d.ts` 中核对过，见报告"证据清单"。
 */

import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { HeatmapUtil } from './AttentionHeatmap';

/** 探测类 · 全部为静态方法，纯函数式，无状态 */
export class HeatmapApiProbe {
  // ══════════════════ 路径 B · 单 Canvas 全量绘制 ══════════════════

  /**
   * `data:image/jpeg;base64,...` 或裸 base64 → PixelMap
   *
   * 为什么需要它：如果坚持"一张 Canvas 画完所有东西"（与 Web 端结构完全同构），
   * 底图就必须先变成 PixelMap 才能交给 `ctx.drawImage`（ArkUI 的 drawImage 只收
   * ImageBitmap | PixelMap，**不吃字符串**）。
   *
   * 若走主方案（Stack + `<Image>`），则**这一步可以完全省掉**。
   */
  public static async decodeImageToPixelMap(raw: string): Promise<image.PixelMap | undefined> {
    if (raw.length === 0) {
      return undefined;
    }
    try {
      // 兼容带前缀与裸 base64 两种形态
      const comma: number = raw.indexOf(',');
      const b64: string = raw.startsWith('data:') && comma >= 0 ? raw.substring(comma + 1) : raw;

      const helper: util.Base64Helper = new util.Base64Helper();
      const bytes: Uint8Array = helper.decodeSync(b64);

      // ★ 服务端 `_encode_base64()` 用 PIL 存的是 JPEG（quality=75），不是 PNG
      const src: image.ImageSource = image.createImageSource(bytes.buffer as ArrayBuffer);
      const pm: image.PixelMap = await src.createPixelMap();
      return pm;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      console.error(`decodeImageToPixelMap 失败: ${e.code} ${e.message}`);
      return undefined;
    }
  }

  /**
   * 单 Canvas 全量绘制（路径 B 的核心）
   * 与 Web 端 `drawFace()` 的对应关系写在每一行注释里。
   */
  public static drawFaceOnCanvas(
    ctx: CanvasRenderingContext2D,
    face: image.PixelMap | undefined,
    data: number[][],
    size: number
  ): void {
    ctx.clearRect(0, 0, size, size);

    // ① 底图：5 参数重载 = 拉伸铺满（对应 Web 端 drawImage(img, 0, 0, SIZE, SIZE)）
    if (face !== undefined) {
      ctx.drawImage(face, 0, 0, size, size);
    }

    // ② 16×16 网格叠加：ArkUI 没有"离屏 canvas 再贴回"的必要，直接 globalAlpha + fillRect 即可
    const rows: number = data.length;
    if (rows === 0) {
      return;
    }
    const cols: number = data[0].length;
    if (cols === 0) {
      return;
    }
    const cellW: number = size / cols;
    const cellH: number = size / rows;

    // Web 端：每格 alpha 0.8 × globalAlpha 0.4 = 0.32；此处直接把两者合成一个 globalAlpha
    ctx.globalAlpha = 0.4;
    for (let y = 0; y < rows; y++) {
      const row: number[] = data[y];
      for (let x = 0; x < cols; x++) {
        ctx.fillStyle = HeatmapUtil.heatColor(row[x]);
        ctx.fillRect(x * cellW, y * cellH, cellW, cellH);
      }
    }
    ctx.globalAlpha = 1;

    // ③ 9 参数重载（带源裁剪）也验证一下：右下角贴一个 64×64 的缩略人脸
    if (face !== undefined) {
      ctx.drawImage(face, 0, 0, 64, 64, size - 44, size - 44, 44, 44);
    }
  }

  /**
   * 路径 B 的"平滑"变体：不做 16×16 硬边格，而是把 16×16 PixelMap 交给 drawImage 放大，
   * 由渲染管线做插值 —— 观感更接近连续热力图。
   */
  public static drawSmoothedGrid(
    ctx: CanvasRenderingContext2D,
    pm16: image.PixelMap,
    size: number
  ): void {
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.globalAlpha = 0.32;
    ctx.drawImage(pm16, 0, 0, size, size);
    ctx.globalAlpha = 1;
  }

  // ══════════════════ 路径 C · 离屏画布 ══════════════════

  /**
   * 离屏画布 → ImageBitmap（与 Web 端 `document.createElement('canvas')` 同构）
   * 适合"先算好一张完整叠加图，再一次性交给 `<Image>` 或 `drawImage`"的场景。
   */
  public static offscreenComposite(data: number[][], size: number): ImageBitmap | undefined {
    const rows: number = data.length;
    if (rows === 0 || data[0].length === 0) {
      return undefined;
    }
    const off: OffscreenCanvas = new OffscreenCanvas(size, size);
    // 注意：ArkUI 这里返回的是**非空**类型，不要写 `if (ctx === null)`（TS 会判为恒真比较）
    const octx: OffscreenCanvasRenderingContext2D = off.getContext('2d', new RenderingContextSettings(true));

    const cols: number = data[0].length;
    const cellW: number = size / cols;
    const cellH: number = size / rows;
    for (let y = 0; y < rows; y++) {
      const row: number[] = data[y];
      for (let x = 0; x < cols; x++) {
        octx.fillStyle = HeatmapUtil.heatColor(row[x]);
        octx.fillRect(x * cellW, y * cellH, cellW, cellH);
      }
    }
    return off.transferToImageBitmap();
  }

  // ══════════════════ 路径 D · 端侧像素读写 ══════════════════

  /**
   * getImageData / createImageData / putImageData 往返
   * 只有"要在端侧自己实现双三次上采样 / 高斯模糊 / 阈值化"时才需要；
   * 16×16 数据量下走这条路也完全可行（1024 个采样点）。
   */
  public static pixelRoundTrip(ctx: CanvasRenderingContext2D, size: number): void {
    const shot: ImageData = ctx.getImageData(0, 0, size, size);
    const blank: ImageData = ctx.createImageData(size, size);
    // 直接把自己贴回去，验证读写链路可用（真实的模糊/放大算法在此处实现）
    ctx.putImageData(blank, 0, 0);
    ctx.putImageData(shot, 0, 0);
  }

  // ══════════════════ 路径 E · 色带（Canvas 渐变版） ══════════════════

  /** 五段色带 · 与 Web 端 CSS `linear-gradient(to right, #00f,#0ff,#0f0,#ff0,#f00)` 等价 */
  public static drawColorBar(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const grad: CanvasGradient = ctx.createLinearGradient(0, 0, w, 0);
    grad.addColorStop(0.0, '#0000FF');
    grad.addColorStop(0.25, '#00FFFF');
    grad.addColorStop(0.5, '#00FF00');
    grad.addColorStop(0.75, '#FFFF00');
    grad.addColorStop(1.0, '#FF0000');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);
  }

  // ══════════════════ 降级预案 · 不依赖 roundRect(@since 20) 的圆角矩形 ══════════════════

  /**
   * 手写圆角矩形（`roundRect` 是 @since 20 API 的替代品）
   * 只有把 compatibleSdkVersion 降到 18 及以下时才需要用到。
   */
  public static roundedRectFallback(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    w: number,
    h: number,
    r: number
  ): void {
    ctx.beginPath();
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

  /** 文字测量（自动缩放区域名标注时用得上） */
  public static textWidth(ctx: CanvasRenderingContext2D, text: string): number {
    const m: TextMetrics = ctx.measureText(text);
    return m.width;
  }

  /** 画布导出成 data URL（若将来要做"长图报告导出"，这条链路可用） */
  public static exportPng(ctx: CanvasRenderingContext2D): string {
    return ctx.toDataURL('image/png', 0.92);
  }
}
