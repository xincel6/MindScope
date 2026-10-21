<script setup lang="ts">
import { computed } from 'vue'
import type { ReportListItem } from '@/api/index'
import { severityTextColorOf, severityTextColors } from '@/stores/dashboard'

const props = defineProps<{
  visible: boolean
  reportA: ReportListItem | null
  reportB: ReportListItem | null
}>()

const emit = defineEmits<{
  'update:visible': [value: boolean]
}>()

const labels: Record<string, string> = {
  none: '正常',
  mild: '轻度',
  moderate: '中度',
  severe: '重度',
}

const delta = computed(() => {
  if (!props.reportA || !props.reportB) return null
  return props.reportB.bdi_score - props.reportA.bdi_score
})

const deltaColor = computed(() => {
  if (delta.value === null) return 'var(--text-secondary)'
  // Lower BDI is better (less depression)
  if (delta.value < 0) return severityTextColors.none
  if (delta.value > 0) return severityTextColors.severe
  return 'var(--text-secondary)'
})

const deltaLabel = computed(() => {
  if (delta.value === null) return ''
  const sign = delta.value > 0 ? '+' : ''
  return `${sign}${delta.value.toFixed(1)}`
})
</script>

<template>
  <el-dialog
    :model-value="visible"
    @update:model-value="emit('update:visible', $event)"
    title="诊断报告对比"
    width="min(760px, calc(100vw - 32px))"
    :close-on-click-modal="false"
    class="comparison-dialog"
  >
    <div class="comparison-body" v-if="reportA && reportB">
      <!-- Column A -->
      <div class="comp-col">
        <div class="comp-header">
          <div class="comp-label">报告 A</div>
          <div class="comp-media-name">{{ reportA.media_name }}</div>
          <div class="comp-date">{{ reportA.detected_at }}</div>
        </div>
        <div class="comp-score" :style="{ color: severityTextColorOf(reportA.severity) }">
          {{ reportA.bdi_score.toFixed(1) }}
          <span class="comp-max">/ 63</span>
        </div>
        <el-tag effect="light" round size="large" :class="`sev-${reportA.severity}`">
          {{ labels[reportA.severity] ?? reportA.severity }}
        </el-tag>
        <div class="comp-inf">
          推理耗时 {{ reportA.inference_time_ms.toFixed(1) }} ms
        </div>
      </div>

      <!-- Delta -->
      <div class="comp-divider">
        <div class="delta-arrow" :style="{ color: deltaColor }">
          {{ deltaLabel }}
        </div>
        <div class="delta-hint">评分变化</div>
      </div>

      <!-- Column B -->
      <div class="comp-col">
        <div class="comp-header">
          <div class="comp-label">报告 B</div>
          <div class="comp-media-name">{{ reportB.media_name }}</div>
          <div class="comp-date">{{ reportB.detected_at }}</div>
        </div>
        <div class="comp-score" :style="{ color: severityTextColorOf(reportB.severity) }">
          {{ reportB.bdi_score.toFixed(1) }}
          <span class="comp-max">/ 63</span>
        </div>
        <el-tag effect="light" round size="large" :class="`sev-${reportB.severity}`">
          {{ labels[reportB.severity] ?? reportB.severity }}
        </el-tag>
        <div class="comp-inf">
          推理耗时 {{ reportB.inference_time_ms.toFixed(1) }} ms
        </div>
      </div>
    </div>

    <div v-else class="comp-empty">
      请选择两条记录进行对比
    </div>
  </el-dialog>
</template>

<style scoped>
.comparison-dialog :deep(.el-dialog) {
  --el-dialog-bg-color: var(--bg-card);
  --el-dialog-border-color: var(--border);
}

.comparison-dialog :deep(.el-dialog__title) {
  color: var(--text-primary);
  font-size: var(--font-base);
}

.comparison-body {
  display: flex;
  align-items: flex-start;
  gap: 0;
}

.comp-col {
  flex: 1;
  text-align: center;
  padding: 24px 16px;
  background: var(--bg-inset);
  border-radius: var(--radius-card);
  border: 1px solid var(--border);
}

.comp-header {
  margin-bottom: 16px;
}

.comp-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  letter-spacing: 1px;
  margin-bottom: 4px;
}

.comp-media-name {
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 2px;
  overflow-wrap: anywhere;
}

.comp-date {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.comp-score {
  font-size: var(--font-metric);
  font-weight: 700;
  line-height: 1;
  font-family: var(--font-mono);
  margin-bottom: 10px;
}

.comp-max {
  font-size: var(--font-base);
  font-weight: 400;
  color: var(--text-secondary);
}

.comp-inf {
  margin-top: 12px;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.comp-divider {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 0 20px;
  flex-shrink: 0;
}

.delta-arrow {
  font-size: var(--font-base);
  font-weight: 700;
  font-family: var(--font-mono);
}

.delta-hint {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  margin-top: 2px;
}

.comp-empty {
  text-align: center;
  padding: 40px;
  color: var(--text-secondary);
  font-size: var(--font-sm);
}

@media (max-width: 640px) {
  .comparison-body {
    flex-direction: column;
    gap: var(--space-2);
  }

  .comp-col {
    width: 100%;
    box-sizing: border-box;
    padding: var(--space-4) var(--space-3);
  }

  .comp-divider {
    flex-direction: row;
    gap: var(--space-2);
    padding: var(--space-1) 0;
  }
}
</style>
