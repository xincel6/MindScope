<script setup lang="ts">
import { computed } from 'vue'
import EmptyState from '@/components/common/EmptyState.vue'
import {
  useDashboardStore,
  getSeverity,
  severityLabels,
  type SeverityLevel,
} from '@/stores/dashboard'

const store = useDashboardStore()
const levelOrder: SeverityLevel[] = ['none', 'mild', 'moderate', 'severe']

const isVideo = computed(() => store.selectedMedia?.type === 'video')
const counts = computed<Record<SeverityLevel, number>>(() => {
  const bucket: Record<SeverityLevel, number> = { none: 0, mild: 0, moderate: 0, severe: 0 }
  for (const point of store.bdiHistory) {
    bucket[getSeverity(point.score)] += 1
  }
  return bucket
})
const total = computed(() => store.bdiHistory.length)
const hasFrames = computed(() => total.value > 0)
/** 视频帧数 ≥2 才画帧级直方条；单帧/图片画四档刻度尺，避免把 1 帧说成「分布」 */
const showBars = computed(() => isVideo.value && total.value >= 2)
const markerLeft = computed(() => `${Math.min(Math.max(store.currentScore, 0), 63) / 63 * 100}%`)

const zones: { level: SeverityLevel; width: string }[] = [
  { level: 'none', width: '22.2%' },
  { level: 'mild', width: '9.5%' },
  { level: 'moderate', width: '14.3%' },
  { level: 'severe', width: '54%' },
]
</script>

<template>
  <section class="severity-card glass-card">
    <header class="severity-head">
      <h2 class="section-title">严重度分布</h2>
      <p class="severity-sub">BDI-II 0–63 · 四档</p>
    </header>

    <div v-if="!hasFrames" class="severity-empty">
      <EmptyState
        compact
        icon="DataAnalysis"
        title="开始分析后显示分布"
        description="视频按帧统计四档占比；图片显示单次评分的档位位置。"
      />
    </div>

    <template v-else-if="showBars">
      <div class="severity-bars" role="img" aria-label="视频帧严重度分布">
        <span
          v-for="level in levelOrder"
          :key="level"
          class="severity-bar"
          :class="`severity-bar--${level}`"
          :style="{ width: `${(counts[level] / total) * 100}%` }"
          :title="`${severityLabels[level]} ${counts[level]} 帧`"
        />
      </div>
      <ul class="severity-legend">
        <li v-for="level in levelOrder" :key="level" class="severity-legend-item">
          <span class="severity-dot" :class="`severity-dot--${level}`" />
          <span class="severity-name">{{ severityLabels[level] }}</span>
          <span class="severity-count mono-num">{{ counts[level] }} 帧</span>
        </li>
      </ul>
      <p class="severity-foot">
        共 {{ total }} 帧 · 最新帧
        <strong class="mono-num" :class="`severity-text--${store.severity}`">{{ store.currentScore }} 分</strong>
        （{{ store.severityLabel }}）
      </p>
    </template>

    <template v-else>
      <div class="severity-score">
        <strong class="severity-score-value mono-num">{{ store.currentScore }}</strong>
        <span class="severity-score-label">{{ store.severityLabel }} · BDI-II</span>
      </div>
      <div class="severity-scale">
        <div class="severity-zones">
          <span
            v-for="zone in zones"
            :key="zone.level"
            class="severity-zone"
            :class="`severity-zone--${zone.level}`"
            :style="{ width: zone.width }"
          />
          <span class="severity-marker" :style="{ left: markerLeft }" />
        </div>
        <div class="severity-zones-labels">
          <span v-for="zone in zones" :key="zone.level" :style="{ width: zone.width }">
            {{ severityLabels[zone.level] }}
          </span>
        </div>
        <div class="severity-endpoints">
          <span>0</span>
          <span>63</span>
        </div>
      </div>
      <p class="severity-foot">当前为单次推理结果，不构成帧级分布。</p>
    </template>
  </section>
</template>

<style scoped>
.severity-card {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  min-width: 0;
}

.severity-head .section-title {
  margin-bottom: 0;
}

.severity-sub {
  margin: var(--space-1) 0 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.severity-empty {
  flex: 1;
  min-height: 180px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.severity-bars {
  display: flex;
  width: 100%;
  height: 14px;
  overflow: hidden;
  border-radius: var(--radius-pill);
  background: var(--bg-inset);
}

.severity-bar {
  height: 100%;
}

.severity-bar--none,
.severity-zone--none,
.severity-dot--none {
  background: var(--severity-none);
}

.severity-bar--mild,
.severity-zone--mild,
.severity-dot--mild {
  background: var(--severity-mild);
}

.severity-bar--moderate,
.severity-zone--moderate,
.severity-dot--moderate {
  background: var(--severity-moderate);
}

.severity-bar--severe,
.severity-zone--severe,
.severity-dot--severe {
  background: var(--severity-severe);
}

.severity-legend {
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  margin: 0;
}

.severity-legend-item {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.severity-dot {
  width: 8px;
  height: 8px;
  border-radius: var(--radius-pill);
  flex-shrink: 0;
}

.severity-name {
  flex: 1;
  min-width: 0;
}

.severity-count {
  color: var(--text-primary);
}

.severity-foot {
  margin: 0;
  font-size: var(--font-xs);
  line-height: 1.55;
  color: var(--text-secondary);
}

.severity-score {
  display: flex;
  align-items: baseline;
  gap: var(--space-2);
}

.severity-score-value {
  font-size: var(--font-metric);
  line-height: 1;
  color: var(--text-primary);
}

.severity-score-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.severity-scale {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.severity-zones {
  position: relative;
  display: flex;
  width: 100%;
  height: 10px;
  overflow: visible;
  border-radius: var(--radius-pill);
}

.severity-zone:first-child {
  border-top-left-radius: var(--radius-pill);
  border-bottom-left-radius: var(--radius-pill);
}

.severity-zone:last-of-type {
  border-top-right-radius: var(--radius-pill);
  border-bottom-right-radius: var(--radius-pill);
}

.severity-marker {
  position: absolute;
  top: -3px;
  width: 3px;
  height: 16px;
  border-radius: var(--radius-pill);
  background: var(--text-primary);
  transform: translateX(-50%);
}

.severity-zones-labels,
.severity-endpoints {
  display: flex;
  width: 100%;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.severity-zones-labels span {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  padding-right: 2px;
}

.severity-endpoints {
  justify-content: space-between;
}

.severity-text--none { color: var(--severity-none-text); }
.severity-text--mild { color: var(--severity-mild-text); }
.severity-text--moderate { color: var(--severity-moderate-text); }
.severity-text--severe { color: var(--severity-severe-text); }
</style>
