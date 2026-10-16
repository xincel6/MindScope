/**
 * HeatmapSampleData · 合成演示帧（**只为验证渲染链路**，不是真实推理结果）
 *
 * ────────────────── 为什么需要它 ──────────────────
 * 分析详情页的真数据来自 WebSocket：上传素材 → 服务端跑 MTCNN + MSSTformer →
 * 逐帧回推 `{bdi_score, aligned_face, heatmap_data[16][16]}`。
 * 这套链路依赖"服务端在跑 + 已登录 + 已上传素材"，在没有这些条件时页面只能是空占位，
 * **热力图这件事就完全没法验证**。
 *
 * 所以这里造 3 帧合成数据：
 *   · 热度矩阵 = 三个高斯斑（眉间 / 左眶周 / 口周），与探测页 `makeSyntheticHeatmap()` 同源，
 *     可以顺带验证"热点位置 → 解剖区域名"的判定顺序；
 *   · 三帧的斑**故意不同**（位置/权重各不一样），这样横向列表里能一眼看出
 *     "每一格画的确实是那一帧"，而不是同一张图重复 3 次 —— 这是本轮最关键的验证点之一；
 *   · 人脸底图留空（`alignedFace = ''`）：方块组件会退回浅灰底 + 只有热度层，
 *     正好检验"没有人脸底图时也不会画成黑块"。
 *
 * ★ 界面上**必须**标注这是演示数据（`HeatmapViewModel.heatSourceHint` 已负责），
 *   否则会被误读成真实推理结果 —— 这在医疗类界面里是不能接受的。
 */

import { AnalysisFrameModel } from '../../types/Index';

/** 一帧的合成配方 */
class SampleRecipe {
  bdiScore: number;
  /** 三个斑的中心（归一化坐标 x, y） */
  cx: number[];
  cy: number[];
  /** 三个斑的权重 */
  wgt: number[];
  /** 高斯半径（归一化坐标） */
  sigma: number;

  constructor(bdiScore: number, cx: number[], cy: number[], wgt: number[], sigma: number) {
    this.bdiScore = bdiScore;
    this.cx = cx;
    this.cy = cy;
    this.wgt = wgt;
    this.sigma = sigma;
  }
}

/**
 * 三帧配方 · 刻意让"最热点"落在不同解剖区域
 *   帧 1：眉间最强（regionY < 0.3 且中部）→ 期望解读「眉间/前额区域」
 *   帧 2：左眶周最强（0.25 < y < 0.45 且 x < 0.35）→ 期望「眶周区域（眼轮匝肌）」
 *   帧 3：口周最强（y > 0.5 且中部）→ 期望「口周区域（降口角肌）」
 */
const RECIPES: SampleRecipe[] = [
  new SampleRecipe(12.4, [0.5, 0.28, 0.5], [0.22, 0.38, 0.70], [1.0, 0.55, 0.45], 0.12),
  new SampleRecipe(17.8, [0.5, 0.22, 0.5], [0.30, 0.40, 0.72], [0.55, 1.0, 0.5], 0.10),
  new SampleRecipe(21.6, [0.5, 0.30, 0.5], [0.26, 0.42, 0.78], [0.45, 0.6, 1.0], 0.11)
];

/** 用配方生成一张 16×16 归一化热度矩阵（与探测页同一套高斯算法） */
function makeMatrix(recipe: SampleRecipe): number[][] {
  const n: number = 16;
  const out: number[][] = [];
  let maxV: number = 0;

  for (let y = 0; y < n; y++) {
    const row: number[] = [];
    for (let x = 0; x < n; x++) {
      const nx: number = (x + 0.5) / n;
      const ny: number = (y + 0.5) / n;
      let v: number = 0;
      for (let k = 0; k < recipe.cx.length; k++) {
        const dx: number = nx - recipe.cx[k];
        const dy: number = ny - recipe.cy[k];
        v += recipe.wgt[k] * Math.exp(-(dx * dx + dy * dy) / (2 * recipe.sigma * recipe.sigma));
      }
      row.push(v);
      if (v > maxV) {
        maxV = v;
      }
    }
    out.push(row);
  }

  // 归一化到 [0,1] —— 服务端 heatmap_data 的值域就是 [0,1]
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      out[y][x] = maxV > 0 ? out[y][x] / maxV : 0;
    }
  }
  return out;
}

/**
 * 合成演示帧数组（3 帧）
 * @returns `AnalysisFrameModel[]`，字段与真实帧完全一致，可直接喂给 `HeatmapTile`
 */
export function makeSampleFrames(): AnalysisFrameModel[] {
  const out: AnalysisFrameModel[] = [];
  const steps: number = RECIPES.length;
  for (let i = 0; i < steps; i++) {
    const recipe: SampleRecipe = RECIPES[i];
    const frame: AnalysisFrameModel = {
      frameId: i + 1,
      timestamp: 0,
      bdiScore: recipe.bdiScore,
      // ★ 留空：验证"没有人脸底图时"方块组件的降级表现
      alignedFace: '',
      heatmapData: makeMatrix(recipe),
      inferenceTimeMs: 0,
      progress: (i + 1) / steps
    };
    out.push(frame);
  }
  return out;
}
