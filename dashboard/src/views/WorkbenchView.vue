<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Refresh } from '@element-plus/icons-vue'
import PageHeader from '@/components/layout/PageHeader.vue'
import StatusBadge from '@/components/common/StatusBadge.vue'
import AssessmentHeroCard from '@/components/workbench/AssessmentHeroCard.vue'
import StartAssessmentCard from '@/components/workbench/StartAssessmentCard.vue'
import AttentionHeatmapCard from '@/components/workbench/AttentionHeatmapCard.vue'
import SeverityDistributionCard from '@/components/workbench/SeverityDistributionCard.vue'
import VlmCard from '@/components/workbench/VlmCard.vue'
import DiagnosisOpinionCard from '@/components/workbench/DiagnosisOpinionCard.vue'
import EmotionCurve from '@/components/right-panel/EmotionCurve.vue'
import PatientInfoDialog from '@/components/common/PatientInfoDialog.vue'
import { useDashboardStore } from '@/stores/dashboard'

const store = useDashboardStore()
const refreshing = ref(false)
const patientDialogVisible = ref(false)
const online = ref(navigator.onLine)

const today = new Date().toLocaleDateString('zh-CN', {
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  weekday: 'long',
})

const greeting = computed(() => {
  const hour = new Date().getHours()
  if (hour < 11) return '早上好'
  if (hour < 14) return '中午好'
  if (hour < 19) return '下午好'
  return '晚上好'
})

const subtitle = computed(() => `${greeting.value} · ${today}`)

const socketStatus = computed<'connected' | 'connecting' | 'disconnected'>(() => {
  if (store.wsConnected) return 'connected'
  if (store.analyzing) return 'connecting'
  return 'disconnected'
})

async function refresh() {
  refreshing.value = true
  try {
    await store.loadMediaList()
  } finally {
    refreshing.value = false
  }
}

function onOnline() {
  online.value = true
}

function onOffline() {
  online.value = false
}

function onPatientConfirm(info: {
  patientId: string
  gender: string
  ageRange: string
  assessmentDate: string
}) {
  store.setPatientInfo(info)
}

onMounted(() => {
  window.addEventListener('online', onOnline)
  window.addEventListener('offline', onOffline)
  if (!store.mediaList.length) void store.loadMediaList()
})

onBeforeUnmount(() => {
  window.removeEventListener('online', onOnline)
  window.removeEventListener('offline', onOffline)
})
</script>

<template>
  <div class="app-page workbench-page">
    <PageHeader title="工作台" :subtitle="subtitle">
      <template #actions>
        <StatusBadge v-if="store.analyzing || store.wsConnected" :status="socketStatus" />
        <el-button :icon="Refresh" :loading="refreshing" plain @click="refresh">刷新</el-button>
      </template>
    </PageHeader>

    <!-- 离线提示：P3 只保留位置与文案，重试逻辑在 P4 接入 -->
    <div v-if="!online" class="offline-banner" role="status">
      <span class="offline-dot" aria-hidden="true" />
      <div class="offline-text">
        <strong class="offline-title">无法连接服务器</strong>
        <span class="offline-desc">
          当前网络已离线，页面可能显示上一次的数据。
        </span>
      </div>
    </div>

    <div class="wb-grid">
      <AssessmentHeroCard class="wb-hero" @patient="patientDialogVisible = true" />
      <StartAssessmentCard class="wb-start" />

      <template v-if="store.selectedMedia">
        <AttentionHeatmapCard class="wb-heat" />
        <EmotionCurve class="wb-curve" />
        <SeverityDistributionCard class="wb-sev" />
        <VlmCard class="wb-vlm" />
        <DiagnosisOpinionCard class="wb-opinion" />
      </template>
    </div>

    <PatientInfoDialog v-model:visible="patientDialogVisible" @confirm="onPatientConfirm" />
  </div>
</template>

<style scoped>
.workbench-page {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
}

.offline-banner {
  display: flex;
  align-items: flex-start;
  gap: var(--space-2);
  padding: var(--space-3) var(--space-4);
  background: var(--color-danger-soft);
  border: 1px solid var(--border);
  border-left: 3px solid var(--color-danger);
  border-radius: var(--radius-tag);
}

.offline-dot {
  flex: 0 0 auto;
  width: 8px;
  height: 8px;
  margin-top: 6px;
  border-radius: var(--radius-pill);
  background: var(--color-danger);
}

.offline-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.offline-title {
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--color-danger);
}

.offline-desc {
  font-size: var(--font-xs);
  line-height: 1.55;
  color: var(--text-secondary);
}

.wb-grid {
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  gap: var(--content-gap);
  align-items: stretch;
}

.wb-grid > * {
  min-width: 0;
}

.wb-hero {
  grid-column: span 8;
}

.wb-start {
  grid-column: span 4;
}

.wb-heat {
  grid-column: span 7;
}

.wb-curve {
  grid-column: span 5;
}

.wb-sev,
.wb-vlm,
.wb-opinion {
  grid-column: span 4;
}

/* ≥1280 三列时，诊断意见卡内容明显更高；不要让右侧两张卡被 grid 拉伸出大片空白。 */
@media (min-width: 1280px) {
  .wb-sev,
  .wb-vlm {
    align-self: start;
  }
}

/* 1024–1279：A/B 两行全宽；C 行前两张各半行，诊断意见单独全宽，
   避免第三张卡落在半行留下孤卡。 */
@media (max-width: 1279px) {
  .wb-hero,
  .wb-start,
  .wb-heat,
  .wb-curve {
    grid-column: span 12;
  }

  .wb-sev,
  .wb-vlm {
    grid-column: span 6;
  }

  .wb-opinion {
    grid-column: span 12;
  }
}

/* 768–1023：单列 */
@media (max-width: 1023px) {
  .wb-sev,
  .wb-vlm,
  .wb-opinion {
    grid-column: span 12;
  }
}
</style>
