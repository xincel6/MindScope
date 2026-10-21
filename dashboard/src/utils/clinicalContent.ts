import type { SeverityLevel } from '@/stores/dashboard'

export interface TreatmentPlan {
  level: string
  interventions: string[]
  monitoring: string
  guidelines: string
}

export interface VlmSection {
  title: string
  content: string
}

/**
 * 按 BDI-II 严重度映射临床干预建议。
 * 从旧 DiagnosisReport.vue 抽出，供工作台 hero（临床干预建议）与 /demo 报告共用一份文案，
 * 避免两处各写一套后慢慢漂移。
 */
export function buildTreatmentPlan(severity: SeverityLevel): TreatmentPlan {
  if (severity === 'none') {
    return {
      level: '一级干预',
      interventions: [
        '保持规律作息，每周 ≥ 150 分钟中等强度运动',
        '维持社交活动频率，建议每周至少 2 次线下社交',
        '正念冥想训练，每日 10–15 分钟',
      ],
      monitoring: '建议每 3 个月使用 PHQ-9 自评量表随访',
      guidelines: 'APA 实践指南 (2019) · NICE CG90 · 中国抑郁障碍防治指南 (第二版)',
    }
  }
  if (severity === 'mild') {
    return {
      level: '二级干预',
      interventions: [
        '结构化心理治疗：认知行为治疗（CBT）或人际心理治疗（IPT），每周 1 次 × 8–12 周',
        '行为激活疗法（BA）：制定每日活动计划表，逐步恢复愉悦活动',
        '运动处方：结合有氧运动（快走/慢跑）与抗阻训练，每周 3 次',
        '互联网 CBT（iCBT）可作为辅助手段（Andersson et al., 2014）',
      ],
      monitoring: '建议每 2–4 周使用 BDI-II 或 HAM-D 评估疗效',
      guidelines: 'APA 实践指南 (2019) — 推荐等级 1A · NICE CG90 · CANMAT 2016',
    }
  }
  if (severity === 'moderate') {
    return {
      level: '三级干预',
      interventions: [
        'CBT + SSRI 类药物联合治疗（有效率 60–70%，Cuijpers et al., 2014）',
        'SSRI 一线用药：舍曲林 50–200 mg/d 或艾司西酞普兰 10–20 mg/d',
        '强化心理治疗频次至每周 2 次，持续 ≥ 12 周',
        '评估自杀风险（C-SSRS 量表），建立安全计划',
        '必要时转诊至精神专科医师进行药物调整',
      ],
      monitoring: '建议每 1–2 周随访，第 4 周评估药物应答，第 8 周评估缓解',
      guidelines: 'APA 实践指南 (2019) — 推荐等级 1A · NICE CG90 · 中国抑郁障碍防治指南 (第二版)',
    }
  }
  return {
    level: '四级干预（紧急）',
    interventions: [
      '立即转诊至精神专科医疗机构进行综合评估',
      '考虑 SNRI 或 augmented 方案（如 SSRI + 非典型抗精神病药）',
      '每周 ≥ 2 次高强度心理治疗（CBT/DBT）',
      '评估电休克治疗（ECT）或重复经颅磁刺激（rTMS）的适应证',
      '建立 24 小时紧急联系人机制，移除自杀工具',
    ],
    monitoring: '建议每周至少 1 次门诊随访，必要时考虑住院治疗',
    guidelines: 'APA 实践指南 (2019) · NICE CG90 · CANMAT 2016 — 难治性抑郁管理',
  }
}

/**
 * 把后端 VLM 的自由文本按 `【小节标题】正文` 切成结构化段落。
 * 与旧 DiagnosisReport.vue 的解析规则逐字一致。
 */
export function parseVlmSections(raw: string): VlmSection[] {
  if (!raw) return []

  const sections: VlmSection[] = []
  const re = /【(.+?)】\s*/g
  let lastEnd = 0
  let match: RegExpExecArray | null

  while ((match = re.exec(raw)) !== null) {
    if (lastEnd > 0) {
      const prev = sections[sections.length - 1]
      if (prev) {
        prev.content = raw.slice(lastEnd, match.index).trim()
      }
    }
    sections.push({ title: match[1], content: '' })
    lastEnd = match.index + match[0].length
  }

  if (lastEnd > 0 && sections.length > 0) {
    const last = sections[sections.length - 1]
    last.content = raw.slice(lastEnd).trim()
  }

  return sections
}
