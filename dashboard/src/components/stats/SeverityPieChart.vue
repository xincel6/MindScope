<script setup lang="ts">
import { computed } from 'vue'
import { useStatsStore } from '@/stores/stats'
import { severityColors } from '@/stores/dashboard'
import { chartTheme } from '@/utils/chartTheme'

const store = useStatsStore()

const option = computed(() => {
  if (!store.data?.severity_distribution) return {}

  const labels: Record<string, string> = {
    none: '正常 0–13',
    mild: '轻度 14–19',
    moderate: '中度 20–28',
    severe: '重度 29–63',
  }

  const data = Object.entries(store.data.severity_distribution).map(([k, v]) => ({
    name: labels[k] ?? k,
    value: v,
    itemStyle: { color: severityColors[k as keyof typeof severityColors] ?? '#94a3b8' },
  }))

  return {
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'item' as const,
      backgroundColor: chartTheme.tooltipBg,
      borderColor: chartTheme.tooltipBorder,
      textStyle: { color: chartTheme.tooltipText, fontSize: 12 },
      formatter: '{b}: {c} 例 ({d}%)',
    },
    legend: {
      bottom: 0,
      textStyle: { color: chartTheme.axis, fontSize: 10 },
    },
    series: [
      {
        type: 'pie' as const,
        radius: ['55%', '80%'],
        center: ['50%', '48%'],
        avoidLabelOverlap: false,
        label: { show: false },
        emphasis: {
          label: { show: true, fontSize: 14, fontWeight: 'bold' },
        },
        data,
      },
    ],
  }
})
</script>

<template>
  <div class="severity-pie glass-card">
    <div class="section-title">严重等级分布</div>
    <div v-if="store.data?.total_analyses" class="pie-total">
      <span class="total-num mono-num">{{ store.data.total_analyses }}</span>
      <span class="total-label">例分析</span>
    </div>
    <VChart :option="option" autoresize class="pie-chart" />
  </div>
</template>

<style scoped>
.severity-pie {
  padding: 16px;
  position: relative;
}

.pie-chart {
  width: 100%;
  height: 220px;
}

.pie-total {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -42%);
  text-align: center;
  pointer-events: none;
  z-index: 2;
}

.total-num {
  display: block;
  font-size: 22px;
  font-weight: 700;
  color: var(--accent-cyan);
}

.total-label {
  font-size: 11px;
  color: var(--text-muted);
}
</style>
