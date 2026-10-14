<script setup lang="ts">
import { computed } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'

const store = useDashboardStore()

const inferenceDisplay = computed(() =>
  store.inferenceTimeMs > 0 ? `${store.inferenceTimeMs.toFixed(1)} ms` : '--',
)

const frameCount = computed(() =>
  store.bdiHistory.length > 0 ? `${store.bdiHistory.length} 帧` : '--',
)

const wsStatus = computed(() => {
  if (store.wsConnected) return { label: '服务已连接', ok: true }
  if (store.analyzing) return { label: '连接中', ok: false, pending: true }
  return { label: '服务未连接', ok: false }
})
</script>

<template>
  <div class="status-bar">
    <div class="status-group">
      <div class="status-chip">
        <span class="chip-label">BDI-II</span>
        <span class="chip-value mono-num" :style="{ color: store.severityColor }">
          {{ store.bdiHistory.length ? store.currentScore : '--' }}
        </span>
      </div>
      <div class="status-chip">
        <span class="chip-label">严重度</span>
        <span class="chip-value">{{ store.bdiHistory.length ? store.severityLabel : '--' }}</span>
      </div>
      <div class="status-chip">
        <span class="chip-label">推理耗时</span>
        <span class="chip-value mono-num">{{ inferenceDisplay }}</span>
      </div>
      <div class="status-chip">
        <span class="chip-label">分析帧数</span>
        <span class="chip-value mono-num">{{ frameCount }}</span>
      </div>
    </div>
    <div class="status-group status-group--right">
      <div class="status-chip" :class="{ ok: wsStatus.ok, pending: wsStatus.pending }">
        <span
          class="status-dot"
          :class="wsStatus.ok ? 'connected' : wsStatus.pending ? 'connecting' : 'disconnected'"
        />
        <span class="chip-value">{{ wsStatus.label }}</span>
      </div>
      <div v-if="store.analyzing" class="analyzing-badge">
        <span class="pulse-ring" />
        分析进行中
      </div>
    </div>
  </div>
</template>

<style scoped>
.status-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 0 16px;
  height: 36px;
  background: rgba(255, 255, 255, 0.75);
  border-bottom: 1px solid var(--border-color);
  flex-shrink: 0;
  overflow-x: auto;
}

.status-group {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}

.status-group--right {
  margin-left: auto;
}

.status-chip {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px;
  background: var(--bg-muted);
  border: 1px solid var(--border-subtle);
  border-radius: 20px;
  font-size: 11px;
}

.status-chip.ok {
  border-color: rgba(16, 185, 129, 0.3);
  background: rgba(16, 185, 129, 0.08);
}

.status-chip.pending {
  border-color: rgba(245, 158, 11, 0.3);
  background: rgba(245, 158, 11, 0.08);
}

.chip-label {
  color: var(--text-muted);
}

.chip-value {
  color: var(--text-primary);
  font-weight: 600;
}

.analyzing-badge {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: var(--accent-primary);
  font-weight: 500;
}

.pulse-ring {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--accent-primary);
  animation: pulse-dot 1.4s ease-in-out infinite;
}
</style>
