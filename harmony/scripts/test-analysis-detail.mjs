/**
 * test-analysis-detail.mjs · 工作台分析区**取数逻辑**离线测试
 *
 * ────────────────── 为什么需要它 ──────────────────
 * 分析内容已从独立详情页搬进工作台主页：hero / 热力图 / 情绪曲线 / 严重度分布 / VLM
 * 都在 `WorkbenchPage` 与 `components/analysis/**` 里。而"图片 / 视频"、
 * "有会话 / 只有报告分数"、"1 帧 / N 帧"、"跨素材取错帧"这些组合共有十余种分支，
 * 全部靠真机点一遍不现实（本工程暂无签名，跑不了 HAP）。所以沿用本仓库既有做法：
 *
 *   · 下面把 `components/charts/AnalysisChartModel.ets` 的判定**逐行镜像**到 Node；
 *   · 用例覆盖用户亲自报过的三个现象（图片十帧 / 回来只剩一帧 / 素材串台）；
 *   · 再做**源码文本级检查**，确认真正生效的 `.ets` / `.py` / `.vue` 里仍是同一套逻辑，
 *     避免"测试里的镜像改了、产品代码没改"这种假绿。
 *
 * ★ 本轮（工作台主页重构）页面路径从 `pages/AnalysisDetailPage.ets` 改为
 *   `pages/WorkbenchPage.ets` + `components/workbench/AnalysisHeroCard.ets`。
 *   断言口径不变：图片=1 帧、箭头/刻度尺分流、图表已接线、绝不跨素材兜底。
 *
 * 用法：node harmony/scripts/test-analysis-detail.mjs
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const ETS = join(HERE, '..', 'entry', 'src', 'main', 'ets');
const MODEL_PATH = join(ETS, 'components', 'charts', 'AnalysisChartModel.ets');
/** 分析内容现在的主页面 */
const PAGE_PATH = join(ETS, 'pages', 'WorkbenchPage.ets');
/** hero 里的类型徽标 / 分数装配 */
const HERO_PATH = join(ETS, 'components', 'workbench', 'AnalysisHeroCard.ets');
/** 从详情页搬入的热力图卡 */
const HEATMAP_PATH = join(ETS, 'components', 'analysis', 'AnalysisHeatmapCard.ets');
const HOLDER_PATH = join(ETS, 'store', 'AnalysisStateHolder.ets');
const STORE_PATH = join(ETS, 'store', 'AppStore.ets');
const BACKEND_PATH = join(HERE, '..', '..', 'dashboard', 'backend', 'services', 'frame_processor.py');
const WEB_CURVE_PATH = join(HERE, '..', '..', 'dashboard', 'src', 'components', 'right-panel', 'EmotionCurve.vue');

// ═══════════════ 与 AnalysisChartModel.ets 同口径的镜像实现 ═══════════════

const IMAGE = 'image';
const VIDEO = 'video';
const MAX_CURVE_POINTS = 60;

const LEVELS = ['none', 'mild', 'moderate', 'severe'];
const LABELS = { none: '正常', mild: '轻度', moderate: '中度', severe: '重度' };
const COLORS = { none: '#16a34a', mild: '#0284c7', moderate: '#d97706', severe: '#dc2626' };
const BDI_MAX = 63;

/** 与 `BdiThreshold.severityOf` 同口径（0–13 / 14–19 / 20–28 / 29–63） */
function severityKey(score) {
  if (score <= 13) return 'none';
  if (score <= 19) return 'mild';
  if (score <= 28) return 'moderate';
  return 'severe';
}

/** 与 `Mapper.toSeverityBuckets` 同口径 */
function toBuckets(distribution, total) {
  const sum = total > 0 ? total : LEVELS.reduce((acc, k) => acc + (distribution[k] || 0), 0);
  return LEVELS.map((level) => ({
    severity: level,
    label: LABELS[level],
    count: distribution[level] || 0,
    color: COLORS[level],
    ratio: sum > 0 ? (distribution[level] || 0) / sum : 0
  }));
}

