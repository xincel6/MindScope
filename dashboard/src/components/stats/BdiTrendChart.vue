<script setup lang="ts">
import { computed } from 'vue'
import { useStatsStore } from '@/stores/stats'
import { severityColors } from '@/stores/dashboard'
import { chartTheme } from '@/utils/chartTheme'

const store = useStatsStore()

const option = computed(() => {
  if (!store.data?.bdi_trend?.length) return {}

  const dates = store.data.bdi_trend.map((d) => d.date)
  const scores = store.data.bdi_trend.map((d) => d.avg_score)

  return {
    backgroundColor: 'transparent',
    grid: { left: 40, right: 16, top: 20, bottom: 30 },
    xAxis: {
      type: 'category' as const,
      data: dates,
      axisLabel: { color: chartTheme.axis, fontSize: 10, rotate: 30 },
      axisLine: { lineStyle: { color: chartTheme.split } },
      axisTick: { show: false },
    },
    yAxis: {
      type: 'value' as const,
      min: 0,
      max: 63,
      interval: 13,
      splitLine: { lineStyle: { color: chartTheme.split } },
      axisLabel: { color: chartTheme.axis, fontSize: 10 },
    },
    series: [
      {
        type: 'line' as const,
        data: scores,
        smooth: true,
        symbol: 'circle',
        symbolSize: 4,
        lineStyle: { width: 2, color: chartTheme.line },
        areaStyle: { color: chartTheme.area },
        markLine: {
          silent: true,
          symbol: 'none',
          label: { fontSize: 9, color: chartTheme.axis },
          data: [
            { yAxis: 13, lineStyle: { color: severityColors.none, type: 'dashed' as const, opacity: 0.4 } },
            { yAxis: 19, lineStyle: { color: severityColors.mild, type: 'dashed' as const, opacity: 0.4 } },
            { yAxis: 28, lineStyle: { color: severityColors.moderate, type: 'dashed' as const, opacity: 0.4 } },
          ],
        },
      },
    ],
    tooltip: {
      trigger: 'axis' as const,
      backgroundColor: chartTheme.tooltipBg,
      borderColor: chartTheme.tooltipBorder,
      textStyle: { color: chartTheme.tooltipText, fontSize: 12 },
    },
  }
})
</script>

<template>
  <div class="bdi-trend glass-card">
    <div class="section-title">BDI 日均趋势</div>
    <div v-if="!store.data?.bdi_trend?.length" class="trend-empty">
      <span>暂无趋势数据</span>
    </div>
    <VChart v-else :option="option" autoresize class="trend-chart" />
  </div>
</template>

<style scoped>
.bdi-trend {
  padding: 16px;
}

.trend-chart {
  width: 100%;
  height: 220px;
}

.trend-empty {
  height: 220px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  font-size: 13px;
}
</style>
