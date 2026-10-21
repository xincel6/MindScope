<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { VideoCamera, Picture, User, Refresh, Download, Switch } from '@element-plus/icons-vue'
import dayjs from 'dayjs'
import { useDashboardStore } from '@/stores/dashboard'
import { usePdfExport } from '@/composables/usePdfExport'
import ScoreCounter from '@/components/common/ScoreCounter.vue'
import ProgressBar from '@/components/common/ProgressBar.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { buildTreatmentPlan, parseVlmSections } from '@/utils/clinicalContent'

const emit = defineEmits<{ patient: [] }>()

const store = useDashboardStore()
const router = useRouter()
const { exporting, exportReport } = usePdfExport()

const treatment = computed(() => buildTreatmentPlan(store.severity))
const vlmSections = computed(() => parseVlmSections(store.vlmAnalysis))
const mediaTypeLabel = computed(() => (store.selectedMedia?.type === 'video' ? '视频 · 逐帧采样' : '图片 · 单次推理'))

function startAnalysis() {
  if (store.selectedMediaId) store.startAnalysis(store.selectedMediaId)
}

async function handleExport() {
  try {
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
        treatment: store.currentScore > 0 ? treatment.value : undefined,
        vlmSections: vlmSections.value.length ? vlmSections.value : undefined,
        bdiHistory: store.bdiHistory.length ? [...store.bdiHistory] : undefined,
      },
      document.querySelector('.emotion-curve') as HTMLElement | null,
    )
    ElMessage.success('PDF 报告已生成')
  } catch (e: unknown) {
    ElMessage.error(e instanceof Error ? e.message : 'PDF 导出失败')
  }
}
</script>

<template>
  <section class="hero-card glass-card">
    <template v-if="!store.selectedMedia">
      <EmptyState
        icon="Aim"
        title="还没有评估记录"
        description="从素材库选择一张图片或一段视频，开始第一次辅助评估。"
        hint="评分由模型逐帧推理产出，仅作辅助筛查"
        action-label="去素材库"
        @action="router.push('/library')"
      />
    </template>

    <template v-else>
      <header class="hero-head">
        <div class="hero-media">
          <span class="hero-media-icon" aria-hidden="true">
            <el-icon :size="20">
              <VideoCamera v-if="store.selectedMedia?.type === 'video'" />
              <Picture v-else />
            </el-icon>
          </span>
          <div class="hero-media-text">
            <span class="hero-media-name" :title="store.selectedMedia?.name">{{ store.selectedMedia?.name }}</span>
            <span class="hero-media-meta">{{ mediaTypeLabel }}</span>
          </div>
        </div>
        <div class="hero-head-actions">
          <el-tag v-if="store.patientInfo" size="small" effect="light">
            受试者 {{ store.patientInfo.patientId }}
          </el-tag>
          <el-button size="small" :icon="User" plain @click="emit('patient')">受试者信息</el-button>
          <el-button size="small" text @click="router.push('/library')">
            <el-icon><Switch /></el-icon>
            <span>更换素材</span>
          </el-button>
        </div>
      </header>

      <!-- 已选中素材但还没有开始 -->
      <div v-if="!store.currentFrame && !store.analyzing" class="hero-ready">
        <div class="hero-ready-text">
          <p class="hero-ready-title">素材已就绪，尚未开始评估</p>
          <p class="hero-ready-desc">
            视频会按固定间隔抽帧并逐帧推理，图片只做一次推理；结果会实时写入下方热力图与评分曲线。
          </p>
        </div>
        <el-button type="primary" :icon="Refresh" @click="startAnalysis">开始分析</el-button>
      </div>

      <!-- 已发起分析但还没收到首帧 -->
      <div v-else-if="!store.currentFrame" class="hero-waiting">
        <div class="hero-waiting-head">
          <span>正在连接模型服务…</span>
          <span class="mono-num">{{ Math.round(store.analysisProgress * 100) }}%</span>
        </div>
        <ProgressBar :percent="store.analysisProgress" :height="6" />
      </div>

      <!-- 有帧：评分 + 进度 + 操作 -->
      <div v-else class="hero-result">
        <div class="hero-score-row">
          <div class="hero-score-block">
            <span class="hero-label">BDI-II 总评分</span>
            <div class="hero-score-value">
              <ScoreCounter :target="store.currentScore" />
              <span class="hero-score-unit">/ 63</span>
            </div>
            <span class="hero-score-range">评分范围 0–63</span>
          </div>
          <div class="hero-score-side">
            <el-tag effect="light" size="large" :class="`sev-${store.severity}`">
              {{ store.severityLabel }}
            </el-tag>
            <span v-if="store.inferenceTimeMs" class="hero-chip mono-num">
              推理 {{ store.inferenceTimeMs.toFixed(1) }} ms
            </span>
            <span class="hero-chip mono-num">已采集 {{ store.bdiHistory.length }} 帧</span>
          </div>
        </div>

        <div v-if="store.analyzing" class="hero-progress">
          <div class="hero-progress-head">
            <span>分析进度</span>
            <span class="mono-num">{{ Math.round(store.analysisProgress * 100) }}%</span>
          </div>
          <ProgressBar :percent="store.analysisProgress" :height="6" />
        </div>

        <div class="hero-actions">
          <el-button v-if="!store.analyzing" type="primary" :icon="Refresh" @click="startAnalysis">
            重新分析该素材
          </el-button>
          <span v-else class="hero-actions-hint">分析进行中，结果会实时更新。</span>
          <el-button :icon="Download" :loading="exporting" plain @click="handleExport">导出 PDF 报告</el-button>
        </div>

        <details v-if="store.currentScore > 0" class="hero-treatment">
          <summary>临床干预建议 · {{ treatment.level }}</summary>
          <ul class="treatment-list">
            <li v-for="item in treatment.interventions" :key="item">{{ item }}</li>
          </ul>
          <p class="treatment-meta"><strong>随访建议：</strong>{{ treatment.monitoring }}</p>
          <p class="treatment-meta"><strong>指南依据：</strong>{{ treatment.guidelines }}</p>
        </details>
      </div>

    </template>

    <p class="clinical-disclaimer">
      <strong>法律免责合规技术声明</strong>
      本结果仅作为人工智能辅助筛查参考，不能替代精神科临床医生的诊断与处方。
    </p>
  </section>