/** 与 `bandSpan` 同口径 */
function bandSpan(level) {
  if (level === 'none') return 14;      // 0–13
  if (level === 'mild') return 6;       // 14–19
  if (level === 'moderate') return 9;   // 20–28
  return BDI_MAX - 28;                  // 29–63 → 35
}

function resolveFrames(session, mediaType) {
  if (session === null) return [];
  const frames = session.frames;
  if (mediaType === IMAGE) {
    if (frames.length === 0) return [];
    return [frames[frames.length - 1]];
  }
  return frames;
}

function displayFrameCount(session, mediaType) {
  if (session === null) return 0;
  if (mediaType === IMAGE) return session.frameCount > 0 ? 1 : 0;
  return session.frameCount;
}

function latestScore(session, fallbackScore) {
  if (session !== null) {
    if (session.score > 0) return session.score;
    if (session.scores.length > 0) return session.scores[session.scores.length - 1];
  }
  return fallbackScore > 0 ? fallbackScore : 0;
}

function downsampleScores(scores, maxPoints) {
  if (maxPoints < 2 || scores.length <= maxPoints) return scores;
  const out = [];
  const step = (scores.length - 1) / (maxPoints - 1);
  for (let i = 0; i < maxPoints; i++) {
    let index = Math.round(i * step);
    if (index < 0) index = 0;
    if (index >= scores.length) index = scores.length - 1;
    out.push(scores[index]);
  }
  return out;
}

function buildCurveView(session, fallbackScore, mediaType) {
  const isImage = mediaType === IMAGE;
  const view = { mode: 'empty', points: [], isImage };
  const score = latestScore(session, fallbackScore);
  if (score <= 0) return view;
  if (isImage) {
    view.mode = 'flatLine';
    view.points = [score];
    return view;
  }
  const scores = session === null ? [] : session.scores;
  if (scores.length === 0) {
    view.mode = 'flatLine';
    view.points = [score];
    return view;
  }
  if (scores.length < 2) {
    view.mode = 'flatLine';
    view.points = [scores[0]];
    return view;
  }
  view.mode = 'series';
  view.points = downsampleScores(scores, MAX_CURVE_POINTS);
  return view;
}

function buildSeverityView(session, fallbackScore, mediaType) {
  const isImage = mediaType === IMAGE;
  const score = latestScore(session, fallbackScore);
  const view = { mode: 'empty', buckets: [], frameTotal: 0, score, level: severityKey(score) };
  if (score <= 0) return view;
  const scores = session === null ? [] : session.scores;
  if (!isImage && scores.length >= 2) {
    const distribution = { none: 0, mild: 0, moderate: 0, severe: 0 };
    for (const s of scores) distribution[severityKey(s)] += 1;
    view.mode = 'pie';
    view.frameTotal = scores.length;
    view.buckets = toBuckets(distribution, scores.length);
    return view;
  }
  view.mode = 'scale';
  view.frameTotal = isImage ? 1 : scores.length;
  return view;
}

/** 与 `AnalysisStateHolder.sessionOf` 同口径：只按 mediaId 精确取，绝不跨素材兜底 */
function sessionOf(sessions, mediaId) {
  if (mediaId.length === 0) return null;
  for (const s of sessions) {
    if (s.mediaId === mediaId) return s;
  }
  return null;
}

// ═══════════════ 测试夹具 ═══════════════

/** 造一帧：热度矩阵里写指纹值，用来证明"拿到的确实是这一帧/这个素材" */
function frame(id, score, marker) {
  return {
    frameId: id,
    timestamp: 0,
    bdiScore: score,
    alignedFace: '',
    heatmapData: [[marker]],
    inferenceTimeMs: 28.5,
    progress: 1
  };
}

