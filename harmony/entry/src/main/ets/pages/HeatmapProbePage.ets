/**
 * HeatmapProbePage · 注意力热力图 **可行性探测页**（独立入口，与业务页面零耦合）
 *
 * ⚠️ 用途：本轮只做技术路线验证。它做了两件事：
 *   ① 把 `AttentionHeatmap`（推荐路线：Stack + PixelMap + Canvas 标注）真正编译进 HAP，
 *      这样"能编译"才是**真结论**——本项目 `hvigor` 只编译从入口可达的文件，
 *      放在 `components/` 下不被引用的 .ets **根本不会进编译器**（实测：不在 modules.abc 里）。
 *   ② 在真机/预览器上用**合成数据**目视验收：色彩映射是否与 Web 端一致、放大是否平滑、
 *      区域框与色带是否到位。
 *
 * ★ 为什么必须有它：没有入口引用时，哪怕往组件里写一个类型错误，`BUILD SUCCESSFUL` 也照样通过。
 *   这一点见报告"验证方法"一节。
 *
 * ★ 验证完成后可直接删除本页，并把 `resources/base/profile/main_pages.json` 里的
 *   `"pages/HeatmapProbePage"` 一并删掉（不影响任何业务代码）。
 *
 * 打开方式（真机调试）：在任一页面执行
 *   router.pushUrl({ url: 'pages/HeatmapProbePage' })
 */

import { AttentionHeatmap, HeatmapUtil, HeatHotspot } from '../components/charts/AttentionHeatmap';
import { HeatmapApiProbe } from '../components/charts/HeatmapFeasibilityProbe';
import { UiTheme } from '../common/UiTheme';

/** 合成 16×16 注意力矩阵 · 三个高斯斑（模拟"眉间 + 双眼 + 口周"的关注模式） */
function makeSyntheticHeatmap(): number[][] {
  const n: number = 16;
  const out: number[][] = [];
  // 三个斑的中心与权重（归一化坐标）：眉间 / 左眶周 / 口周
  const cx: number[] = [0.5, 0.28, 0.5];
  const cy: number[] = [0.24, 0.4, 0.72];
  const wgt: number[] = [1.0, 0.8, 0.9];
  const sigma: number = 0.13;

  let maxV: number = 0;
  for (let y = 0; y < n; y++) {
    const row: number[] = [];
    for (let x = 0; x < n; x++) {
      const nx: number = (x + 0.5) / n;
      const ny: number = (y + 0.5) / n;
      let v: number = 0;
      for (let k = 0; k < cx.length; k++) {
        const dx: number = nx - cx[k];
        const dy: number = ny - cy[k];
        v += wgt[k] * Math.exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));
      }
      row.push(v);
      if (v > maxV) {
        maxV = v;
      }
    }
    out.push(row);
  }
  // 归一化到 0..1（服务端 heatmap_data 的值域就是 [0,1]）
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      out[y][x] = maxV > 0 ? out[y][x] / maxV : 0;
    }
  }
  return out;
}

@Entry
@ComponentV2
struct HeatmapProbePage {
  @Local heat: number[][] = makeSyntheticHeatmap();
  @Local smooth: boolean = true;
  @Local hotspotText: string = '';

  /** 路径 B（单 Canvas 全量绘制）用的画布 */
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    // 顺带验证纯函数层（HeatmapUtil）在运行期的输出是否正确
    const list: HeatHotspot[] = HeatmapUtil.hotspots(this.heat, 3);
    let text: string = '';
    for (let i = 0; i < list.length; i++) {
      text += `#${i + 1} ${list[i].region} ${list[i].percent}%  `;
    }
    this.hotspotText = text;

    // 验证 base64/PixelMap 解码链路是否可调用（无真实数据时不产生副作用）
    HeatmapApiProbe.decodeImageToPixelMap('').then((pm) => {
      console.info(`解码探测完成，结果 ${pm === undefined ? 'undefined(预期，输入为空)' : 'ok'}`);
    });
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(UiTheme.fontSizeSection)
      .fontWeight(FontWeight.Medium)
      .fontColor(UiTheme.textPrimary)
      .width('100%')
      .textAlign(TextAlign.Start)
  }

  build() {
    Column({ space: UiTheme.gapL }) {
      Row({ space: UiTheme.gapS }) {
        Text('热力图可行性探测')
          .fontSize(UiTheme.fontSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.textPrimary)
          .layoutWeight(1)
        Button('返回')
          .fontSize(UiTheme.fontSizeBody)
          .height(36)
          .backgroundColor(UiTheme.fillSoft)
          .fontColor(UiTheme.textPrimary)
          .onClick(() => {
            // ★ 不用已废弃的 `@ohos.router.back()`（since 18 deprecated），走 UIContext 版本
            this.getUIContext().getRouter().back();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: UiTheme.gapL }) {
          // ── ① 推荐路线：Stack(Image 底图 / Image 热力图 / Canvas 标注) ──
          this.sectionTitle('① 推荐路线 · Stack + 16×16 PixelMap 放大')
          AttentionHeatmap({
            heatmap: this.heat,
            faceDataUrl: '',
            smooth: this.smooth
          })

          Row({ space: UiTheme.gapS }) {
            Button(this.smooth ? '平滑放大（High）' : '逐格方块（None）')
              .fontSize(UiTheme.fontSizeCaption)
              .height(32)
              .backgroundColor(UiTheme.primary)
              .onClick(() => {
                this.smooth = !this.smooth;
              })
            Button('换一组数据')
              .fontSize(UiTheme.fontSizeCaption)
              .height(32)
              .backgroundColor(UiTheme.accent)
              .onClick(() => {
                // ★ 整体替换数组（与 store 的行为一致），确保 @Monitor 能感知
                this.heat = makeSyntheticHeatmap();
              })
          }
          .width('100%')

          Text(`Top-3 热点（HeatmapUtil 输出）：${this.hotspotText}`)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)

          Divider().color(UiTheme.divider)

          // ── ② 备选路线：单 Canvas 全量绘制（最贴近 Web 端写法） ──
          this.sectionTitle('② 备选路线 · 单 Canvas 全量绘制（fillRect 网格 + 渐变在 Canvas 内）')
          Canvas(this.canvasCtx)
            .width(200)
            .height(200)
            .backgroundColor(UiTheme.fillSoft)
            .borderRadius(UiTheme.cardRadius)
            .onReady(() => {
              // 无真人脸数据时传 undefined，只验证网格 + 色带两条绘制链路
              HeatmapApiProbe.drawFaceOnCanvas(this.canvasCtx, undefined, this.heat, 200);
              HeatmapApiProbe.drawColorBar(this.canvasCtx, 200, 6);
            })

          Text('说明：该 Canvas 走的是 `ctx.fillStyle = heatColor(v)` + `fillRect` 的逐格路径，'
            + '与 Web 端 `FacePreview.vue` 的离屏网格在像素级同构（16×16 硬边）。')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)

          Divider().color(UiTheme.divider)

          // ── ③ 纯函数层自检：色带采样值，用于与 Web 端逐点比对 ──
          this.sectionTitle('③ heatColor 采样（应与 Web 端逐位相同）')
          ForEach([0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1], (t: number) => {
            Row({ space: UiTheme.gapS }) {
              Text(`t=${t}`)
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(UiTheme.textSecondary)
                .width(64)
                .textAlign(TextAlign.Start)
              Row()
                .width(40)
                .height(16)
                .backgroundColor(HeatmapUtil.heatColor(t))
              Text(HeatmapUtil.heatColor(t))
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(UiTheme.textPrimary)
                .layoutWeight(1)
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }, (t: number) => `${t}`)
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
