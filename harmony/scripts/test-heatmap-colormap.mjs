/**
 * test-heatmap-consistency.mjs · 注意力热力图**色彩口径一致性**离线测试
 *
 * ────────────────── 为什么需要这个测试 ──────────────────
 * 本项目的硬要求是：鸿蒙端 `HeatmapUtil.heatColor/heatRgb` 必须与 Web 端
 * `dashboard/src/components/center-panel/FacePreview.vue` 的 `heatColor()` **逐位等价**，
 * 否则"同一帧数据两端颜色对不上"，热力图验收就失去意义。
 *
 * 而 ArkTS 代码本身无法在本机命令行直接跑（要靠 DevEco 工具链），
 * 所以这里用**双份实现**做对照：
 *   · `webHeatColor` —— 逐字复制 Web 端 `FacePreview.vue` 的 heatColor 实现；
 *   · `arkHeatRgb`   —— 逐字搬运 `HeatmapTile.ets` 里 `HeatmapUtil.heatRgb` 的实现
 *                       （含同样的分段与 clamp），再由 heatColor 拼出 rgba 串。
 * 两份实现各自独立，谁都不调用谁，比较的是**最终输出**。
 *
 * ★ 另有一条"文本级"检查：直接读 `.ets` 源码，确认分段边界常量
 *   （0.25 / 0.5 / 0.75、各段乘数 4、alpha 0.8）在源码里真实存在，
 *   防止"源码被改过、而本测试里的搬运件没跟着改"这种假绿。
 *
 * 用法：
 *   node harmony/scripts/test-heatmap-consistency.mjs
 * 退出码：0 = 全部一致；1 = 存在不一致（会打印差异明细）
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
// ★ 算法实现只有一份，在 `HeatmapTile.ets`（`AttentionHeatmap.ets` 只重新导出）
const ETS_PATH = join(HERE, '..', 'entry', 'src', 'main', 'ets', 'components', 'charts', 'HeatmapTile.ets');
const WEB_PATH = join(HERE, '..', '..', 'dashboard', 'src', 'components', 'center-panel', 'FacePreview.vue');

// ───────────────────────── Web 端实现（逐字复制 FacePreview.vue:108-113）─────────────────────────

function webHeatColor(t) {
  const r = Math.min(Math.max(t < 0.25 ? 0 : t < 0.5 ? (t - 0.25) * 4 : 1, 0), 1);
  const g = Math.min(Math.max(t < 0.25 ? t * 4 : t < 0.75 ? 1 : (1 - t) * 4, 0), 1);
  const b = Math.min(Math.max(t < 0.5 ? (0.5 - t) * 4 : 0, 0), 1);
  return `rgba(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)},0.8)`;
}

// ───────────────────────── 鸿蒙端实现（逐字搬运 HeatmapUtil.heatRgb）─────────────────────────

function arkHeatRgb(t) {
  const v = t < 0 ? 0 : (t > 1 ? 1 : t);

  let r;
  if (v < 0.25) {
    r = 0;
  } else if (v < 0.5) {
    r = (v - 0.25) * 4;
  } else {
    r = 1;
  }

  let g;
  if (v < 0.25) {
    g = v * 4;
  } else if (v < 0.75) {
    g = 1;
  } else {
    g = (1 - v) * 4;
  }

  let b;
  if (v < 0.5) {
    b = (0.5 - v) * 4;
  } else {
    b = 0;
  }

  const rr = Math.round(Math.min(Math.max(r, 0), 1) * 255);
  const gg = Math.round(Math.min(Math.max(g, 0), 1) * 255);
  const bb = Math.round(Math.min(Math.max(b, 0), 1) * 255);
  return [rr, gg, bb];
}

function arkHeatColor(t) {
  const rgb = arkHeatRgb(t);
  return `rgba(${rgb[0]},${rgb[1]},${rgb[2]},0.8)`;
}

// ───────────────────────── 断言 ─────────────────────────

let failures = 0;

function check(name, ok, detail) {
  if (ok) {
    console.log(`  [OK]   ${name}`);
  } else {
    failures += 1;
    console.log(`  [FAIL] ${name}\n         ${detail}`);
  }
}

console.log('1) 采样点逐位比对（Web heatColor vs ArkTS heatRgb）');

const samples = [];
// 关键停靠点 + 每段内的密集采样（含段边界前后一个极小量）
for (const edge of [0, 0.25, 0.5, 0.75, 1]) {
  samples.push(edge, edge - 1e-9, edge + 1e-9, edge - 0.001, edge + 0.001);
}
for (let i = 0; i <= 1000; i++) {
  samples.push(i / 1000);
}
// 越界值（服务端理论上只给 [0,1]，但两侧都要能 clamp 住）
samples.push(-1, -0.5, 1.5, 2);

let compared = 0;
let mismatches = 0;
for (const t of samples) {
  const web = webHeatColor(t);
  const ark = arkHeatColor(t);
  compared += 1;
  if (web !== ark) {
    mismatches += 1;
    if (mismatches <= 5) {
      console.log(`  [FAIL] t=${t}\n         web=${web}\n         ark=${ark}`);
    }
  }
}
check(`${compared} 个采样点全部一致`, mismatches === 0, `共有 ${mismatches} 处不一致`);
failures += mismatches;

console.log('\n2) 五段停靠点色值（肉眼比对照表）');
const stops = [0, 0.25, 0.5, 0.75, 1.0];
const expectedStops = [
  'rgba(0,0,255,0.8)',
  'rgba(0,255,255,0.8)',
  'rgba(255,255,0,0.8)',
  'rgba(255,255,0,0.8)',
  'rgba(255,0,0,0.8)'
];
for (let i = 0; i < stops.length; i++) {
  const ark = arkHeatColor(stops[i]);
  console.log(`  t=${stops[i]}  ->  ${ark}`);
  check(`t=${stops[i]} 等于预期色值`, ark === expectedStops[i], `预期 ${expectedStops[i]}，实际 ${ark}`);
}

console.log('\n3) 源码文本级检查（防止测试里的搬运件与真实源码脱钩）');
const ets = readFileSync(ETS_PATH, 'utf8');
const required = [
  ['分段边界 0.25', /v < 0\.25/],
  ['分段边界 0.5', /v < 0\.5/],
  ['分段边界 0.75', /v < 0\.75/],
  ['过渡段乘数 4', /\) \* 4/],
  ['红色通道上限 1', /r = 1;/],
  ['绿色通道上限 1', /g = 1;/],
  ['蓝色通道下限 0', /b = 0;/],
  ['alpha 0.8', /,0\.8\)`/],
  ['归一化 255', /\* 255/],
  ['clamp 到 [0,1]', /Math\.min\(Math\.max\(/],
  ['叠加不透明度 0.32', /HEAT_OVERLAY_ALPHA: number = 0\.32/],
  ['解剖区域坐标基准 128', /CANON_FACE_SIZE: number = 128/]
];
for (const [name, re] of required) {
  check(`HeatmapTile.ets 含「${name}」`, re.test(ets), `未匹配 ${re}`);
}

console.log('\n4) Web 端源码仍在原位（对照基准没被搬走/改名）');
const web = readFileSync(WEB_PATH, 'utf8');
check('FacePreview.vue 含 heatColor', /function heatColor\(t: number\)/.test(web), '未找到 heatColor 定义');
check(
  'FacePreview.vue 渐变停靠点 = 蓝青绿黄红',
  /linear-gradient\(to right, #0000ff, #00ffff, #00ff00, #ffff00, #ff0000\)/.test(web),
  '未找到预期渐变'
);

console.log('');
if (failures === 0) {
  console.log('PASS 全部通过：鸿蒙端色彩口径与 Web 端逐位一致。');
  process.exit(0);
}
console.log(`FAIL 存在 ${failures} 处不一致，请修复后再验收。`);
process.exit(1);