/** 造一个会话 */
function session(mediaId, mediaType, scores, opts = {}) {
  const frames = opts.frames || scores.map((s, i) => frame(i + 1, s, (i + 1) / 100));
  return {
    mediaId,
    mediaType,
    status: opts.status || 'done',
    progress: 1,
    score: opts.score === undefined ? scores[scores.length - 1] || 0 : opts.score,
    frameCount: opts.frameCount === undefined ? frames.length : opts.frameCount,
    frames,
    scores,
    vlmText: opts.vlmText || '',
    errorMsg: opts.errorMsg || '',
    updatedAt: 0
  };
}

let failures = 0;
function check(name, ok, detail) {
  if (ok) {
    console.log(`  [OK]   ${name}`);
  } else {
    failures += 1;
    console.log(`  [FAIL] ${name}\n         ${detail}`);
  }
}

/**
 * 去掉注释后的源码
 *
 * ★ 为什么"禁止出现某标识"这类断言必须先剥注释：本工程的注释里会**大量引用**
 *   被删掉的旧实现（"旧签名里有 `lastFrame`…"），那是文档而不是代码。
 *   只看代码才不会把说明文字误判成回归。
 */
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .map((line) => line.replace(/\/\/.*$/, ''))
    .join('\n');
}

// ═══════════════ 用例 1：图片素材（用户主诉一）═══════════════
console.log('1) 图片素材：只做 1 次推理 → 永远只呈现 1 帧、曲线是直线、分布是刻度尺');
{
  // ★ 刻意模拟"旧服务端推了 10 条重复帧"的情形：端上也必须归一成 1 帧
  const scores = new Array(10).fill(22);
  const img = session('21', IMAGE, scores, { score: 22.4, frameCount: 10 });
  check('resolveFrames = 1 帧（10 条重复帧被归一）', resolveFrames(img, IMAGE).length === 1,
    `实际 ${resolveFrames(img, IMAGE).length}`);
  check('保留的是最后一帧', resolveFrames(img, IMAGE)[0].frameId === 10, '不是最后一帧');
  check('displayFrameCount = 1（哪怕 frameCount 是 10）', displayFrameCount(img, IMAGE) === 1,
    `实际 ${displayFrameCount(img, IMAGE)}`);

  const curve = buildCurveView(img, 0, IMAGE);
  check('曲线 mode = flatLine（不是 series）', curve.mode === 'flatLine', `实际 ${curve.mode}`);
  check('曲线只有一个点', curve.points.length === 1, `实际 ${curve.points.length}`);
  check('曲线点 = 本次分数', curve.points[0] === 22.4, `实际 ${curve.points[0]}`);

  const sev = buildSeverityView(img, 0, IMAGE);
  check('分布 mode = scale（图片不画饼图）', sev.mode === 'scale', `实际 ${sev.mode}`);
  check('分布 frameTotal = 1', sev.frameTotal === 1, `实际 ${sev.frameTotal}`);
  check('档位 = 中度', sev.level === 'moderate', `实际 ${sev.level}`);
}

