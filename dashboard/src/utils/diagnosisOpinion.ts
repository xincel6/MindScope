import type { SeverityLevel } from '@/stores/dashboard'

/**
 * 「诊断意见」区域的纯函数工具：
 * - 从当前分析结果推导判断依据
 * - 生成可编辑的 AI 意见草稿
 * - 输出严重度刻度
 *
 * 该模块不依赖 Pinia，便于单独测试与复用。
 */

export const OPINION_MAX_LEN = 600
export const OPINION_MIN_LEN = 10

export interface SeverityScaleItem {
  level: SeverityLevel
  label: string
  range: string
}

export const severityScale: SeverityScaleItem[] = [
  { level: 'none', label: '正常', range: '0–13' },
  { level: 'mild', label: '轻度', range: '14–19' },
  { level: 'moderate', label: '中度', range: '20–28' },
  { level: 'severe', label: '重度', range: '29–63' },
]

export type EvidenceKey = 'face' | 'temporal' | 'subscale' | 'subject'

export interface OpinionEvidence {
  key: EvidenceKey
  index: string
  label: string
  value: string
  hint: string
  available: boolean
}

export interface OpinionSubScales {
  /** 永远是 false：模型没有量表分项输出，这个接口只用来向 UI 说明「为什么没有」 */
  available: false
  /** 展示用主文案 */
  label: string
  /** 展示用补充说明 */
  detail: string
}

/**
 * 量表分项 —— 模型没有这个输出。
 *
 * 旧实现按 BDI-II 文献因子负荷把总分按固定比例拆成三维，
 * 那是「用结构方程系数倒推一个不存在的输出」：数字看起来精确，但它不对应任何一次推理，
 * 和临床量表施测也没有关系。`dashboard/backend/**.py`（排除 venv）与 `harmony/**.ets`
 * 全仓 0 处 subscale，说明后端从未产出分项 → 这里只返回「不可用」，不再造数。
 */
export function buildSubScales(): OpinionSubScales {
  return {
    available: false,
    label: '本模型未输出量表分项',
    detail: 'LMTformer 只回归 BDI-II 总分；认知-情感 / 躯体症状 / 行为表现三个维度需要正式量表施测。',
  }
}

export interface Hotspot {
  region: string
  value: number
}

/** 与 FacePreview 相同的分区规则，取注意力最高的热区 */
export function topHotspot(heatmap: number[][]): Hotspot | null {
  if (!heatmap.length) return null
  const h = heatmap.length
  const w = heatmap[0]?.length ?? 0
  if (!w) return null
  let best = { x: 0, y: 0, v: -Infinity }
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const v = heatmap[y][x]
      if (v > best.v) best = { x, y, v }
    }
  }
  if (!Number.isFinite(best.v)) return null
  const regionX = best.x / w
  const regionY = best.y / h
  let region = '面部中央区域'
  if (regionY < 0.3 && regionX > 0.3 && regionX < 0.7) region = '眉间/前额区域'
  else if (regionY > 0.25 && regionY < 0.45 && (regionX < 0.35 || regionX > 0.65)) region = '眶周区域'
  else if (regionY > 0.5 && regionX > 0.3 && regionX < 0.7) region = '口周区域'
  else if (regionY > 0.4 && regionY < 0.55 && regionX > 0.35 && regionX < 0.65) region = '鼻唇沟区域'
  return { region, value: best.v * 100 }
}

export interface EvidenceInput {
  heatmap: number[][]
  history: number[]
  score: number
  hasPatient: boolean
}

export function buildEvidence(input: EvidenceInput): OpinionEvidence[] {
  const hotspot = topHotspot(input.heatmap)
  const range = input.history.length
    ? Math.max(...input.history) - Math.min(...input.history)
    : 0
  const scales = buildSubScales()

  return [
    {
      key: 'face',
      index: '01',
      label: '面部注意力',
      value: hotspot ? `${hotspot.region} ${hotspot.value.toFixed(1)}%` : '暂无热力图数据',
      hint: 'MSSTformer 注意力热区',
      available: !!hotspot,
    },
    {
      key: 'temporal',
      index: '02',
      label: '情绪时序',
      value:
        input.history.length > 1
          ? `${input.history.length} 帧 · 极差 ${range} 分`
          : input.history.length === 1
            ? '单帧推理 · 无时序波动'
            : '暂无逐帧数据',
      hint: 'BDI-II 逐帧评分序列',
      available: input.history.length > 1,
    },
    {
      key: 'subscale',
      index: '03',
      label: '量表维度',
      value: scales.label,
      hint: '模型只回归 BDI-II 总分',
      available: scales.available,
    },
    {
      key: 'subject',
      index: '04',
      label: '受试者信息',
      value: input.hasPatient ? '已录入并核对' : '尚未录入',
      hint: '性别 / 年龄段 / 评估日',
      available: input.hasPatient,
    },
  ]
}

export interface DraftInput {
  score: number
  severityLabel: string
  severity: SeverityLevel
  suggestion: string
  heatmap: number[][]
  history: number[]
  vlmAnalysis: string
  patientId?: string
}

const followUp: Record<SeverityLevel, string> = {
  none: '建议 3 个月后复评',
  mild: '建议 2–4 周后复评',
  moderate: '建议 1–2 周内复评',
  severe: '建议 24–48 小时内复评',
}

function temporalSentence(history: number[]): string {
  if (history.length <= 1) return '仅有单帧推理结果，暂无法评估时序波动'
  const range = Math.max(...history) - Math.min(...history)
  if (range <= 3) return `逐帧评分平稳（极差 ${range} 分）`
  if (range <= 8) return `逐帧评分轻度波动（极差 ${range} 分）`
  return `逐帧评分波动明显（极差 ${range} 分）`
}

function vlmSentence(raw: string): string {
  const text = raw.replace(/【[^】]*】/g, ' ').replace(/\s+/g, ' ').trim()
  if (!text) return ''
  const summary = text.slice(0, 46)
  return `多模态描述提示：${summary}${text.length > 46 ? '…' : ''}。`
}

/**
 * 生成 AI 意见草稿。刻意保持三段式：
 * 评估结果 → 客观依据 → 处置建议，方便医师逐段改写。
 */
export function buildAiDraft(input: DraftInput): string {
  const spot = topHotspot(input.heatmap)
  const subject = input.patientId ? `受试者 ${input.patientId} ` : '本次评估'
  const face = spot
    ? `面部分析显示注意力主要集中于${spot.region}（${spot.value.toFixed(1)}%）`
    : '面部热力图数据尚不完整'
  const suggestion = input.suggestion.replace(/。$/, '')

  return [
    `${subject}经 MSSTformer 多模态评估，BDI-II 总分为 ${input.score} 分，处于${input.severityLabel}区间。`,
    `${face}；${temporalSentence(input.history)}。${vlmSentence(input.vlmAnalysis)}`,
    `综合量表与面部分析结果，${suggestion}；${followUp[input.severity]}，并结合临床访谈进一步核实。`,
  ].join('\n')
}

/** 已确认意见与分析结果是否仍匹配 */
export function isSameSnapshot(
  a: { score: number; severity: SeverityLevel; mediaId: string; patientId: string },
  b: { score: number; severity: SeverityLevel; mediaId: string; patientId: string },
): boolean {
  return (
    a.score === b.score &&
    a.severity === b.severity &&
    a.mediaId === b.mediaId &&
    a.patientId === b.patientId
  )
}
