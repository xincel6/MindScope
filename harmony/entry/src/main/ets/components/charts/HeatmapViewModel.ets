/**
 * HeatmapViewModel · 工作台分析区"注意力热力图"的**取数逻辑**（纯函数，可离线推演）
 *
 * ────────────────── 为什么把这段逻辑单独放一个文件 ──────────────────
 * 热力图卡要处理**三种**数据情形，如果直接写在 `build()` 里，组件会被 if 淹没，
 * 而且这些判断无法脱离真机验证。抽成纯函数后：
 *   · 页面只负责"把返回值的几个字段画出来"；
 *   · 这套优先级可以用 `node harmony/scripts/test-heatmap-strip.mjs` 离线跑（含边界用例）。
 *
 * ────────────────── 三种情形（优先级从高到低）──────────────────
 *   ① **手动选中**：用户在横向列表里点了某一格 → 主图显示**那一帧**的热力图
 *      （`focusedIndex >= 0`，且该帧确有热度数据）
 *   ② **本素材有帧**：`frames` 由调用方按 mediaId 解析好后传入
 *      （`live` = 正在跟随的分析会话；`snapshot` = 该素材已完成/归档的会话）
 *   ③ **纯演示**：没有任何真实热度数据 → 用 `makeSampleFrames()` 的**合成帧**
 *      把渲染链路跑起来（文案必须标注"演示数据"，绝不能让人误读成真实结果）
 *
 * ══════════════════ ★★ 本轮（分析页实装轮）删掉了一条"兜底" ══════════════════
 * 旧签名里有第五个参数 `lastFrame`，语义是"当前会话里最近的一帧"，并在
 * `followLiveTask === false`（历史素材）时回退成 `frames = [lastFrame]`。
 * 那条兜底是**两个用户可见 bug 的唯一入口**：
 *   · 「退出分析页再回来只剩 1 帧」——历史素材没有自己的帧，只剩这条兜底；
 *   · 「所有分析过的素材热力图都变成最近那个人」——兜底取的是**全局**最新一帧，
 *     与所看的素材毫无关系。
 * 现在帧数组由调用方按 mediaId 解析（`AppStore.analysisSessionOf(mediaId)`），
 * 取不到就是空 → 页面显示"本机未保留逐帧数据"，**绝不跨素材兜底**。
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
  /** 跟随正在跑的分析会话 */
  live = 1,
  /** 该素材已完成/归档的会话（从「最近使用的素材」进来） */
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
 * 为什么要有它：视频素材服务端会推 ~60~96 帧，每格都要建一个 16×16 PixelMap
 * 加一个透明 Canvas。实机（模拟器 API 23）一次性渲染 90+ 格会把渲染服务压死
 * （实测黑屏 / `LIFECYCLE_TIMEOUT` 冻结日志）。取 24 兼顾两点：
 *   · 一屏能看到 3~4 格、滑两下能回看 20 多帧；
 *   · 节点数与 PixelMap 数都留在安全区。
 *
 * ★ 超出上限时**按时间均匀抽取**（保留首尾），不再"只留最后 24 帧"——
 *   服务端每 24 帧才推理一次，最后 24 帧正好是同一批，整列 24 格会完全同图
 *   （用户报的"所有帧都是同一帧"）。均匀抽取后 24 格跨越整段视频，
 *   "注意力热点随时间漂移"才看得出来。
 */
const MAX_STRIP_TILES: number = 24;

/**
 * 等距抽样（保留首尾）
 *
 * @param frames 已过滤掉无热度矩阵的帧（按时间顺序）
 * @param maxTiles 渲染上限
 */
function sampleEvenly(frames: AnalysisFrameModel[], maxTiles: number): AnalysisFrameModel[] {
  if (maxTiles <= 0) {
    return [];
  }
  if (frames.length <= maxTiles) {
    return frames;
  }
  const out: AnalysisFrameModel[] = [];
  const lastIndex: number = frames.length - 1;
  const step: number = lastIndex / (maxTiles - 1);
  for (let i = 0; i < maxTiles; i++) {
    let index: number = Math.round(i * step);
    if (index < 0) {
      index = 0;
    }
    if (index > lastIndex) {
      index = lastIndex;
    }
    out.push(frames[index]);
  }
  return out;
}

/** 只保留有热度数据的帧，并在超出渲染上限时**按时间均匀抽取** */
function heatOnly(frames: AnalysisFrameModel[]): AnalysisFrameModel[] {
  const out: AnalysisFrameModel[] = [];
  for (let i = 0; i < frames.length; i++) {
    if (hasHeat(frames[i])) {
      out.push(frames[i]);
    }
  }
  return sampleEvenly(out, MAX_STRIP_TILES);
}

/**
 * 定位"主图要画哪一帧"
 *
 * ★ 这里有个**用户手感**的细节：不能简单地"没选中就取第 0 帧"。
 *   横向列表是**按时间顺序左旧右新**排列的，用户的心智模型是"最右边是最新"。
 *   所以：
 *     · 没手动选过（`focusedIndex < 0`）→ 取**最后一格**（最新）；
 *     · 手动选过 → 取那一格；但如果选中的下标越界（例如换了一素材/新一轮分析把列表换了），
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
 * @param frames **本素材**的帧（由调用方按 mediaId 解析 · 图片素材请在调用前归一成 1 帧）
 * @param sampleFrames 合成演示帧（`makeSampleFrames()` 的结果）
 * @param focusedIndex 用户手动选中的帧下标（-1 = 没选过）
 * @param isLive 本页的素材是不是当前正在跑的分析会话（决定文案是"实时"还是"归档"）
 */
export function buildHeatmapView(
  frames: AnalysisFrameModel[],
  sampleFrames: AnalysisFrameModel[],
  focusedIndex: number,
  isLive: boolean
): HeatmapView {
  // ① 本素材有帧 → 就用它（最常见：live 会话 / 该素材的归档会话）
  const own: AnalysisFrameModel[] = heatOnly(frames);
  if (own.length > 0) {
    const last: number = own.length - 1;
    const index: number = pickIndex(own, focusedIndex, last);
    const pinned: boolean = focusedIndex >= 0 && index === focusedIndex;
    const view: HeatmapView = {
      frames: own,
      heatmap: index >= 0 ? own[index].heatmapData : [],
      index: index,
      focusedIndex: focusedIndex,
      source: pinned ? HeatSource.pinned : (isLive ? HeatSource.live : HeatSource.snapshot)
    };
    return view;
  }

  // ② 本素材一帧热度数据都没有 → 用合成演示帧把渲染链路跑通（界面会标"演示数据"）
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
    return `已固定第 ${frameId} 帧 · BDI ${score.toFixed(1)}（点「回到最新」可跟随最新一帧）`;
  }
  if (source === HeatSource.snapshot) {
    return `该素材最近一次分析的第 ${frameId} 帧 · BDI ${score.toFixed(1)}（逐帧数据来自本机会话缓存）`;
  }
  return `跟随最新一帧（第 ${frameId} 帧）· 左右滑动可回看任意一帧`;
}
