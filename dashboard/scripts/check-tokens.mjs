#!/usr/bin/env node
/**
 * MindScope · 设计令牌守卫（P0→P1 · 棘轮）
 * ================================================================
 * 唯一真源：src/styles/tokens.css（值回指鸿蒙 UiTheme.ets）。
 * 本脚本零依赖，只读 src/ 下的源码，不修改任何文件。
 *
 * 用法：
 *   node scripts/check-tokens.mjs            # 等价 --report：打印计数与违规清单，永不失败
 *   node scripts/check-tokens.mjs --report   # 同上（P0 用这个）
 *   node scripts/check-tokens.mjs --strict   # 有违规即 exit 1（P1 起接 CI / pre-commit）
 *
 * 检查项：
 *   [A] 未定义 CSS 变量：src/**\/*.{vue,ts,css} 里所有 var(--x)，
 *       在 tokens.css / style.css 或 .vue/.ts 的内联 `'--x':` 定义里找不到 → 违规。
 *   [B] 裸色值：.vue / .ts 中 #rrggbb 的出现次数（P2 实测基线 84）。
 *   [C] 裸字面量：.vue 中不经 var(--radius*) / var(--font*) 的
 *       border-radius / font-size 出现次数与取值集合。
 *   [D] 渐变：全 src 的 linear-gradient / radial-gradient 出现位置
 *       （§2.8 白名单只允许 tokens.css 里的 2 条）。
 *   [E] 一致性：tokens.ts 与 tokens.css 逐条数值比对（防两份真源漂移）。
 *
 * [A] 必须为 0：这是 P0 的核心风险项（变量名在 CSS/TS 之间拼错不会报错，只会静默失效）。
 * [B]/[C]/[D] 的基线随阶段下调，P1 起逐个收敛到 0。
 *
 * ── P1 白名单（写死在这里，任何新增都会让本脚本的计数上升 → --strict 失败）──
 *   font-size：
 *     · 图表轴 11px 只允许出现在 ECharts 配置的 JS `fontSize: 11`（canvas 不读 CSS 变量），
 *       它不走 CSS `font-size:` 属性，因此不计入 [C]；CSS 侧图表轴一律 var(--font-axis) 或 var(--font-xs)。
 *     · CSS 里唯一允许保留的裸声明是 `font-size: inherit`（ScoreCounter.vue，继承父级数值字号）。
 *   border-radius：
 *     · `50%` 的圆形（状态点、占位图标）无令牌可替，保留 2 处；
 *     · `4px` 只允许出现在滚动条/微型条（本阶段实测 2 处），进度条圆角由 ProgressBar 内联 height/2 给出，
 *       不写进 CSS。
 */

import { readdirSync, readFileSync, existsSync } from 'node:fs'
import { join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

// ── 路径 ──────────────────────────────────────────────────────────
const ROOT = fileURLToPath(new URL('..', import.meta.url)) // dashboard/
const SRC = join(ROOT, 'src')
const TOKENS_CSS = join(SRC, 'styles', 'tokens.css')
const TOKENS_TS = join(SRC, 'styles', 'tokens.ts')
const STYLE_CSS = join(SRC, 'style.css')

// ── 基线（棘轮：只能降不能升） ────────────────────────────────────
// P0 基线 118 / 24 / 108 / 11 / 3；P1 完成去渐变、字号/圆角收敛、严重度换色后实测降到 93；
// P2「删伪图表」又实测降到 84：
//   hex 84      —— usePdfExport.ts(68，PDF 模板内联样式，§P5 处理)
//                  + stores/dashboard.ts(8，严重度/图表数据色)
//                  + chartTheme.ts(4) + MediaLibrary.vue(3) + SeverityPieChart.vue(1)
//                  （CloudTopology.vue 原有 9 处已随 force graph 一起删除）
//   radius 4    —— 50%×2（圆形）+ 4px×2（滚动条微型条）
//   fontSize 1  —— 仅 ScoreCounter.vue 的 `font-size: inherit`
//   linear 0 / radial 0 —— §2.8 白名单的 2 条渐变只存在于 tokens.css（[D] 只统计 .vue/.ts/style.css 引用处）
// 以后任何一项超过下列数值，--strict 直接 exit 1。
const BASELINE = {
  hex: 84,
  radius: 4,
  fontSize: 1,
  linear: 0,
  radial: 0,
}

const args = process.argv.slice(2)
const STRICT = args.includes('--strict')
const REPORT = args.includes('--report') || !STRICT

const rel = (p) => relative(ROOT, p).split(sep).join('/')
const read = (p) => readFileSync(p, 'utf8')

// ── 收集源文件 ────────────────────────────────────────────────────
function walk(dir, acc = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name)
    if (e.isDirectory()) walk(p, acc)
    else if (/\.(vue|ts|css)$/.test(e.name)) acc.push(p)
  }
  return acc
}

