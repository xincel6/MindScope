<script setup lang="ts">
import { computed } from 'vue'
import { useDashboardStore, severityTextColors } from '@/stores/dashboard'
import { chartTheme } from '@/utils/chartTheme'
import { usePrefersReducedMotion } from '@/composables/usePrefersReducedMotion'
import EmptyState from '@/components/common/EmptyState.vue'

const store = useDashboardStore()
const reducedMotion = usePrefersReducedMotion()

const hasData = computed(() => store.bdiHistory.length > 0)

/**
 * 单点（图片素材）判定
 *
 * ★ 后端的图片分析只做**一次推理、只推一帧**（`services/frame_processor.py::_process_image`），
 *   所以这里只会拿到 1 个分数。ECharts 用 1 个点画折线只会得到一个孤立圆点，
 *   看起来像"图没画出来"。
 *   → 这种情况下把点复制成两个（同分），画成一条**水平直线**：
 *     图片没有"随帧变化"，直线才是诚实的表达（与鸿蒙端 `EmotionCurveCard` 同口径）。
 */
const isSinglePoint = computed(() => store.bdiHistory.length === 1)

const option = computed(() => {
  const rawScores = store.bdiHistory.map((p) => p.score)
  const rawTimes = store.bdiHistory.map((p) => p.time)

  const scores = isSinglePoint.value ? [rawScores[0], rawScores[0]] : rawScores
  const times = isSinglePoint.value ? [rawTimes[0], ''] : rawTimes

  // Build per-point colors from severity（点标记与图例均用文字态色，保证深浅可辨）
  const colors = scores.map((s) => {
    if (s > 28) return severityTextColors.severe
    if (s > 19) return severityTextColors.moderate
    if (s > 13) return severityTextColors.mild
    return severityTextColors.none
  })

  return {
    backgroundColor: 'transparent',
    // 系统减弱动效时关闭 ECharts 入场动画（CSS reduce 管不到 canvas）
    animation: !reducedMotion.value,
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
      <span v-if="hasData" class="data-count">
        {{ isSinglePoint ? '(单帧图片 · 水平直线)' : `(${store.bdiHistory.length} 点)` }}
      </span>
    </div>

    <div v-if="!hasData" class="chart-empty">
      <EmptyState
        compact
        icon="TrendCharts"
        title="暂无评分曲线"
        description="上传素材并开始分析后，这里会按帧实时绘出 BDI-II 分数。"
        hint="图片素材只做 1 次推理，会画成一条水平直线。"
      />
    </div>

    <VChart v-else :option="option" autoresize class="chart-instance" />

    <!-- 单帧图片说明：只有一次推理，曲线是水平直线，不是"图没画出来" -->
    <p v-if="isSinglePoint" class="single-point-note">
      图片素材只做 1 次推理，分数恒定为 {{ store.bdiHistory[0]?.score }}，因此曲线是水平直线。
    </p>

    <!-- Score list: always visible when data exists -->
    <div v-if="hasData" class="score-list">
      <span
        v-for="(p, i) in store.bdiHistory"
        :key="i"
        class="score-chip"
        :style="{ color: p.score > 28 ? severityTextColors.severe : p.score > 19 ? severityTextColors.moderate : p.score > 13 ? severityTextColors.mild : severityTextColors.none }"
      >{{ p.score }}</span>
    </div>

    <!-- Severity zones legend -->
    <div class="zone-legend">
      <div v-for="zone in [
        { label: '正常 0-13', color: severityTextColors.none },
        { label: '轻度 14-19', color: severityTextColors.mild },
        { label: '中度 20-28', color: severityTextColors.moderate },
        { label: '重度 29-63', color: severityTextColors.severe },
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
  min-height: 120px;
}

.data-count {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-weight: 400;
  margin-left: auto;
}

.single-point-note {
  margin: 6px 0 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  line-height: 1.5;
}

.zone-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 12px;
  margin-top: 6px;
  font-size: var(--font-xs);
  color: var(--text-secondary);
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
  border-radius: var(--radius-pill);
}

.score-list {
  display: none;
}
</style>