// ═══════════════ 用例 2：视频素材 ═══════════════
console.log('\n2) 视频素材：逐帧 → 曲线是折线、分布是帧级饼图，四档合计 = 帧数');
{
  const scores = [5, 8, 12, 15, 18, 20, 24, 27, 30, 35, 40, 60];
  const vid = session('31', VIDEO, scores);
  const curve = buildCurveView(vid, 0, VIDEO);
  check('曲线 mode = series', curve.mode === 'series', `实际 ${curve.mode}`);
  check('点数 = 帧数（未超上限时不抽稀）', curve.points.length === scores.length,
    `实际 ${curve.points.length}`);
  check('首尾保留', curve.points[0] === 5 && curve.points[11] === 60,
    `首 ${curve.points[0]} 末 ${curve.points[11]}`);

  const sev = buildSeverityView(vid, 0, VIDEO);
  check('分布 mode = pie', sev.mode === 'pie', `实际 ${sev.mode}`);
  check('frameTotal = 帧数', sev.frameTotal === scores.length, `实际 ${sev.frameTotal}`);
  check('四档 buckets', sev.buckets.length === 4, `实际 ${sev.buckets.length}`);
  check('四档计数之和 = 帧数', sev.buckets.reduce((a, b) => a + b.count, 0) === scores.length,
    `实际 ${sev.buckets.reduce((a, b) => a + b.count, 0)}`);
  check('四档占比之和 ≈ 1',
    Math.abs(sev.buckets.reduce((a, b) => a + b.ratio, 0) - 1) < 1e-9,
    `实际 ${sev.buckets.reduce((a, b) => a + b.ratio, 0)}`);
  check('档位顺序固定为 正常→轻度→中度→重度',
    sev.buckets.map((b) => b.severity).join(',') === 'none,mild,moderate,severe',
    sev.buckets.map((b) => b.severity).join(','));
  check('计数正确（≤13:3 / 14–19:2 / 20–28:3 / ≥29:4）',
    sev.buckets[0].count === 3 && sev.buckets[1].count === 2 &&
    sev.buckets[2].count === 3 && sev.buckets[3].count === 4,
    sev.buckets.map((b) => b.count).join(','));
}

// ═══════════════ 用例 3：视频只收到 1 帧 / 超长视频抽稀 ═══════════════
console.log('\n3) 视频边界：只有 1 帧 → 直线；超长视频 → 抽稀到 60 点但保留首尾');
{
  const one = session('32', VIDEO, [18]);
  check('1 帧 → flatLine', buildCurveView(one, 0, VIDEO).mode === 'flatLine', '不是直线');
  check('1 帧 → 分布退化刻度尺', buildSeverityView(one, 0, VIDEO).mode === 'scale', '不是刻度尺');

  // ★ 分数必须都 > 0：0 分在实现里的语义是"还没有分数"（`latestScore` 会退回兜底），
  //   所以夹具不能拿 0 当数据点，否则测的就不是抽稀而是空态了。
  const long = [];
  for (let i = 1; i <= 120; i++) long.push((i % 50) + 5);
  const longSession = session('33', VIDEO, long);
  const curve = buildCurveView(longSession, 0, VIDEO);
  check('抽稀到 60 点', curve.points.length === 60, `实际 ${curve.points.length}`);
  check('抽稀后首点保留', curve.points[0] === long[0], `实际 ${curve.points[0]}`);
  check('抽稀后末点保留', curve.points[59] === long[119], `实际 ${curve.points[59]}`);
}

// ═══════════════ 用例 4：没有本机会话（App 重启后看历史素材）═══════════════
console.log('\n4) 本机没有会话：绝不让曲线/分布编造走势，也不拿别的素材兜底');
{
  const curveImg = buildCurveView(null, 0, IMAGE);
  check('图片 + 无会话 + 无报告分数 → empty', curveImg.mode === 'empty', `实际 ${curveImg.mode}`);
  const sevImg = buildSeverityView(null, 0, IMAGE);
  check('分布同样 empty', sevImg.mode === 'empty', `实际 ${sevImg.mode}`);

  // 有报告分数（从「最近使用的素材」进来）：用报告分数画直线 + 刻度尺
  const curveReport = buildCurveView(null, 18.4, VIDEO);
  check('视频 + 只有报告分数 → 直线（不编造走势）', curveReport.mode === 'flatLine',
    `实际 ${curveReport.mode}`);
  check('直线分数 = 报告分数', curveReport.points[0] === 18.4, `实际 ${curveReport.points[0]}`);
  const sevReport = buildSeverityView(null, 18.4, VIDEO);
  check('分布 = 刻度尺（无法做帧级分布）', sevReport.mode === 'scale', `实际 ${sevReport.mode}`);
}

