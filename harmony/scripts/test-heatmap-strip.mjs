/**
 * test-heatmap-strip.mjs · 横向逐帧列表**取数逻辑**离线测试
 *
 * ────────────────── 为什么需要它 ──────────────────
 * `HeatmapViewModel.ets` 里的 `buildHeatmapView()` 决定了"主图画哪一帧"，而它要处理
 * 三种数据情形（手动固定 / 本素材的帧 / 演示数据）与三种边界（空列表 / 越界下标 / 空矩阵）。
 * 这些分支如果只靠真机点击去试，覆盖不全而且每次都要重装 HAP。
 *
 * 所以这里用**逻辑镜像**的方式把同一套判定搬到 Node 里跑：
 *   · 下面 `buildView()` 是 `HeatmapViewModel.ets` 的逐行对照实现（同样的优先级顺序）；
 *   · 用例覆盖"用户手感"的关键点：**没手动选过时必须取最后一帧**（列表右端 = 最新）。
 *   · 另有一条**源码文本级检查**：确认真正生效的 `.ets` 里仍有相同的判定顺序与常量，
 *     避免"测试里的镜像改了、产品代码没改"这种假绿。
 *
 * ★★ 本轮新增的**回归守卫**（"所有帧都是同一帧"）：
 *   旧实现超出 24 格时 `slice` 保留**最后 24 帧**。服务端一批正好 24 帧，
 *   于是整列就是一个批次的同一张图（连帧号都因尾批补帧而错位）。
 *   现在必须**按时间均匀抽取（含首尾）**，且收尾裁剪也必须是抽稀而不是砍头。
 *
 * 用法：node harmony/scripts/test-heatmap-strip.mjs
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const VM_PATH = join(HERE, '..', 'entry', 'src', 'main', 'ets', 'components', 'charts', 'HeatmapViewModel.ets');
const HOLDER_PATH = join(HERE, '..', 'entry', 'src', 'main', 'ets', 'store', 'AnalysisStateHolder.ets');

// ───────────────── 与 HeatmapViewModel.ets 同口径的镜像实现 ─────────────────

const SOURCE = { pinned: 0, live: 1, snapshot: 2, sample: 3 };

function hasHeat(f) {
  return f.heatmapData.length > 0 && f.heatmapData[0].length > 0;
}

/** 等距抽样（保留首尾）· 与 .ets 里的 sampleEvenly 逐行对应 */
function sampleEvenly(frames, maxTiles) {
  if (maxTiles <= 0) return [];
  if (frames.length <= maxTiles) return frames;
  const out = [];
  const lastIndex = frames.length - 1;
  const step = lastIndex / (maxTiles - 1);
  for (let i = 0; i < maxTiles; i++) {
    let index = Math.round(i * step);
    if (index < 0) index = 0;
    if (index > lastIndex) index = lastIndex;
    out.push(frames[index]);
  }
  return out;
}

function heatOnly(frames, maxTiles) {
  return sampleEvenly(frames.filter(hasHeat), maxTiles);
}

function pickIndex(frames, focusedIndex, lastIndex) {
  if (frames.length === 0) return -1;
  if (focusedIndex >= 0 && focusedIndex < frames.length) return focusedIndex;
  return lastIndex;
}

function buildView(frames, sampleFrames, focusedIndex, isLive, maxTiles = 24) {
  const own = heatOnly(frames, maxTiles);
  if (own.length > 0) {
    const last = own.length - 1;
    const index = pickIndex(own, focusedIndex, last);
    const pinned = focusedIndex >= 0 && index === focusedIndex;
    return {
      frames: own,
      heatmap: index >= 0 ? own[index].heatmapData : [],
      index,
      focusedIndex,
      source: pinned ? SOURCE.pinned : (isLive ? SOURCE.live : SOURCE.snapshot)
    };
  }
  const demo = heatOnly(sampleFrames, maxTiles);
  const last = demo.length - 1;
  const index = pickIndex(demo, focusedIndex, last);
  return {
    frames: demo,
    heatmap: index >= 0 ? demo[index].heatmapData : [],
    index,
    focusedIndex,
    source: SOURCE.sample
  };
}

// ───────────────── 断言 ─────────────────

let failures = 0;
function check(name, ok, detail) {
  if (ok) {
    console.log(`  [OK]   ${name}`);
  } else {
    failures += 1;
    console.log(`  [FAIL] ${name}\n         ${detail}`);
  }
}

/** 造一帧 · 每帧的热度矩阵里写一个"指纹值"，用来验证"画的确实是那一帧" */
function frame(id, marker, withHeat = true) {
  return {
    frameId: id,
    heatmapData: withHeat ? [[marker]] : [],
    bdiScore: id * 1.5
  };
}

