/**
 * test-heatmap-strip.mjs · 横向逐帧列表**取数逻辑**离线测试
 *
 * ────────────────── 为什么需要它 ──────────────────
 * `HeatmapViewModel.ets` 里的 `buildHeatmapView()` 决定了"主图画哪一帧"，而它要处理四种
 * 数据情形（手动固定 / 实时 / 历史快照 / 演示数据）与三种边界（空列表 / 越界下标 / 空矩阵）。
 * 这些分支如果只靠真机点击去试，覆盖不全而且每次都要重装 HAP。
 *
 * 所以这里用**逻辑镜像**的方式把同一套判定搬到 Node 里跑：
 *   · 下面 `buildView()` 是 `HeatmapViewModel.ets` 的逐行对照实现（同样的优先级顺序）；
 *   · 用例覆盖"用户手感"的关键点：**没手动选过时必须取最后一帧**（列表右端 = 最新）。
 *   · 另有一条**源码文本级检查**：确认真正生效的 `.ets` 里仍有相同的判定顺序与常量，
 *     避免"测试里的镜像改了、产品代码没改"这种假绿。
 *
 * 用法：node harmony/scripts/test-heatmap-strip.mjs
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const VM_PATH = join(HERE, '..', 'entry', 'src', 'main', 'ets', 'components', 'charts', 'HeatmapViewModel.ets');

// ───────────────── 与 HeatmapViewModel.ets 同口径的镜像实现 ─────────────────

const SOURCE = { pinned: 0, live: 1, snapshot: 2, sample: 3 };

function hasHeat(f) {
  return f.heatmapData.length > 0 && f.heatmapData[0].length > 0;
}

function heatOnly(frames, maxTiles) {
  const out = frames.filter(hasHeat);
  return out.length > maxTiles ? out.slice(out.length - maxTiles) : out;
}

function pickIndex(frames, focusedIndex, lastIndex) {
  if (frames.length === 0) return -1;
  if (focusedIndex >= 0 && focusedIndex < frames.length) return focusedIndex;
  return lastIndex;
}

function buildView(liveFrames, sampleFrames, followLiveTask, focusedIndex, lastFrame, maxTiles = 24) {
  if (followLiveTask && liveFrames.length > 0) {
    const frames = heatOnly(liveFrames, maxTiles);
    const last = frames.length - 1;
    const index = pickIndex(frames, focusedIndex, last);
    return {
      frames,
      heatmap: index >= 0 ? frames[index].heatmapData : [],
      index,
      focusedIndex,
      source: focusedIndex >= 0 && index === focusedIndex ? SOURCE.pinned : SOURCE.live
    };
  }
  if (lastFrame !== null && hasHeat(lastFrame)) {
    return {
      frames: [lastFrame],
      heatmap: lastFrame.heatmapData,
      index: 0,
      focusedIndex: -1,
      source: SOURCE.snapshot
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

console.log('1) 实时模式：没有手动选过时必须取【最后一格】（列表右端 = 最新）');
{
  const live = [frame(1, 0.1), frame(2, 0.5), frame(3, 0.9)];
  const v = buildView(live, [], true, -1, null);
  check('index = 最后一格', v.index === 2, `实际 ${v.index}`);
  check('主图取到第 3 帧的矩阵', v.heatmap[0][0] === 0.9, `实际 ${JSON.stringify(v.heatmap)}`);
  check('source = live', v.source === SOURCE.live, `实际 ${v.source}`);
}

console.log('\n2) 手动固定第 1 格：主图必须是那一帧，且 source = pinned');
{
  const live = [frame(1, 0.1), frame(2, 0.5), frame(3, 0.9)];
  const v = buildView(live, [], true, 0, null);
  check('index = 0', v.index === 0, `实际 ${v.index}`);
  check('主图取到第 1 帧的矩阵（不是最新帧）', v.heatmap[0][0] === 0.1, `实际 ${JSON.stringify(v.heatmap)}`);
  check('source = pinned', v.source === SOURCE.pinned, `实际 ${v.source}`);
}

console.log('\n3) 越界下标（新一轮分析把列表换了）→ 退回最后一格，而不是第 0 格');
{
  const live = [frame(1, 0.1), frame(2, 0.5)];
  const v = buildView(live, [], true, 7, null);
  check('index = 1（最后一格）', v.index === 1, `实际 ${v.index}`);
}

console.log('\n4) 空热度矩阵的帧必须被过滤掉（否则缩略图是灰块）');
{
  const live = [frame(1, 0.2), frame(2, 0, false), frame(3, 0.8)];
  const v = buildView(live, [], true, -1, null);
  check('frames 只剩 2 帧', v.frames.length === 2, `实际 ${v.frames.length}`);
  check('主图 = 有数据的最新帧', v.heatmap[0][0] === 0.8, `实际 ${JSON.stringify(v.heatmap)}`);
}

console.log('\n5) 渲染上限：超出时保留【最新】的 N 帧（不能保留最旧的）');
{
  const live = [];
  for (let i = 1; i <= 40; i++) live.push(frame(i, i / 100));
  const v = buildView(live, [], true, -1, null, 24);
  check('frames 被裁到 24 帧', v.frames.length === 24, `实际 ${v.frames.length}`);
  check('保留的是第 17~40 帧', v.frames[0].frameId === 17 && v.frames[23].frameId === 40,
    `首 ${v.frames[0].frameId} 末 ${v.frames[23].frameId}`);
  check('主图仍是最新帧', v.heatmap[0][0] === 0.4, `实际 ${JSON.stringify(v.heatmap)}`);
}

console.log('\n6) 历史快照：没有逐帧数据，但有"最近一帧" → 单帧快照态');
{
  const v = buildView([], [], false, -1, frame(9, 0.77));
  check('frames = 1', v.frames.length === 1, `实际 ${v.frames.length}`);
  check('主图 = 那一帧', v.heatmap[0][0] === 0.77, `实际 ${JSON.stringify(v.heatmap)}`);
  check('source = snapshot', v.source === SOURCE.snapshot, `实际 ${v.source}`);
}

console.log('\n7) 实时模式但一帧都没收到 → 走演示数据，且**必须**带上 sample 标记');
{
  // ★ 这里记录一个真实行为（初版测试写错了预期，实测代码是对的）：
  //   实时任务刚起步、`lastFrame` 还没到、`frameHistory` 为空时，
  //   代码**不会**走 snapshot 分支，而是落到演示数据分支。
  //   这是刻意的：此刻屏幕上没有任何真实热度可画，用演示帧把渲染链路铺开
  //   （界面同时打出"演示数据"蓝色标记）比一片空白更有信息量；
  //   一旦第一帧到达，`followLiveTask && liveFrames.length > 0` 立刻接管，演示帧自动让位。
  const demo = [frame(1, 0.3)];
  const v = buildView([], demo, true, -1, null);
  check('source = sample（并会显示"演示数据"标记）', v.source === SOURCE.sample, `实际 ${v.source}`);
  check('演示帧可画', v.heatmap[0][0] === 0.3, `实际 ${JSON.stringify(v.heatmap)}`);

  // 第一帧到达后必须立刻切换到实时分支
  const v2 = buildView([frame(5, 0.55)], demo, true, -1, null);
  check('第一帧到达后 source = live', v2.source === SOURCE.live, `实际 ${v2.source}`);
  check('主图切到真实帧', v2.heatmap[0][0] === 0.55, `实际 ${JSON.stringify(v2.heatmap)}`);
}

console.log('\n8) 彻底没有真实数据 → 演示数据，且 source = sample（界面会打"演示数据"标记）');
{
  const demo = [frame(1, 0.3), frame(2, 0.6)];
  const v = buildView([], demo, true, -1, null);
  check('frames = 演示帧', v.frames.length === 2, `实际 ${v.frames.length}`);
  check('source = sample', v.source === SOURCE.sample, `实际 ${v.source}`);
  check('主图 = 演示数据最后一帧', v.heatmap[0][0] === 0.6, `实际 ${JSON.stringify(v.heatmap)}`);
}

console.log('\n9) 全空：不该崩，且 index = -1、heatmap 为空数组（方块组件走占位态）');
{
  const v = buildView([], [], true, -1, null);
  check('index = -1', v.index === -1, `实际 ${v.index}`);
  check('heatmap 为空数组', v.heatmap.length === 0, `实际 ${JSON.stringify(v.heatmap)}`);
  check('source = sample', v.source === SOURCE.sample, `实际 ${v.source}`);
}

console.log('\n10) 源码文本级检查（防止镜像与产品代码脱钩）');
const src = readFileSync(VM_PATH, 'utf8');
const required = [
  ['渲染上限常量 24', /MAX_STRIP_TILES: number = 24/],
  ['只保留有热度数据的帧', /function heatOnly/],
  ['超出上限时保留最新（slice 尾部）', /out\.slice\(out\.length - MAX_STRIP_TILES\)/],
  ['实时分支优先', /if \(followLiveTask && liveFrames\.length > 0\)/],
  ['快照兜底分支', /if \(lastFrame !== null && hasHeat\(lastFrame\)\)/],
  ['演示数据分支', /const demo: AnalysisFrameModel\[\] = heatOnly\(sampleFrames\)/],
  ['pinned 判定', /focusedIndex >= 0 && index === focusedIndex/],
  ['越界退回最后一格', /return lastIndex;/]
];
for (const [name, re] of required) {
  check(`HeatmapViewModel.ets 含「${name}」`, re.test(src), `未匹配 ${re}`);
}

console.log('');
if (failures === 0) {
  console.log('PASS 全部通过：横向逐帧列表取数逻辑符合预期。');
  process.exit(0);
}
console.log(`FAIL 存在 ${failures} 处失败。`);
process.exit(1);
