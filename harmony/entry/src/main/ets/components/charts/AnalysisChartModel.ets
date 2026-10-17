/**
 * AnalysisChartModel · 工作台分析区两张图表（情绪曲线 / 严重度分布）的**取数逻辑**
 *
 * ────────────────── 为什么单独一个文件 ──────────────────
 * "情绪曲线"和"严重度分布"在图片与视频两种素材下语义完全不同，如果把这套判断
 * 直接写进页面/组件的 `build()`，会被 if 淹没，而且这些分支**无法脱离真机验证**
 * （本工程暂无签名，跑不了 HAP）。抽成纯函数后：
 *   · 页面/卡片只负责"把返回值的几个字段画出来"；
 *   · 这套优先级可以用 `node harmony/scripts/test-analysis-detail.mjs` 离线跑（含边界用例）。
 *
 * ────────────────── 两种素材的语义（本轮用户明确的规范）──────────────────
 *
 *   **图片**（服务端只做一次推理，固定推 1 帧）
 *     · 曲线：只有一个分数，"随帧变化"不存在 → **画一条水平直线**（`CurveMode.flatLine`），
 *       绝不能画一个孤立点（ECharts/图表库上单点几乎看不见，还会让人以为没数据）。
 *     · 分布：一个样本的饼图必然是"100% 一个颜色"，零信息量 →
 *       换成**档位刻度尺**（`SeverityMode.scale`）：0–63 四档色段 + 当前分数指针。
 *
 *   **视频**（服务端按约 60 帧采样逐帧推送）
 *     · 曲线：逐帧 BDI 折线（`CurveMode.series`，横轴 = 帧序号）。
 *     · 分布：**这一段视频的所有帧**分别落在四个档位的数量占比（`SeverityMode.pie`，
 *       环心写「N 帧」）—— 这才是"一段视频里怎么用饼图"的正确答案：
 *       它回答"这段素材里情绪稳定的比例"。
 *
 * ★ 一条硬规则：**图片永远只呈现 1 帧**。
 *   即使服务端（或旧版本）推了 10 条重复帧，`resolveFrames()` 也只留最后一帧、
 *   `displayFrameCount()` 恒为 1。这样"图片看起来像一段 10 帧的视频"这种误解不可能发生。
 *
 * ★ 另一条硬规则：**本文件不碰任何全局状态**。
 *   会话从参数进来（`session`），取不到就是 `null` → 页面走"本机未保留逐帧数据"分支，
 *   绝不允许拿"全局最新一帧"顶替（那正是"所有素材热力图变成同一个人"的根因）。
 */

import {
  AnalysisFrameModel, AnalysisSessionModel, BdiThreshold, BDI_MAX_SCORE, Mapper, MediaType,
  SeverityBucketModel, SeverityLevel, SeverityMeta, UiConstant
} from '../../types/Index';

/** 曲线最多画多少个点（超出则等距抽稀，保留首尾）· 手机窄屏再密就糊成一团 */
export const MAX_CURVE_POINTS: number = 60;

/** 逐帧列表最多渲染多少格（与 `HeatmapViewModel.MAX_STRIP_TILES` 同口径，此处只用于文案） */
export const STRIP_RENDER_LIMIT: number = 24;

/** 情绪曲线的呈现方式 */
export enum CurveMode {
  /** 没有任何分数（等推理） */
  empty = 0,
  /** 只有一个分数 → 画水平直线（图片 / 只收到 1 帧） */
  flatLine = 1,
  /** 多点 → 画折线（视频） */
  series = 2
}

/** 严重度分布的呈现方式 */
export enum SeverityMode {
  /** 没有分数 */
  empty = 0,
  /** 环形饼图（视频：帧级四档分布） */
  pie = 1,
  /** 档位刻度尺（图片 / 帧数不足 2：只有"落在 0–63 的哪个位置"这一个信息） */
  scale = 2
}

/** 情绪曲线卡的取数结果 · 页面/卡片据此选渲染形态 */
export interface CurveView {
  mode: CurveMode;
  /** `series` = 逐帧分数；`flatLine` = 只有一个元素（该分数） */
  points: number[];
  /** 素材是否为图片（决定标题与解释文案） */
  isImage: boolean;
  title: string;
  subtitle: string;
  /** 图下方的一句话说明（写清"为什么是直线/折线"） */
  hint: string;
}

/** 严重度分布卡的取数结果 */
export interface SeverityView {
  mode: SeverityMode;
  /** 视频：四档帧数（`Mapper.toSeverityBuckets` 产出，带颜色与占比） */
  buckets: SeverityBucketModel[];
  /** 参与统计的帧数（视频 = 帧数，图片 = 1） */
  frameTotal: number;
  /** 当前分数（刻度尺的指针位置） */
  score: number;
  level: SeverityLevel;
  levelLabel: string;
  levelColor: string;
  title: string;
  subtitle: string;
  hint: string;
}

