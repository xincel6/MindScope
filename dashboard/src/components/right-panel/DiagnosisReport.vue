<script setup lang="ts">
import { ref, computed } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'
import { usePdfExport } from '@/composables/usePdfExport'
import ScoreCounter from '@/components/common/ScoreCounter.vue'
import ProgressBar from '@/components/common/ProgressBar.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import dayjs from 'dayjs'
import { ElMessage } from 'element-plus'
import { buildTreatmentPlan, parseVlmSections } from '@/utils/clinicalContent'

const store = useDashboardStore()
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
      severityColor: store.severityTextColor,
      suggestion: store.suggestion,
      inferenceTimeMs: store.inferenceTimeMs || undefined,
      patientInfo: store.patientInfo,
      treatment: store.currentScore > 0 ? treatmentPlan.value : undefined,
      vlmSections: vlmSections.value.length ? vlmSections.value : undefined,
      bdiHistory: store.bdiHistory.length ? [...store.bdiHistory] : undefined,
    },
    chartEl,
  )

  ElMessage.success('PDF 报告已生成')
}

const treatmentPlan = computed(() => buildTreatmentPlan(store.severity))

const vlmSections = computed(() => parseVlmSections(store.vlmAnalysis))
</script>

<template>
  <div class="diagnosis-report">
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
      <EmptyState
        icon="Document"
        title="等待分析数据"
        description="选择素材并开始分析后，诊断报告将在此显示"
      />
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
            effect="light"
            size="large"
            class="severity-tag"
            :class="`sev-${store.severity}`"
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
        <ProgressBar :percent="store.analysisProgress" />
      </div>

      <!-- Collapsible detail sections -->
      <el-collapse v-model="activeSections" class="report-collapse">
        <el-collapse-item title="BDI-II 量表分项" name="subscale">
          <EmptyState
            compact
            icon="InfoFilled"
            title="本模型未输出量表分项"
            description="LMTformer 只回归 BDI-II 总分（每个片段输出一个值），不产出认知-情感 / 躯体症状 / 行为表现三个维度的分项分数。"
            hint="需要分项分数时，请按正式 BDI-II 量表施测并手工计分。"
          />
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

/* 免责声明：warning 语义底 + 左 3px 警示条；不用投影 */
.clinical-disclaimer {
  padding: 10px 12px;
  background: var(--color-warning-soft);
  border: 1px solid var(--border);
  border-left: 3px solid var(--color-warning);
  border-radius: var(--radius-tag);
  font-size: var(--font-xs);
  color: var(--text-primary);
  line-height: 1.6;
}

.clinical-disclaimer strong {
  display: block;
  font-size: var(--font-xs);
  color: var(--color-warning-text);
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
  background: var(--bg-inset);
  border: 1px solid var(--border);
  border-radius: var(--radius-tag);
}

.pat-field {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}

.pat-label { font-size: var(--font-xs); color: var(--text-secondary); }
.pat-value { font-size: var(--font-xs); color: var(--text-primary); font-weight: 500; }

.report-empty {
  min-height: 200px;
}

/* Hero 卡：纯色内嵌底 + 1px 描边 + 严重度左边条（去薄荷→天蓝渐变） */
.score-hero {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 16px;
  background: var(--bg-inset);
  border: 1px solid var(--border);
  border-left: 3px solid var(--severity-color, var(--color-primary));
  border-radius: var(--radius-card);
}

.score-hero-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  display: block;
  margin-bottom: 4px;
}

.score-hero-value {
  display: flex;
  align-items: baseline;
  gap: 4px;
  font-size: var(--font-metric);
  font-weight: 700;
  line-height: 1;
}

.score-unit { font-size: var(--font-base); color: var(--text-secondary); font-weight: 400; }
.score-range { font-size: var(--font-xs); color: var(--text-secondary); font-family: var(--font-mono); margin-top: 4px; display: block; }

.score-hero-right {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 8px;
}

.severity-tag { font-weight: 600; font-size: var(--font-xs); }

.inference-chip {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  padding: 2px 8px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-tag);
}

.progress-block { margin-bottom: 4px; }

.progress-header {
  display: flex;
  justify-content: space-between;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  margin-bottom: 6px;
}

.report-collapse { margin-top: 4px; }

.treatment-list {
  margin: 0 0 10px;
  padding-left: 16px;
}

.treatment-list li {
  font-size: var(--font-sm);
  color: var(--text-secondary);
  line-height: 1.65;
  margin-bottom: 4px;
}

.treatment-meta p {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  line-height: 1.55;
  margin-bottom: 4px;
}

.guidelines {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-style: italic;
}

.vlm-block { margin-bottom: 10px; }
.vlm-block:last-child { margin-bottom: 0; }

.vlm-block-title {
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 4px;
}

.vlm-block-content {
  font-size: var(--font-sm);
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