</template>

<style scoped>
.hero-card {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  min-width: 0;
}

.hero-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-3);
  flex-wrap: wrap;
}

.hero-media {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-width: 0;
}

.hero-media-icon {
  flex: 0 0 auto;
  width: 40px;
  height: 40px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--radius-tag);
  background: var(--bg-inset);
  color: var(--color-primary-text);
}

.hero-media-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
  line-height: 1.35;
}

.hero-media-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--font-base);
  font-weight: 600;
  color: var(--text-primary);
}

.hero-media-meta {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.hero-head-actions {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: var(--space-1);
}

.hero-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.hero-score-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-4);
  flex-wrap: wrap;
}

.hero-score-block {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.hero-score-value {
  display: flex;
  align-items: baseline;
  gap: var(--space-1);
  font-size: var(--font-metric);
  line-height: 1.1;
  color: var(--text-primary);
}

.hero-score-unit {
  font-size: var(--font-sm);
  color: var(--text-secondary);
  font-weight: 400;
}

.hero-score-range {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.hero-score-side {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: var(--space-2);
}

.hero-chip {
  padding: 3px 10px;
  border-radius: var(--radius-pill);
  background: var(--bg-inset);
  color: var(--text-secondary);
  font-size: var(--font-xs);
}

.hero-progress {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.hero-progress-head,
.hero-waiting-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.hero-waiting {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  padding: var(--space-3);
  background: var(--bg-inset);
  border-radius: var(--radius-tag);
}

.hero-ready {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  flex-wrap: wrap;
  padding: var(--space-3);
  background: var(--bg-inset);
  border-radius: var(--radius-tag);
}

.hero-ready-text {
  min-width: 0;
}

.hero-ready-title {
  margin: 0;
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.hero-ready-desc {
  margin: var(--space-1) 0 0;
  font-size: var(--font-xs);
  line-height: 1.55;
  color: var(--text-secondary);
}

.hero-actions {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: var(--space-2);
}

.hero-actions-hint {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.hero-treatment {
  padding: var(--space-2) var(--space-3);
  background: var(--bg-inset);
  border-radius: var(--radius-tag);
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.hero-treatment summary {
  cursor: pointer;
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.treatment-list {
  margin: var(--space-2) 0 0;
  padding-left: 18px;
  line-height: 1.6;
}

.treatment-meta {
  margin: var(--space-2) 0 0;
  line-height: 1.6;
  color: var(--text-secondary);
}

.clinical-disclaimer {
  margin: 0;
}
</style>