/** 空曲线（`@Param` 的默认值 / 无数据态） */
export function emptyCurveView(): CurveView {
  const view: CurveView = {
    mode: CurveMode.empty,
    points: [],
    isImage: false,
    title: '情绪曲线',
    subtitle: '',
    hint: '等待推理结果…'
  };
  return view;
}

/** 空分布 */
export function emptySeverityView(): SeverityView {
  const view: SeverityView = {
    mode: SeverityMode.empty,
    buckets: [],
    frameTotal: 0,
    score: 0,
    level: SeverityLevel.none,
    levelLabel: '',
    levelColor: UiConstant.textSecondaryColor,
    title: '严重度分布',
    subtitle: '',
    hint: '等待推理结果…'
  };
  return view;
}

/**
 * 分数 → 档位配置（**全工程唯一口径**：`BdiThreshold` 判档 + `UiConstant` 取色）
 * ★ 页面不再从参数里读"档位标签/颜色"：那是入栈那一刻的快照，
 *   分析跑完后不会更新（这正是 BUG-15：分析完了档位标签却不出现）。
 */
export function severityMetaOf(score: number): SeverityMeta {
  return UiConstant.severityMeta(BdiThreshold.levelOf(score));
}

/**
 * 本素材**要展示的帧**
 *
 * @param session 该素材自己的会话（`AppStore.analysisSessionOf(mediaId)`），没有则 null
 * @param mediaType 素材类型（会话缺失时也要能判断图片/视频）
 * @returns 图片 → 最多 1 帧（最后一帧）；视频 → 会话里的全部帧；无会话 → 空数组
 */
export function resolveFrames(session: AnalysisSessionModel | null, mediaType: MediaType): AnalysisFrameModel[] {
  if (session === null) {
    return [];
  }
  const frames: AnalysisFrameModel[] = session.frames;
  if (mediaType === MediaType.image) {
    if (frames.length === 0) {
      return [];
    }
    return [frames[frames.length - 1]];
  }
  return frames;
}

/**
 * 展示用的帧数文案里的那个数字
 * ★ 图片恒为 1（哪怕服务端/旧版本推了 10 条重复帧）；视频用实际收到的帧数，
 *   而不是 `frames.length`（后者会被尾部裁剪，说"共 30 帧"会漏掉视频的前半段）。
 */
export function displayFrameCount(session: AnalysisSessionModel | null, mediaType: MediaType): number {
  if (session === null) {
    return 0;
  }
  if (mediaType === MediaType.image) {
    return session.frameCount > 0 ? 1 : 0;
  }
  return session.frameCount;
}

/** 当前分数：会话有就用会话的，否则回落到报告分数（历史素材没有会话时） */
export function latestScore(session: AnalysisSessionModel | null, fallbackScore: number): number {
  if (session !== null) {
    if (session.score > 0) {
      return session.score;
    }
    if (session.scores.length > 0) {
      return session.scores[session.scores.length - 1];
    }
  }
  return fallbackScore > 0 ? fallbackScore : 0;
}

/**
 * 曲线抽稀：等距取样，**保留首尾**
 * 为什么需要：超长视频的分数序列最多 120 点，60 个点画在手机宽度上已经足够，
 * 再多只会让 mpchart 每次重绘都白算一遍。
 */
export function downsampleScores(scores: number[], maxPoints: number): number[] {
  if (maxPoints < 2 || scores.length <= maxPoints) {
    return scores;
  }
  const out: number[] = [];
  const step: number = (scores.length - 1) / (maxPoints - 1);
  for (let i = 0; i < maxPoints; i++) {
    let index: number = Math.round(i * step);
    if (index < 0) {
      index = 0;
    }
    if (index >= scores.length) {
      index = scores.length - 1;
    }
    out.push(scores[index]);
  }
  return out;
}

/**
 * 情绪曲线取数
 *
 * 优先级：
 *   ① **图片** → 恒为直线（只有一个分数，讲"随帧变化"是骗人的）
 *   ② 没有分数 → 空态
 *   ③ 只有 1 点 → 直线（并说明"只收到 1 帧"）
 *   ④ 多个点 → 折线（已抽稀）
 */
