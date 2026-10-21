<script setup lang="ts">
import { computed } from 'vue'
import { useStatsStore } from '@/stores/stats'
import { severityColors } from '@/stores/dashboard'
import { chartTheme } from '@/utils/chartTheme'
import { usePrefersReducedMotion } from '@/composables/usePrefersReducedMotion'
import EmptyState from '@/components/common/EmptyState.vue'

const store = useStatsStore()
const reducedMotion = usePrefersReducedMotion()

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
    // 系统减弱动效时关闭 ECharts 入场动画（CSS reduce 管不到 canvas）
    animation: !reducedMotion.value,
    tooltip: {
      trigger: 'item' as const,
      backgroundColor: chartTheme.tooltipBg,
      borderColor: chartTheme.tooltipBorder,
      textStyle: { color: chartTheme.tooltipText, fontSize: 12 },
      formatter: '{b}: {c} 例 ({d}%)',
    },
    legend: {
      bottom: 0,
      textStyle: { color: chartTheme.axis, fontSize: 11 },
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
    <div v-if="store.data?.total_analyses">
      <div class="pie-total">
        <span class="total-num mono-num">{{ store.data.total_analyses }}</span>
        <span class="total-label">例分析</span>
      </div>
      <VChart :option="option" autoresize class="pie-chart" />
    </div>
    <!-- 0 例时画空坐标系等于「看起来有数据但全是 0」，这里直接给空态 -->
    <div v-else class="pie-empty">
      <EmptyState
        icon="PieChart"
        title="暂无分析数据"
        description="完成第一次分析后，这里会按严重等级统计分布。"
        hint="数据来源：/api/stats · severity_distribution"
      />
    </div>
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

.pie-empty {
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
  font-size: var(--font-title);
  font-weight: 700;
  color: var(--color-primary-text);
}

.total-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}
</style>