if (!existsSync(SRC)) {
  console.error(`✗ 找不到源码目录：${SRC}`)
  process.exit(1)
}

const files = walk(SRC).sort()
const byExt = (exts) => files.filter((f) => exts.some((x) => f.endsWith(x)))

const vueFiles = byExt(['.vue'])
const vtsFiles = byExt(['.vue', '.ts']) // [B] 范围

// ── 工具 ──────────────────────────────────────────────────────────
function lineAt(text, index) {
  let n = 1
  for (let i = 0; i < index; i++) if (text.charCodeAt(i) === 10) n++
  return n
}

function collect(regex, text) {
  const out = []
  if (!regex.global) throw new Error('collect() 需要 global 正则')
  regex.lastIndex = 0
  let m
  while ((m = regex.exec(text)) !== null) {
    out.push({ m, index: m.index })
    if (m[0].length === 0) regex.lastIndex++
  }
  return out
}

// ── [A] 未定义变量 ────────────────────────────────────────────────
// 定义来源：① CSS 文件里的 `--x:` 声明；② .vue/.ts 内联（`:style` 对象 / <style> 块）
const DEF_RE_CSS = /--([A-Za-z0-9_-]+)\s*:/g
const DEF_RE_INLINE = /['"`]?--([A-Za-z0-9_-]+)['"`]?\s*:/g
const USE_RE = /var\(\s*(--[A-Za-z0-9_-]+)/g

const defined = new Map() // name -> "file:line"
function defineFrom(file, text, regex) {
  for (const { m, index } of collect(regex, text)) {
    const name = `--${m[1]}`
    if (!defined.has(name)) defined.set(name, `${rel(file)}:${lineAt(text, index)}`)
  }
}
for (const f of byExt(['.css'])) defineFrom(f, read(f), DEF_RE_CSS)
for (const f of vtsFiles) defineFrom(f, read(f), DEF_RE_INLINE)

const undefinedUses = []
const allUses = new Map() // name -> count
for (const f of files) {
  const text = read(f)
  for (const { m, index } of collect(USE_RE, text)) {
    const name = m[1]
    allUses.set(name, (allUses.get(name) ?? 0) + 1)
    if (!defined.has(name)) {
      const line = lineAt(text, index)
      const hasFallback = new RegExp(`var\\(\\s*${name.replace(/[-]/g, '\\-')}\\s*,`).test(
        text.slice(index, index + 240),
      )
      undefinedUses.push({ file: rel(f), line, name, hasFallback })
    }
  }
}

// ── [B] 裸色值 ────────────────────────────────────────────────────
const HEX_RE = /#[0-9a-fA-F]{6}/g
let hexTotal = 0
const hexByFile = []
for (const f of vtsFiles) {
  if (f === TOKENS_TS) continue // 令牌镜像本身持有色值，不计入基线
  const n = (read(f).match(HEX_RE) ?? []).length
  if (n) {
    hexByFile.push({ file: rel(f), n })
    hexTotal += n
  }
}
hexByFile.sort((a, b) => b.n - a.n)

// ── [C] 裸 border-radius / font-size（仅 .vue） ──────────────────
function literalDecls(prop, tokenPrefix) {
  const re = new RegExp(`${prop}\\s*:\\s*([^;}]+)`, 'g')
  const hits = []
  let total = 0
  for (const f of vueFiles) {
    const text = read(f)
    for (const { m, index } of collect(re, text)) {
      const value = m[1].trim().replace(/\s+/g, ' ')
      if (value.includes(`var(${tokenPrefix}`)) continue
      total++
      hits.push({ file: rel(f), line: lineAt(text, index), value })
    }
  }
  const values = new Map()
  for (const h of hits) values.set(h.value, (values.get(h.value) ?? 0) + 1)
  return { total, hits, values }
}
const radiusDecls = literalDecls('border-radius', '--radius')
const fontSizeDecls = literalDecls('font-size', '--font')

// ── [D] 渐变 ──────────────────────────────────────────────────────
const GRAD_RE = /(linear|radial)-gradient\(/g
const grads = []
for (const f of files) {
  if (f === TOKENS_CSS || f === TOKENS_TS) continue // 白名单与镜像不算违规
  const text = read(f)
  for (const { m, index } of collect(GRAD_RE, text)) {
    grads.push({ file: rel(f), line: lineAt(text, index), kind: m[1] })
  }
}
const linearTotal = grads.filter((g) => g.kind === 'linear').length
const radialTotal = grads.filter((g) => g.kind === 'radial').length
const whitelist = (() => {
  const text = read(TOKENS_CSS).replace(/\/\*[\s\S]*?\*\//g, '')
  return (text.match(/--gradient-[a-z0-9-]+\s*:/g) ?? []).length
})()

// ── [E] tokens.ts ↔ tokens.css ────────────────────────────────────
function parseCssTokens() {
  const text = read(TOKENS_CSS).replace(/\/\*[\s\S]*?\*\//g, '')
  const map = new Map()
  for (const { m } of collect(/--([A-Za-z0-9_-]+)\s*:\s*([^;]+);/g, text)) {
    if (!map.has(m[1])) map.set(m[1], m[2].trim()) // 首次定义优先（媒体查询里的覆盖值忽略）
  }
  return map
}

function parseTsTokens() {
  const text = read(TOKENS_TS)
  const start = text.indexOf('export const tokens = {')
  if (start < 0) throw new Error('tokens.ts 里找不到 `export const tokens = {`')
  const body = text.slice(start + 'export const tokens = {'.length)
  const end = body.indexOf('} as const')
  const inner = end < 0 ? body : body.slice(0, end)
  const map = new Map()
  for (const { m } of collect(/^\s*'?([A-Za-z0-9-]+)'?\s*:\s*(.+?),\s*$/gm, inner)) {
    map.set(m[1], m[2].trim())
  }
  return map
}

function normalize(value) {
  let s = value.trim().replace(/\s+/g, ' ')
  const quoted = /^(['"`])([\s\S]*)\1$/.exec(s)
  if (quoted) s = quoted[2].trim()
  if (/-?\d*\.?\d+/.test(s) && /^-?\d*\.?\d+$/.test(s)) return String(parseFloat(s))
  const dim = /^(-?\d*\.?\d+)(px|ms|s|%)$/.exec(s)
  if (dim) {
    const n = parseFloat(dim[1])
    return String(dim[2] === 's' ? n * 1000 : n)
  }
  s = s.replace(/#[0-9a-fA-F]{3,8}/g, (h) => h.toLowerCase())
  s = s.replace(/\b(rgba?|hsla?)\(([^)]*)\)/gi, (_, fn, body) =>
    `${fn.toLowerCase()}(${body.split(',').map((x) => x.trim()).join(', ')})`,
  )
  return s
}

const cssTokens = parseCssTokens()
const tsTokens = parseTsTokens()
const parity = { checked: 0, issues: [] }
for (const [name, cssValue] of cssTokens) {
  if (!tsTokens.has(name)) {
    parity.issues.push(`tokens.ts 缺少 '${name}'（tokens.css 有 ${cssValue}）`)
    continue
  }
  parity.checked++
  const a = normalize(cssValue)
  const b = normalize(tsTokens.get(name))
  if (a !== b) parity.issues.push(`'${name}' 值不一致：css=${cssValue} / ts=${tsTokens.get(name)}`)
}
for (const name of tsTokens.keys()) {
  if (!cssTokens.has(name)) parity.issues.push(`tokens.ts 多出 '${name}'（tokens.css 无此定义）`)
}

// ── 输出 ──────────────────────────────────────────────────────────
const pad = (s, n) => String(s).padEnd(n, ' ')
const num = (n, w = 4) => String(n).padStart(w)
const flag = (ok) => (ok ? '✅' : '✗')

const lines = []
lines.push('')
lines.push('MindScope · 设计令牌守卫（P0→P1 · 棘轮）  真源 src/styles/tokens.css')
lines.push(`扫描 ${files.length} 个文件：src/**/*.{vue,ts,css}${STRICT ? '   [strict]' : '   [report]'}`)
lines.push('─'.repeat(72))

const aOk = undefinedUses.length === 0
lines.push(`${flag(aOk)} [A] 未定义 CSS 变量      ${num(undefinedUses.length)} 处   （要求 0）`)

const bOk = hexTotal <= BASELINE.hex
lines.push(`${flag(bOk)} [B] 裸色值 #rrggbb        ${num(hexTotal)} 处   （基线 ${BASELINE.hex}）`)

const cRadiusOk = radiusDecls.total <= BASELINE.radius
const cFontOk = fontSizeDecls.total <= BASELINE.fontSize
lines.push(
  `${flag(cRadiusOk)} [C] 裸 border-radius      ${num(radiusDecls.total)} 处   （基线 ${BASELINE.radius}）`,
)
lines.push(
  `${flag(cFontOk)} [C] 裸 font-size          ${num(fontSizeDecls.total)} 处   （基线 ${BASELINE.fontSize}）`,
)

const dLinearOk = linearTotal <= BASELINE.linear
const dRadialOk = radialTotal <= BASELINE.radial
lines.push(
  `${flag(dLinearOk)} [D] linear-gradient       ${num(linearTotal)} 处   （基线 ${BASELINE.linear}）`,
)
lines.push(
  `${flag(dRadialOk)} [D] radial-gradient       ${num(radialTotal)} 处   （基线 ${BASELINE.radial}）`,
)
lines.push(`    §2.8 白名单（tokens.css） ${num(whitelist)} 条   （只允许 2）`)

const eOk = parity.issues.length === 0
lines.push(
  `${flag(eOk)} [E] tokens.ts ↔ tokens.css  ${pad(`${parity.checked}/${cssTokens.size}`, 9)}（逐条数值比对）`,
)
lines.push('─'.repeat(72))

// [A] 违规清单
if (undefinedUses.length) {
  lines.push('')
  lines.push(`[A] 未定义变量清单（${undefinedUses.length} 处）：`)
  for (const u of undefinedUses) {
    lines.push(`  ${u.file}:${u.line}  var(${u.name})${u.hasFallback ? '  ← 有兜底值' : ''}`)
  }
} else if (REPORT) {
  const reffed = allUses.size
  lines.push(`[A] 违规：无（共引用 ${reffed} 个不同变量 / ${[...allUses.values()].reduce((a, b) => a + b, 0)} 处 var()）`)
}

// [B] 分布（仅列出 top 文件，避免刷屏）
if (hexByFile.length) {
  const top = hexByFile.slice(0, 5).map((x) => `${x.file}(${x.n})`).join('  ')
  lines.push(`[B] 分布 top5：${top}`)
}

// [C] 取值集合
const dumpValues = (label, map) =>
  `[C] ${label}取值集合：${[...map.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([v, n]) => `${v}×${n}`)
    .join(', ')}`
if (radiusDecls.total) lines.push(dumpValues('border-radius ', radiusDecls.values))
if (fontSizeDecls.total) lines.push(dumpValues('font-size     ', fontSizeDecls.values))

// [D] 位置
if (grads.length) {
  lines.push(`[D] 位置：${grads.map((g) => `${g.file}:${g.line}(${g.kind})`).join('  ')}`)
}

// [E] 违规清单
if (parity.issues.length) {
  lines.push('')
  lines.push(`[E] 不一致清单（${parity.issues.length} 项）：`)
  for (const i of parity.issues) lines.push(`  ${i}`)
}

const failed = !aOk || !eOk || !bOk || !cRadiusOk || !cFontOk || !dLinearOk || !dRadialOk
lines.push('')
lines.push(
  failed
    ? `结果：${STRICT ? '失败（strict）' : '存在违规（report 模式不失败）'}`
    : '结果：通过（未定义变量 0 · 令牌两份一致 · 无新增裸值）',
)

console.log(lines.join('\n'))
if (STRICT && failed) process.exitCode = 1