// ═══════════════ 用例 5：★ 回归 —— 两个素材并存时不串台 ═══════════════
console.log('\n5) ★ 回归：A / B 两个素材的会话并存，按 mediaId 取帧绝不串台');
{
  const a = session('41', VIDEO, [10, 11, 12], { frames: [frame(1, 10, 0.11), frame(2, 11, 0.12), frame(3, 12, 0.13)] });
  const b = session('42', VIDEO, [40, 41, 42], { frames: [frame(1, 40, 0.91), frame(2, 41, 0.92), frame(3, 42, 0.93)] });
  const sessions = [a, b];

  const gotA = resolveFrames(sessionOf(sessions, '41'), VIDEO);
  const gotB = resolveFrames(sessionOf(sessions, '42'), VIDEO);
  const aMarks = gotA.map((f) => f.heatmapData[0][0]);
  const bMarks = gotB.map((f) => f.heatmapData[0][0]);
  check('看 A 只拿到 A 的帧', aMarks.join(',') === '0.11,0.12,0.13', aMarks.join(','));
  check('看 B 只拿到 B 的帧', bMarks.join(',') === '0.91,0.92,0.93', bMarks.join(','));
  check('A 的结果里不含 B 的任何帧', !aMarks.some((m) => m > 0.5), aMarks.join(','));
  check('取不存在的素材 → null（宁可空，也不兜底）', sessionOf(sessions, '99') === null,
    '竟然取到了东西');
  check('空 id → null', sessionOf(sessions, '') === null, '竟然取到了东西');
}

// ═══════════════ 用例 6：判档 / 刻度尺权重 ═══════════════
console.log('\n6) 判档边界与刻度尺权重');
{
  check('13 → none', severityKey(13) === 'none', severityKey(13));
  check('14 → mild', severityKey(14) === 'mild', severityKey(14));
  check('19 → mild', severityKey(19) === 'mild', severityKey(19));
  check('20 → moderate', severityKey(20) === 'moderate', severityKey(20));
  check('28 → moderate', severityKey(28) === 'moderate', severityKey(28));
  check('29 → severe', severityKey(29) === 'severe', severityKey(29));
  const spans = LEVELS.map(bandSpan);
  check('四档跨度 14/6/9/35', spans.join(',') === '14,6,9,35', spans.join(','));
  check('跨度之和 = 64（与 0–63 的量表一致）', spans.reduce((x, y) => x + y, 0) === 64,
    `${spans.reduce((x, y) => x + y, 0)}`);
}

// ═══════════════ 用例 7：源码文本级检查（防止镜像与产品代码脱钩）═══════════════
console.log('\n7) 源码文本级检查');
const modelSrc = readFileSync(MODEL_PATH, 'utf8');
const pageSrc = readFileSync(PAGE_PATH, 'utf8');
const heroSrc = readFileSync(HERO_PATH, 'utf8');
const heatmapSrc = readFileSync(HEATMAP_PATH, 'utf8');
const holderSrc = readFileSync(HOLDER_PATH, 'utf8');
const storeSrc = readFileSync(STORE_PATH, 'utf8');

