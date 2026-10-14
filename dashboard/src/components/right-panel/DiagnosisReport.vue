<script setup lang="ts">
import { ref, computed } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'
import { usePdfExport } from '@/composables/usePdfExport'
import ScoreCounter from '@/components/common/ScoreCounter.vue'
import GlowProgress from '@/components/common/GlowProgress.vue'
import dayjs from 'dayjs'
import { ElMessage } from 'element-plus'

const store = useDashboardStore()
const reportRef = ref<HTMLElement | null>(null)
const { exporting, exportReport } = usePdfExport()
const activeSections = ref(['subscale', 'treatment'])

async function handleExport() {
  const chartEl = document.querySelector('.emotion-curve') as HTMLElement | null

  await exportReport(
    {
      date: dayjs().format('YYYY-MM-DD HH:mm:ss'),
      mediaName: store.selectedMedia?.name ?? '未知素材',
      bdiScore: store.currentScore,
      severityLabel: store.severityLabel,
      severityColor: store.severityColor,
      suggestion: store.suggestion,
      inferenceTimeMs: store.inferenceTimeMs || undefined,
      patientInfo: store.patientInfo,
      subScales: store.currentScore > 0 ? subScales.value : undefined,
      subMax: store.currentScore > 0 ? subMax : undefined,
      treatment: store.currentScore > 0 ? treatmentPlan.value : undefined,
      vlmSections: vlmSections.value.length ? vlmSections.value : undefined,
      bdiHistory: store.bdiHistory.length ? [...store.bdiHistory] : undefined,
    },
    chartEl,
  )

  ElMessage.success('PDF 报告已生成')
}