/**
 * 去掉注释后的源码
 *
 * ★ "禁止出现某标识"这类断言必须先剥注释：本工程的注释会**大量引用**被删掉的旧实现
 *   （"旧签名里有 `lastFrame`…"），那是文档不是代码。只看代码才不会误判成回归。
 */
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .map((line) => line.replace(/\/\/.*$/, ''))
    .join('\n');
}

console.log('1) 有帧但没手动选过时，必须取【最后一格】（列表右端 = 最新）');
{
  const own = [frame(1, 0.1), frame(2, 0.5), frame(3, 0.9)];
  const v = buildView(own, [], -1, true);
  check('index = 最后一格', v.index === 2, `实际 ${v.index}`);
  check('主图取到第 3 帧的矩阵', v.heatmap[0][0] === 0.9, `实际 ${JSON.stringify(v.heatmap)}`);
  check('source = live（帧来自正在跑的会话）', v.source === SOURCE.live, `实际 ${v.source}`);
}

console.log('\n2) 手动固定第 1 格：主图必须是那一帧，且 source = pinned');
{
  const own = [frame(1, 0.1), frame(2, 0.5), frame(3, 0.9)];
  const v = buildView(own, [], 0, true);
  check('index = 0', v.index === 0, `实际 ${v.index}`);
  check('主图取到第 1 帧的矩阵（不是最新帧）', v.heatmap[0][0] === 0.1, `实际 ${JSON.stringify(v.heatmap)}`);
  check('source = pinned', v.source === SOURCE.pinned, `实际 ${v.source}`);
}

console.log('\n3) 越界下标（换了素材 / 新一轮分析把列表换了）→ 退回最后一格，而不是第 0 格');
{
  const own = [frame(1, 0.1), frame(2, 0.5)];
  const v = buildView(own, [], 7, true);
  check('index = 1（最后一格）', v.index === 1, `实际 ${v.index}`);
}

console.log('\n4) 空热度矩阵的帧必须被过滤掉（否则缩略图是灰块）');
{
  const own = [frame(1, 0.2), frame(2, 0, false), frame(3, 0.8)];
  const v = buildView(own, [], -1, true);
  check('frames 只剩 2 帧', v.frames.length === 2, `实际 ${v.frames.length}`);
  check('主图 = 有数据的最新帧', v.heatmap[0][0] === 0.8, `实际 ${JSON.stringify(v.heatmap)}`);
}

console.log('\n5) 渲染上限：超出时按时间【均匀抽取】（不能再只留最后 N 帧）');
{
  const own = [];
  for (let i = 1; i <= 40; i++) own.push(frame(i, i / 100));
  const v = buildView(own, [], -1, true, 24);
  check('frames 被抽到 24 格', v.frames.length === 24, `实际 ${v.frames.length}`);
  check('保留首帧（第 1 格 = #1）', v.frames[0].frameId === 1, `实际 ${v.frames[0].frameId}`);
  check('保留尾帧（最后一格 = #40）', v.frames[23].frameId === 40, `实际 ${v.frames[23].frameId}`);
  check('抽稀后的帧号严格递增（无重复格）',
    v.frames.every((f, i) => i === 0 || f.frameId > v.frames[i - 1].frameId),
    `帧号 ${v.frames.map((f) => f.frameId).join(',')}`);
  check('主图仍是最新帧', v.heatmap[0][0] === 0.4, `实际 ${JSON.stringify(v.heatmap)}`);
}

console.log('\n5b) 真实视频口径：60 帧抽 24 格，必须覆盖整段（首尾都在）');
{
  const own = [];
  for (let i = 1; i <= 60; i++) own.push(frame(i, i / 100));
  const v = buildView(own, [], -1, true, 24);
  check('共 24 格', v.frames.length === 24, `实际 ${v.frames.length}`);
  check('覆盖第 1 帧', v.frames[0].frameId === 1, `实际 ${v.frames[0].frameId}`);
  check('覆盖第 60 帧', v.frames[23].frameId === 60, `实际 ${v.frames[23].frameId}`);
  let maxGap = 0;
  for (let i = 1; i < v.frames.length; i++) {
    maxGap = Math.max(maxGap, v.frames[i].frameId - v.frames[i - 1].frameId);
  }
  check('相邻格间隔 ≤ 4 帧（不是挤在最后一个批次里）', maxGap <= 4, `最大间隔 ${maxGap}`);
}

console.log('\n6) 本素材的归档会话（isLive = false）→ source = snapshot（文案要说清是归档）');
{
  const own = [frame(1, 0.3), frame(2, 0.7)];
  const v = buildView(own, [], -1, false);
  check('source = snapshot', v.source === SOURCE.snapshot, `实际 ${v.source}`);
  check('仍取最后一格', v.heatmap[0][0] === 0.7, `实际 ${JSON.stringify(v.heatmap)}`);
}