const required = [
  [modelSrc, 'AnalysisChartModel 含 resolveFrames', /export function resolveFrames/],
  [modelSrc, 'AnalysisChartModel 图片只留最后一帧', /return \[frames\[frames\.length - 1\]\];/],
  [modelSrc, 'AnalysisChartModel 图片帧数恒为 1', /return session\.frameCount > 0 \? 1 : 0;/],
  [modelSrc, 'AnalysisChartModel 曲线抽稀上限 60', /MAX_CURVE_POINTS: number = 60/],
  [modelSrc, 'AnalysisChartModel 视频才画饼图', /if \(!isImage && scores\.length >= 2\)/],
  [modelSrc, 'AnalysisChartModel 复用 mapper 摊平四档', /Mapper\.toSeverityBuckets\(distribution, scores\.length\)/],
  [pageSrc, '工作台用 buildCurveView', /buildCurveView\(\s*this\.session/],
  [pageSrc, '工作台用 buildSeverityView', /buildSeverityView\(\s*this\.session/],
  [pageSrc, '工作台按 mediaId 取会话', /analysisSessionOf\(current\.mediaId\)/],
  [pageSrc, '工作台挂载情绪曲线卡', /EmotionCurveCard\(\{ view: this\.curveView \}\)/],
  [pageSrc, '工作台挂载严重度分布卡', /SeverityDistributionCard\(\{ view: this\.severityView \}\)/],
  [pageSrc, '工作台挂载热力图卡', /AnalysisHeatmapCard\(\{/],
  [heroSrc, 'hero 有类型徽标', /MediaTypeBadge\(\{ mediaType: this\.model\.mediaType \}\)/],
  [heatmapSrc, '热力图卡按传入 frames 取数', /buildHeatmapView\(this\.frames/],
  [holderSrc, '桥接器按素材取会话', /public sessionOf\(mediaId: string\)/],
  [holderSrc, '桥接器归档上限 6 条会话', /MAX_ARCHIVE_SESSIONS: number = 6/],
  [holderSrc, '桥接器收尾裁剪 30 帧', /MAX_ARCHIVE_FRAMES: number = 30/],
  [storeSrc, '门面按素材取会话', /public analysisSessionOf\(mediaId: string\)/],
  [storeSrc, '门面把素材类型交给桥接器', /this\.analysis\(\)\.start\(id, type\)/]
];
for (const [src, name, re] of required) {
  check(`源码含「${name}」`, re.test(src), `未匹配 ${re}`);
}

const analysisSources = [
  [pageSrc, '工作台'],
  [heroSrc, 'hero'],
  [heatmapSrc, '热力图卡']
];
const forbiddenAnalysis = [
  ['图表占位块 chartPlaceholder', /chartPlaceholder/],
  ['全局最后一帧兜底 analysisLastFrame', /analysisLastFrame/],
  ['followLiveTask 开关', /followLiveTask/]
];
for (const [src, label] of analysisSources) {
  for (const [name, re] of forbiddenAnalysis) {
    check(`${label} 已无「${name}」（已剥注释）`, !re.test(stripComments(src)), `仍匹配 ${re}`);
  }
}
const forbidden = [
  [holderSrc, '桥接器已无全局 frameHistory', /frameHistory/],
  [holderSrc, '桥接器已无全局 scoreHistory', /scoreHistory/],
  [storeSrc, '门面已无 analysisFrameHistory', /analysisFrameHistory/]
];
for (const [src, name, re] of forbidden) {
  // 只看代码，注释里的历史说明不算回归（见 stripComments 的说明）
  check(`源码「${name}」（已剥注释）`, !re.test(stripComments(src)), `仍匹配 ${re}`);
}

// ═══════════════ 用例 8：服务端与网页端（跨端一致性）═══════════════
console.log('\n8) 服务端 / 网页端一致性');
const backendSrc = readFileSync(BACKEND_PATH, 'utf8');
const webCurveSrc = readFileSync(WEB_CURVE_PATH, 'utf8');

check('服务端图片路径不再伪造 10 帧（无 steps = 10）', !/steps = 10/.test(backendSrc),
  '仍存在 steps = 10');
check('服务端图片路径只推 1 帧（progress=1.0）', /progress=1\.0/.test(backendSrc),
  '未找到 progress=1.0');
check('网页端曲线处理"只有一个分数"（单点补成直线）', /isSinglePoint|singlePoint/.test(webCurveSrc),
  '未找到单点处理');

// ═══════════════ 汇总 ═══════════════
console.log('');
if (failures === 0) {
  console.log('PASS 全部通过：工作台分析区保持「图片=单帧/直线/刻度尺，视频=逐帧/折线/帧级分布」，且素材之间不串台。');
  process.exit(0);
}
console.log(`FAIL 存在 ${failures} 处失败。`);
process.exit(1);