// Clinical recommendations keyed by severity
const treatmentPlan = computed(() => {
  const s = store.severity
  if (s === 'none') return {
    level: '一级干预',
    interventions: [
      '保持规律作息，每周 ≥ 150 分钟中等强度运动',
      '维持社交活动频率，建议每周至少 2 次线下社交',
      '正念冥想训练，每日 10–15 分钟',
    ],
    monitoring: '建议每 3 个月使用 PHQ-9 自评量表随访',
    guidelines: 'APA 实践指南 (2019) · NICE CG90 · 中国抑郁障碍防治指南 (第二版)',
  }
  if (s === 'mild') return {
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
  if (s === 'moderate') return {
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
})

// BDI-II sub-scale estimation (based on literature factor loadings)
const subScales = computed(() => {
  const total = store.currentScore
  // Approximate distribution based on BDI-II factor analysis literature
  // Cognitive-Affective: ~50%, Somatic: ~35%, Behavioral: ~15%
  const cognitive = Math.round(total * 0.48)
  const somatic = Math.round(total * 0.35)
  const behavioral = total - cognitive - somatic
  return { cognitive, somatic, behavioral }
})

const subMax = { cognitive: 30, somatic: 22, behavioral: 11 }

// Parse VLM analysis text into structured sections
interface VlmSection {
  title: string
  content: string
}

const vlmSections = computed((): VlmSection[] => {
  const raw = store.vlmAnalysis
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

  // Last section content
  if (lastEnd > 0 && sections.length > 0) {
    const last = sections[sections.length - 1]
    last.content = raw.slice(lastEnd).trim()
  }

  return sections
})
</script>

<template>
  <div ref="reportRef" class="diagnosis-report">
    <div class="clinical-disclaimer">
      <strong>法律免责合规技术声明</strong>
      <p>本报告仅作为人工智能技术驱动的心理健康辅助筛查结果，不能作为替代精神科临床医生核心病理确诊与处方开具的唯一医学诊断依据。</p>
    </div>

    <div v-if="store.patientInfo" class="patient-bar">
      <div class="pat-field">
        <span class="pat-label">受试者</span>
        <span class="pat-value mono-num">{{ store.patientInfo.patientId }}</span>
      </div>
      <div class="pat-field">
        <span class="pat-label">性别</span>
        <span class="pat-value">{{ store.patientInfo.gender }}</span>
      </div>
      <div class="pat-field">
        <span class="pat-label">年龄段</span>
        <span class="pat-value">{{ store.patientInfo.ageRange }} 岁</span>
      </div>
      <div class="pat-field">
        <span class="pat-label">评估日</span>
        <span class="pat-value mono-num">{{ store.patientInfo.assessmentDate }}</span>
      </div>
    </div>

    <div v-if="!store.currentFrame && !store.analyzing" class="report-empty">
      <el-icon :size="36"><Document /></el-icon>
      <p class="empty-title">等待分析数据</p>
      <p class="empty-hint">选择素材并开始分析后，诊断报告将在此显示</p>
    </div>

    <template v-else>
      <!-- Hero score card -->
      <div class="score-hero" :style="{ '--severity-color': store.severityColor }">
        <div class="score-hero-left">
          <span class="score-hero-label">BDI-II 总评分</span>
          <div class="score-hero-value">
            <ScoreCounter :target="store.currentScore" />
            <span class="score-unit">分</span>
          </div>
          <span class="score-range">评分范围 0–63</span>
        </div>
        <div class="score-hero-right">
          <el-tag
            :color="store.severityColor"
            effect="light"
            size="large"
            class="severity-tag"
          >
            {{ store.severityLabel }}
          </el-tag>
          <div v-if="store.inferenceTimeMs" class="inference-chip mono-num">
            推理 {{ store.inferenceTimeMs.toFixed(1) }} ms
          </div>
        </div>
      </div>

      <!-- Progress -->
      <div v-if="store.analyzing" class="progress-block">
        <div class="progress-header">
          <span>分析进度</span>
          <span class="mono-num">{{ Math.round(store.analysisProgress * 100) }}%</span>
        </div>
        <GlowProgress :percent="store.analysisProgress" />
      </div>

      <!-- Collapsible detail sections -->
      <el-collapse v-model="activeSections" class="report-collapse">
        <el-collapse-item v-if="store.currentScore > 0" title="BDI-II 维度估计（模型推算）" name="subscale">
          <p class="collapse-note">* 以下维度为基于总分的模型估算，非正式量表分项结果</p>
          <div class="subscale-item">
            <div class="ss-header">
              <span>认知-情感维度</span>
              <span class="mono-num">{{ subScales.cognitive }}/{{ subMax.cognitive }}</span>
            </div>
            <GlowProgress :percent="subScales.cognitive / subMax.cognitive" :height="4" />
          </div>
          <div class="subscale-item">
            <div class="ss-header">
              <span>躯体症状维度</span>
              <span class="mono-num">{{ subScales.somatic }}/{{ subMax.somatic }}</span>
            </div>
            <GlowProgress :percent="subScales.somatic / subMax.somatic" :height="4" />
          </div>
          <div class="subscale-item">
            <div class="ss-header">
              <span>行为表现维度</span>
              <span class="mono-num">{{ subScales.behavioral }}/{{ subMax.behavioral }}</span>
            </div>
            <GlowProgress :percent="subScales.behavioral / subMax.behavioral" :height="4" />
          </div>
        </el-collapse-item>

        <el-collapse-item v-if="store.currentScore > 0" :title="`临床干预建议 · ${treatmentPlan.level}`" name="treatment">
          <ul class="treatment-list">
            <li v-for="item in treatmentPlan.interventions" :key="item">{{ item }}</li>
          </ul>
          <div class="treatment-meta">
            <p><strong>随访建议：</strong>{{ treatmentPlan.monitoring }}</p>
            <p class="guidelines">{{ treatmentPlan.guidelines }}</p>
          </div>
        </el-collapse-item>

        <el-collapse-item v-if="vlmSections.length" title="多模态面部分析" name="vlm">
          <div v-for="sec in vlmSections" :key="sec.title" class="vlm-block">
            <div class="vlm-block-title">{{ sec.title }}</div>
            <div class="vlm-block-content">{{ sec.content }}</div>
          </div>
        </el-collapse-item>
      </el-collapse>

      <div v-if="store.currentFrame" class="export-row">
        <el-button type="primary" size="small" :loading="exporting" @click="handleExport">
          <el-icon><Download /></el-icon>
          导出 PDF 报告
        </el-button>
      </div>
    </template>
  </div>
</template>

<style scoped>
.diagnosis-report {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding-top: 4px;
}

.clinical-disclaimer {
  padding: 10px 12px;
  background: #fffbeb;
  border: 1px solid rgba(245, 158, 11, 0.35);
  border-left: 3px solid #f59e0b;
  border-radius: var(--radius-sm);
  font-size: 11px;
  color: #78350f;
  line-height: 1.6;
}

.clinical-disclaimer strong {
  display: block;
  font-size: 12px;
  color: #92400e;
  margin-bottom: 4px;
}

.clinical-disclaimer p {
  margin: 0;
}

.patient-bar {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 6px 12px;
  padding: 10px 12px;
  background: var(--bg-muted);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
}

.pat-field {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}

.pat-label { font-size: 11px; color: var(--text-muted); }
.pat-value { font-size: 12px; color: var(--text-primary); font-weight: 500; }

.report-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: var(--text-muted);
  min-height: 200px;
  text-align: center;
  padding: 24px;
}

.empty-title { font-size: 14px; color: var(--text-secondary); font-weight: 500; }
.empty-hint { font-size: 12px; color: var(--text-muted); }

.score-hero {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 16px;
  background: linear-gradient(135deg, #ecfdf5 0%, #e0f2fe 100%);
  border: 1px solid rgba(13, 148, 136, 0.2);
  border-left: 3px solid var(--severity-color, var(--accent-primary));
  border-radius: var(--radius-card);
}

.score-hero-label {
  font-size: 11px;
  color: var(--text-muted);
  display: block;
  margin-bottom: 4px;
}

.score-hero-value {
  display: flex;
  align-items: baseline;
  gap: 4px;
  font-size: 42px;
  font-weight: 700;
  line-height: 1;
}

.score-unit { font-size: 16px; color: var(--text-muted); font-weight: 400; }
.score-range { font-size: 11px; color: var(--text-muted); font-family: var(--font-mono); margin-top: 4px; display: block; }

.score-hero-right {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 8px;
}

.severity-tag { font-weight: 600; font-size: 13px; }

.inference-chip {
  font-size: 10px;
  color: var(--text-muted);
  padding: 2px 8px;
  background: rgba(148, 163, 184, 0.08);
  border-radius: 10px;
}

.progress-block { margin-bottom: 4px; }

.progress-header {
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  color: var(--text-muted);
  margin-bottom: 6px;
}

.report-collapse { margin-top: 4px; }

.collapse-note {
  font-size: 10px;
  color: var(--text-muted);
  margin-bottom: 10px;
  font-style: italic;
}

.subscale-item { margin-bottom: 8px; }
.subscale-item:last-child { margin-bottom: 0; }

.ss-header {
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  color: var(--text-secondary);
  margin-bottom: 4px;
}

.treatment-list {
  margin: 0 0 10px;
  padding-left: 16px;
}

.treatment-list li {
  font-size: 12px;
  color: var(--text-secondary);
  line-height: 1.65;
  margin-bottom: 4px;
}

.treatment-meta p {
  font-size: 11px;
  color: var(--text-secondary);
  line-height: 1.55;
  margin-bottom: 4px;
}

.guidelines {
  font-size: 10px;
  color: var(--text-muted);
  font-style: italic;
}

.vlm-block { margin-bottom: 10px; }
.vlm-block:last-child { margin-bottom: 0; }

.vlm-block-title {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 4px;
}

.vlm-block-content {
  font-size: 12px;
  color: var(--text-secondary);
  line-height: 1.65;
}

.export-row {
  display: flex;
  justify-content: stretch;
  padding-top: 4px;
}

.export-row .el-button { width: 100%; }
</style>
