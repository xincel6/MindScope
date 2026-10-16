/**
 * HeatmapViewModel · 分析详情页"注意力热力图"区的**取数逻辑**（纯函数，可离线推演）
 *
 * ────────────────── 为什么把这段逻辑单独放一个文件 ──────────────────
 * 分析详情页要处理**四种**数据情形，如果直接写在 `build()` 里，页面会被 if 淹没，
 * 而且这些判断无法脱离真机验证。抽成纯函数后：
 *   · 页面只负责"把返回值的四个字段画出来"；
 *   · 这套优先级可以用 `node scripts/test-heatmap-viewmodel.mjs` 离线跑（含边界用例）。
 *
 * ────────────────── 四种情形（优先级从高到低）──────────────────
 *   ① **手动选中**：用户在横向列表里点了某一格 → 主图显示**那一帧**的热力图
 *      （`focusedIndex >= 0`，且该帧确有热度数据）
 *   ② **实时**：`followLiveTask = true` 且已收到帧 → 显示**最新一帧**（列表最右一格）
 *   ③ **历史快照**：从「最近使用的素材」进入（`followLiveTask = false`）→ 没有逐帧数据，
 *      但当前会话缓冲区里可能还留着刚跑完的那次分析 → 用它做兜底展示
 *   ④ **纯演示**：没有任何真实热度数据 → 用 `makeSampleFrames()` 的**合成帧**
 *      把渲染链路跑起来（文案必须标注"演示数据"，绝不能让人误读成真实结果）
 *
 * ★ 一条硬规则：**主图与列表必须来自同一个帧数组**。
 *   所以 `frames` 与 `heatmap` / `index` 都在这一个返回值里算好，
 *   页面不再自己挑数据 —— 否则会出现"列表里高亮的是第 7 格、主图画的是第 12 格"。
 *
 * ★ 另一条硬规则：**只画有热度数据的帧**。
 *   视频路径下，`heatmap_data` 缺失的帧会被 mapper 归一化成空矩阵（`normalizeMatrix`），
 *   把空矩阵交给方块组件只会得到一个灰块。所以这里先挑出 `hasHeat()` 的帧再来谈索引。
 */

import { AnalysisFrameModel } from '../../types/Index';

/** 主图当前显示的帧来自哪里 · 页面据此选文案（不要用"有数据"反推，容易误标） */
export enum HeatSource {
  /** 用户手动点了某一格 */
  pinned = 0,
  /** 实时跟随最新一帧 */
  live = 1,
  /** 历史快照兜底（当前会话缓冲区里还留着的帧） */
  snapshot = 2,
  /** 合成演示数据（不是真实推理结果） */
  sample = 3
}

/** 热力图区的取数结果 · 页面的**唯一**数据入口 */
export interface HeatmapView {
  /** 横向逐帧列表要渲染的帧（已过滤掉空热度矩阵的帧） */
  frames: AnalysisFrameModel[];
  /** 主图要画的 16×16 矩阵（空数组 = 无数据，方块组件走占位态） */
  heatmap: number[][];
  /** 主图帧在 `frames` 里的下标（-1 = 无） */
  index: number;
  /** 用户选中的帧下标快照（-1 = 没有手动选过）· 列表用它画高亮边框 */
  focusedIndex: number;
  /** 数据来源 · 页面据此选文案 */
  source: HeatSource;
}

/** 这一帧是否有可画的 16×16 热度矩阵 */
function hasHeat(frame: AnalysisFrameModel): boolean {
  const data: number[][] = frame.heatmapData;
  return data.length > 0 && data[0].length > 0;
}

/**
 * 横向列表最多渲染多少格（**渲染上限，不是数据上限**）
 *
 * 为什么要有它：视频素材服务端会推 ~96 帧，每格都要建一个 16×16 PixelMap
 * 加一个透明 Canvas。实机（模拟器 API 23）一次性渲染 90+ 格会把渲染服务压死
 * （实测黑屏 / `LIFECYCLE_TIMEOUT` 冻结日志）。取 24 兼顾两点：
 *   · 一屏能看到 3~4 格、滑两下能回看 20 多帧，足够看出热点随时间的漂移；
 *   · 节点数与 PixelMap 数都留在安全区。
 * 完整逐帧数据仍在 `AnalysisState.frameHistory`（上限 90），
 * 将来做"整片时间轴 / 视频切分"时替换成**懒加载或缩略图**即可，不必改数据层。
 */
const MAX_STRIP_TILES: number = 24;

