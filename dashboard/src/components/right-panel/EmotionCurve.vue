<script setup lang="ts">
import { computed } from 'vue'
import { useDashboardStore, severityColors } from '@/stores/dashboard'
import { chartTheme } from '@/utils/chartTheme'

const store = useDashboardStore()

const hasData = computed(() => store.bdiHistory.length > 0)

const option = computed(() => {
  const scores = store.bdiHistory.map((p) => p.score)
  const times = store.bdiHistory.map((p) => p.time)

  // Build per-point colors from severity
  const colors = scores.map((s) => {
    if (s > 28) return severityColors.severe
    if (s > 19) return severityColors.moderate
    if (s > 13) return severityColors.mild
    return severityColors.none
  })

  return {
    backgroundColor: 'transparent',
    grid: { left: 40, right: 16, top: 20, bottom: 30 },
    xAxis: {
      type: 'category',
      data: times,
      boundaryGap: false,
      axisLine: { lineStyle: { color: chartTheme.split } },
      axisTick: { show: false },
      axisLabel: {
        color: chartTheme.axis,
        fontSize: 10,
        interval: Math.max(Math.floor(times.length / 5), 0),
      },
    },
    yAxis: {
      type: 'value',
      min: 0,
      max: 63,
      interval: 13,
      splitLine: { lineStyle: { color: chartTheme.split } },
      axisLabel: { color: chartTheme.axis, fontSize: 10 },
    },
    series: [
      {
        type: 'line',
        data: scores,
        smooth: false,
        symbol: 'circle',
        symbolSize: 4,
        lineStyle: { width: 2, color: chartTheme.line },
        itemStyle: {
          color: (params: any) => colors[params.dataIndex] || chartTheme.line,
        },
        areaStyle: { color: chartTheme.area },
      },
    ],
    tooltip: {
      trigger: 'axis',
      backgroundColor: chartTheme.tooltipBg,
      borderColor: chartTheme.tooltipBorder,
      textStyle: { color: chartTheme.tooltipText, fontSize: 12 },
    },
  }
})
</script>

<template>
  <div class="emotion-curve glass-card">
    <div class="section-title section-title--bordered">
      BDI-II 评分曲线
      <span v-if="hasData" class="data-count">({{ store.bdiHistory.length }} 点)</span>
    </div>

    <div v-if="!hasData" class="chart-empty">
      <el-icon :size="32"><TrendCharts /></el-icon>
      <span>上传素材后将实时显示评分曲线</span>
    </div>

    <VChart v-else :option="option" autoresize class="chart-instance" />

    <!-- Score list: always visible when data exists -->
    <div v-if="hasData" class="score-list">
      <span
        v-for="(p, i) in store.bdiHistory"
        :key="i"
        class="score-chip"
        :style="{ color: p.score > 28 ? severityColors.severe : p.score > 19 ? severityColors.moderate : p.score > 13 ? severityColors.mild : severityColors.none }"
      >{{ p.score }}</span>
    </div>

    <!-- Severity zones legend -->
    <div class="zone-legend">
      <div v-for="zone in [
        { label: '正常 0-13', color: severityColors.none },
        { label: '轻度 14-19', color: severityColors.mild },
        { label: '中度 20-28', color: severityColors.moderate },
        { label: '重度 29-63', color: severityColors.severe },
      ]" :key="zone.label" class="zone-item">
        <span class="zone-dot" :style="{ background: zone.color }" />
        <span>{{ zone.label }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.emotion-curve {
  display: flex;
  flex-direction: column;
  padding: 12px 14px;
  height: 100%;
  margin-bottom: 0;
}

.chart-instance {
  width: 100%;
  flex: 1;
  min-height: 120px;
}

.chart-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  color: var(--text-muted);
  font-size: 12px;
  min-height: 120px;
}

.data-count {
  font-size: 11px;
  color: var(--text-muted);
  font-weight: 400;
  margin-left: auto;
}

.zone-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 12px;
  margin-top: 6px;
  font-size: 10px;
  color: var(--text-muted);
  flex-shrink: 0;
}

.zone-item {
  display: flex;
  align-items: center;
  gap: 4px;
}

.zone-dot {
  width: 8px;
  height: 3px;
  border-radius: 2px;
}

.score-list {
  display: none;
}
</style>