export function buildCurveView(
  session: AnalysisSessionModel | null,
  fallbackScore: number,
  mediaType: MediaType
): CurveView {
  const isImage: boolean = mediaType === MediaType.image;
  const view: CurveView = emptyCurveView();
  view.isImage = isImage;
  view.title = isImage ? '情绪曲线（单帧图片）' : '情绪曲线（逐帧 BDI）';
  view.subtitle = isImage
    ? '单张图片只做 1 次推理，没有"随帧变化"可言，因此画成水平直线'
    : '横轴为帧序号，纵轴为 BDI-II 分数（13 / 19 / 28 是四档分界）';

  const score: number = latestScore(session, fallbackScore);
  if (score <= 0) {
    view.hint = '等待推理结果…';
    return view;
  }

  // ① 图片：只有一个分数 → 直线
  if (isImage) {
    view.mode = CurveMode.flatLine;
    view.points = [score];
    view.hint = `分数恒定为 ${score.toFixed(1)}：这张图片只有一次推理，曲线没有第二个点`;
    return view;
  }

  const scores: number[] = session === null ? [] : session.scores;

  // ② 视频但没有逐帧分数序列（本机只存了最终分数，例如 App 重启后看历史素材）：
  //    用已知的分数画直线，别硬编造走势
  if (scores.length === 0) {
    view.mode = CurveMode.flatLine;
    view.points = [score];
    view.hint = '本机只保留了最终分数（没有逐帧序列），因此曲线画成水平直线';
    return view;
  }

  // ③ 视频只收到 1 帧（极短素材 / 早期失败）：同样是直线
  if (scores.length < 2) {
    view.mode = CurveMode.flatLine;
    view.points = [scores[0]];
    view.hint = '本次只收到 1 帧推理结果，曲线无法形成走势，画成水平直线';
    return view;
  }

  // ④ 正常视频：逐帧折线
  view.mode = CurveMode.series;
  view.points = downsampleScores(scores, MAX_CURVE_POINTS);
  const total: number = session === null ? scores.length : session.frameCount;
  view.hint = `逐帧 BDI 分数走势 · 共 ${total} 帧（横轴为帧序号，纵轴 0–63）`;
  return view;
}

/**
 * 严重度分布取数
 *
 * 优先级：
 *   ① **视频且帧数 ≥ 2** → 帧级四档分布（环形饼图）——"这段视频的情绪稳定比例"
 *   ② 其它（图片 / 帧数不足 2）→ 档位刻度尺（单个样本用饼图是零信息量）
 *   ③ 没有分数 → 空态
 */
export function buildSeverityView(
  session: AnalysisSessionModel | null,
  fallbackScore: number,
  mediaType: MediaType
): SeverityView {
  const isImage: boolean = mediaType === MediaType.image;
  const view: SeverityView = emptySeverityView();
  view.title = isImage ? '严重度档位（单帧图片）' : '本段视频的帧级严重度分布';
  view.subtitle = isImage
    ? '单个样本只有一个档位：用刻度尺定位它在 0–63 上的位置'
    : '统计这一段视频的所有帧分别落在四个档位的数量';

  const score: number = latestScore(session, fallbackScore);
  view.score = score;
  const meta: SeverityMeta = severityMetaOf(score);
  view.level = meta.level;
  view.levelLabel = meta.label;
  view.levelColor = meta.color;

  if (score <= 0) {
    view.hint = '等待推理结果…';
    return view;
  }

  const scores: number[] = session === null ? [] : session.scores;

  // ① 视频：帧级分布
  if (!isImage && scores.length >= 2) {
    const distribution: Record<string, number> = { 'none': 0, 'mild': 0, 'moderate': 0, 'severe': 0 };
    for (let i = 0; i < scores.length; i++) {
      const key: string = BdiThreshold.severityOf(scores[i]);
      const current: number | undefined = distribution[key];
      distribution[key] = current === undefined ? 1 : current + 1;
    }
    view.mode = SeverityMode.pie;
    view.frameTotal = scores.length;
    // 复用统计页同一个摊平逻辑（四档顺序、颜色、占比都在 mapper 里算好）
    view.buckets = Mapper.toSeverityBuckets(distribution, scores.length);
    view.hint = `共 ${scores.length} 帧参与统计，四档帧数合计 ${scores.length} 帧`;
    return view;
  }

  // ② 图片 / 帧数不足 2：刻度尺
  view.mode = SeverityMode.scale;
  view.frameTotal = isImage ? 1 : scores.length;
  view.hint = isImage
    ? '单张图片只有 1 个档位，饼图只会是一个整圆，所以用刻度尺表示"它在量表的哪个位置"'
    : '本素材帧数不足 2，无法做帧级分布，改用刻度尺展示当前档位';
  return view;
}

/** 某档位在 0–63 量表上的跨度（用作刻度尺的宽度权重） */
export function bandSpan(level: SeverityLevel): number {
  if (level === SeverityLevel.none) {
    return BdiThreshold.normalMax + 1;                    // 0–13 → 14
  }
  if (level === SeverityLevel.mild) {
    return BdiThreshold.mildMax - BdiThreshold.normalMax; // 14–19 → 6
  }
  if (level === SeverityLevel.moderate) {
    return BdiThreshold.moderateMax - BdiThreshold.mildMax; // 20–28 → 9
  }
  return BDI_MAX_SCORE - BdiThreshold.moderateMax;        // 29–63 → 35
}