console.log('\n7) 本素材一帧都没有 → 走演示数据，且**必须**带上 sample 标记');
{
  const demo = [frame(1, 0.3), frame(2, 0.6)];
  const v = buildView([], demo, -1, true);
  check('frames = 演示帧', v.frames.length === 2, `实际 ${v.frames.length}`);
  check('source = sample（界面会打"演示数据"标记）', v.source === SOURCE.sample, `实际 ${v.source}`);
  check('主图 = 演示数据最后一帧', v.heatmap[0][0] === 0.6, `实际 ${JSON.stringify(v.heatmap)}`);
}

console.log('\n8) 全空：不该崩，且 index = -1、heatmap 为空数组（方块组件走占位态）');
{
  const v = buildView([], [], -1, true);
  check('index = -1', v.index === -1, `实际 ${v.index}`);
  check('heatmap 为空数组', v.heatmap.length === 0, `实际 ${JSON.stringify(v.heatmap)}`);
  check('source = sample', v.source === SOURCE.sample, `实际 ${v.source}`);
}

console.log('\n9) ★ 回归：本素材没有帧时**绝不**拿"别的素材/全局最后一帧"兜底');
{
  // 别的素材的帧（指纹 0.99）故意放在 sampleFrames 之外的地方，模拟"全局最新一帧"
  const otherMediaFrame = frame(99, 0.99);
  const v = buildView([], [], -1, true);
  const leaked = v.frames.some((f) => f.heatmapData.length > 0 && f.heatmapData[0][0] === 0.99);
  check('空帧数组不会泄漏出任何别的素材的帧', !leaked, `frames=${JSON.stringify(v.frames)}`);
  check('空帧数组 + 无演示帧 → frames 为空', v.frames.length === 0, `实际 ${v.frames.length}`);
  // 源码里也不允许存在那条兜底（只看代码，注释里的历史说明不算——见 stripComments）
  const rawSrc = readFileSync(VM_PATH, 'utf8');
  const code = stripComments(rawSrc);
  check('HeatmapViewModel.ets 代码里已无 lastFrame 兜底参数', !/lastFrame/.test(code), '仍出现 lastFrame');
  check('HeatmapViewModel.ets 代码里已无 followLiveTask 开关', !/followLiveTask/.test(code), '仍出现 followLiveTask');
  // 提醒：这个用例本身不用 otherMediaFrame，只是把它"摆在场上"表明它不该被取到
  check('（基线）别的素材那一帧确实存在', otherMediaFrame.heatmapData[0][0] === 0.99, '构造错误');
}

console.log('\n10) 源码文本级检查（防止镜像与产品代码脱钩）');
const src = readFileSync(VM_PATH, 'utf8');
const required = [
  ['渲染上限常量 24', /MAX_STRIP_TILES: number = 24/],
  ['只保留有热度数据的帧', /function heatOnly/],
  ['均匀抽样函数（含首尾）', /function sampleEvenly/],
  ['抽稀用四舍五入等距', /Math\.round\(i \* step\)/],
  ['本素材帧优先', /const own: AnalysisFrameModel\[\] = heatOnly\(frames\)/],
  ['pinned 判定', /focusedIndex >= 0 && index === focusedIndex/],
  ['live / snapshot 分流', /isLive \? HeatSource\.live : HeatSource\.snapshot/],
  ['演示数据分支', /const demo: AnalysisFrameModel\[\] = heatOnly\(sampleFrames\)/],
  ['越界退回最后一格', /return lastIndex;/]
];
for (const [name, re] of required) {
  check(`HeatmapViewModel.ets 含「${name}」`, re.test(src), `未匹配 ${re}`);
}
check('HeatmapViewModel.ets 不再「只留最后 24 帧」',
  !/out\.slice\(out\.length - MAX_STRIP_TILES\)/.test(src),
  '仍存在 out.slice(out.length - MAX_STRIP_TILES)');

console.log('\n11) 归档裁剪也必须是抽稀（只留尾部 = 列表里全是同一批）');
{
  const holder = readFileSync(HOLDER_PATH, 'utf8');
  check('AnalysisStateHolder 用 sampleEvenly 抽稀', /sampleEvenly\(prev\.frames, MAX_ARCHIVE_FRAMES\)/.test(holder),
    '未找到 sampleEvenly(prev.frames, MAX_ARCHIVE_FRAMES)');
  check('AnalysisStateHolder 不再从头部切掉帧',
    !/frames\.slice\(frames\.length - MAX_ARCHIVE_FRAMES\)/.test(stripComments(holder)),
    '仍存在 frames.slice(frames.length - MAX_ARCHIVE_FRAMES)');
  check('归档上限常量仍为 30', /MAX_ARCHIVE_FRAMES: number = 30/.test(holder), '未找到 30');
}

console.log('');
if (failures === 0) {
  console.log('PASS 全部通过：横向逐帧列表取数逻辑符合预期（且不再跨素材兜底）。');
  process.exit(0);
}
console.log(`FAIL 存在 ${failures} 处失败。`);
process.exit(1);