/** 只保留有热度数据的帧，并在超出渲染上限时**保留最新的那些** */
function heatOnly(frames: AnalysisFrameModel[]): AnalysisFrameModel[] {
  const out: AnalysisFrameModel[] = [];
  for (let i = 0; i < frames.length; i++) {
    if (hasHeat(frames[i])) {
      out.push(frames[i]);
    }
  }
  if (out.length > MAX_STRIP_TILES) {
    return out.slice(out.length - MAX_STRIP_TILES);
  }
  return out;
}

/**
 * 定位"主图要画哪一帧"
 *
 * ★ 这里有个**用户手感**的细节：不能简单地"没选中就取第 0 帧"。
 *   横向列表是**按时间顺序左旧右新**排列的，用户的心智模型是"最右边是最新"。
 *   所以：
 *     · 没手动选过（`focusedIndex < 0`）→ 取**最后一格**（最新）；
 *     · 手动选过 → 取那一格；但如果选中的下标越界（例如新一轮分析把列表换了），
 *       退回最后一格，而不是硬取第 0 格（那会突然跳到"很久以前的一帧"）。
 */
function pickIndex(frames: AnalysisFrameModel[], focusedIndex: number, lastIndex: number): number {
  if (frames.length === 0) {
    return -1;
  }
  if (focusedIndex >= 0 && focusedIndex < frames.length) {
    return focusedIndex;
  }
  return lastIndex;
}

/**
 * 计算热力图区要展示的内容
 *
 * @param liveFrames 当前分析会话的逐帧序列（`AppStore.analysisFrameHistory()`）
 * @param sampleFrames 合成演示帧（`makeSampleFrames()` 的结果）
 * @param followLiveTask 本页是否跟随正在跑的任务（历史快照为 false）
 * @param focusedIndex 用户手动选中的帧下标（-1 = 没选过）
 * @param lastFrame 最新一帧（历史快照兜底用，可为 null）
 */
export function buildHeatmapView(
  liveFrames: AnalysisFrameModel[],
  sampleFrames: AnalysisFrameModel[],
  followLiveTask: boolean,
  focusedIndex: number,
  lastFrame: AnalysisFrameModel | null
): HeatmapView {
  // ① 实时会话有帧 → 就用它（最常见的路径）
  if (followLiveTask && liveFrames.length > 0) {
    const frames: AnalysisFrameModel[] = heatOnly(liveFrames);
    const last: number = frames.length - 1;
    const index: number = pickIndex(frames, focusedIndex, last);
    const view: HeatmapView = {
      frames: frames,
      heatmap: index >= 0 ? frames[index].heatmapData : [],
      index: index,
      focusedIndex: focusedIndex,
      source: focusedIndex >= 0 && index === focusedIndex ? HeatSource.pinned : HeatSource.live
    };
    return view;
  }

  // ② 历史快照 / 实时但还没收到帧 → 退回"最近一帧"（可能来自刚跑完的上一次分析）
  if (lastFrame !== null && hasHeat(lastFrame)) {
    const frames: AnalysisFrameModel[] = [lastFrame];
    const view: HeatmapView = {
      frames: frames,
      heatmap: lastFrame.heatmapData,
      index: 0,
      focusedIndex: -1,
      source: HeatSource.snapshot
    };
    return view;
  }

  // ③ 一个真实热度数据都没有 → 用合成演示帧把渲染链路跑通
  const demo: AnalysisFrameModel[] = heatOnly(sampleFrames);
  const last: number = demo.length - 1;
  const index: number = pickIndex(demo, focusedIndex, last);
  const view: HeatmapView = {
    frames: demo,
    heatmap: index >= 0 ? demo[index].heatmapData : [],
    index: index,
    focusedIndex: focusedIndex,
    source: HeatSource.sample
  };
  return view;
}

/** 主图下方的说明文案（把"数据来自哪里"直接写在界面上，避免误读） */
export function heatSourceHint(source: HeatSource, frameId: number, score: number): string {
  if (source === HeatSource.sample) {
    return '当前为演示数据（不是真实推理结果），仅用于验证热力图渲染链路';
  }
  if (source === HeatSource.pinned) {
    return `已固定第 ${frameId} 帧 · BDI ${score.toFixed(1)}（点最右一格可回到最新帧）`;
  }
  if (source === HeatSource.snapshot) {
    return `历史报告快照 · 无逐帧热力图，这里显示当前会话缓冲区里最近的第 ${frameId} 帧`;
  }
  return `跟随最新一帧（第 ${frameId} 帧）· 横向列表可左右滑动回看任意一帧`;
}
