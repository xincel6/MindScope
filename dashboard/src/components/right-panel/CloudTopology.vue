<script setup lang="ts">
import { computed } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'
import { chartTheme } from '@/utils/chartTheme'

const store = useDashboardStore()

const inferenceDisplay = computed(() => {
  if (store.inferenceTimeMs > 0) {
    return `${store.inferenceTimeMs.toFixed(1)} ms`
  }
  return '--'
})

const frameProgress = computed(() => {
  if (store.bdiHistory.length > 0) {
    return `${store.bdiHistory.length} 帧`
  }
  return '--'
})

const currentBdi = computed(() => {
  if (store.bdiHistory.length > 0) {
    return `${store.currentScore} 分`
  }
  return '--'
})

const wsLabel = computed(() => {
  if (store.wsConnected) return '已连接'
  if (store.analyzing) return '连接中...'
  return '未连接'
})

const option = computed(() => ({
  backgroundColor: 'transparent',
  tooltip: {
    trigger: 'item',
    backgroundColor: chartTheme.tooltipBg,
    borderColor: chartTheme.tooltipBorder,
    textStyle: { color: chartTheme.tooltipText, fontSize: 12 },
    formatter: '{b}',
  },
  series: [
    {
      type: 'graph',
      layout: 'force',
      force: { repulsion: 180, edgeLength: [100, 180], friction: 0.6 },
      roam: false,
      draggable: false,
      data: [
        {
          name: '终端设备',
          x: 80, y: 150,
          symbolSize: 42,
          itemStyle: { color: '#0284c7' },
          label: { show: true, color: '#475569', fontSize: 11, position: 'bottom', distance: 10 },
        },
        {
          name: 'LMTformer\n推理节点',
          x: 260, y: 80,
          symbolSize: 54,
          itemStyle: {
            color: '#ffffff',
            borderColor: '#0d9488',
            borderWidth: 2,
            shadowBlur: 8,
            shadowColor: 'rgba(13, 148, 136, 0.25)',
          },
          label: { show: true, color: '#0d9488', fontSize: 11, fontWeight: 600, position: 'top', distance: 14 },
        },
        {
          name: '结果输出',
          x: 260, y: 220,
          symbolSize: 38,
          itemStyle: { color: '#059669' },
          label: { show: true, color: '#475569', fontSize: 11, position: 'bottom', distance: 10 },
        },
      ],
      links: [
        {
          source: '终端设备',
          target: 'LMTformer\n推理节点',
          lineStyle: { color: '#0284c7', curveness: 0.2, opacity: 0.55, width: 2 },
        },
        {
          source: 'LMTformer\n推理节点',
          target: '结果输出',
          lineStyle: { color: '#059669', curveness: 0.2, opacity: 0.55, width: 2 },
        },
      ],
    },
  ],
}))
</script>

<template>
  <div class="cloud-topo">
    <div class="section-title section-title--bordered">云端推理状态</div>

    <div class="topo-chart-wrap">
      <VChart :option="option" autoresize class="topo-chart" />
    </div>

    <div class="flow-desc">
      <span class="flow-step">终端采集</span>
      <span class="flow-arrow">→</span>
      <span class="flow-step active">LMTformer 推理</span>
      <span class="flow-arrow">→</span>
      <span class="flow-step">BDI 评分输出</span>
    </div>

    <div class="live-stats">
      <div class="stat-row">
        <span class="label">批次推理耗时</span>
        <span class="value mono-num">{{ inferenceDisplay }}</span>
      </div>
      <div class="stat-row">
        <span class="label">帧序进度</span>
        <span class="value mono-num">{{ frameProgress }}</span>
      </div>
      <div class="stat-row">
        <span class="label">当前 BDI 评分</span>
        <span class="value mono-num" :style="{ color: store.severityColor }">{{ currentBdi }}</span>
      </div>
      <div class="stat-row">
        <span class="label">WebSocket 连接</span>
        <span class="value" :class="{ online: store.wsConnected, pending: store.analyzing && !store.wsConnected }">
          <span
            class="status-dot"
            :class="store.wsConnected ? 'connected' : store.analyzing ? 'connecting' : 'disconnected'"
          />
          {{ wsLabel }}
        </span>
      </div>
      <div class="stat-row">
        <span class="label">分析状态</span>
        <span class="value" :style="{ color: store.analyzing ? 'var(--accent-primary)' : 'var(--text-muted)' }">
          {{ store.analyzing ? '进行中' : '空闲' }}
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.cloud-topo {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding-top: 4px;
}

.topo-chart-wrap {
  background: linear-gradient(145deg, #ecfdf5 0%, #e0f2fe 100%);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-card);
  padding: 8px;
}

.topo-chart {
  width: 100%;
  height: 200px;
}

.flow-desc {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  flex-wrap: wrap;
  padding: 8px 10px;
  background: var(--bg-muted);
  border-radius: var(--radius-sm);
  border: 1px solid var(--border-subtle);
}

.flow-step {
  font-size: 11px;
  color: var(--text-muted);
  padding: 2px 8px;
  border-radius: 10px;
}

.flow-step.active {
  color: var(--accent-primary);
  background: rgba(13, 148, 136, 0.1);
  font-weight: 600;
}

.flow-arrow {
  font-size: 11px;
  color: var(--text-muted);
}

.live-stats {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.stat-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 12px;
  background: var(--bg-muted);
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-sm);
}

.stat-row .label {
  font-size: 12px;
  color: var(--text-muted);
}

.stat-row .value {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 600;
  color: var(--accent-primary);
}

.stat-row .value.online {
  color: #059669;
}

.stat-row .value.pending {
  color: var(--accent-yellow);
}
</style>
