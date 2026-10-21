<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'
import { resolveMediaUrl } from '@/api/baseResolver'
import EmptyState from '@/components/common/EmptyState.vue'
import FacePreview from '@/components/center-panel/FacePreview.vue'
import FaceFrameGallery from '@/components/left-panel/FaceFrameGallery.vue'
import MainVideoPlayer from '@/components/center-panel/MainVideoPlayer.vue'

const store = useDashboardStore()
const isVideo = computed(() => store.selectedMedia?.type === 'video')

/**
 * 视频素材可以在这张卡里切「注意力热力图 / 原始视频」：P3 删掉旧播放器后
 * 视频回看能力缺失（能力回退），P4a 把它补回这张 7 列卡里，默认仍显示热力图，
 * 这样 12 栅格与 B/C 行的 `v-if="store.selectedMedia"` 结构完全不变。
 * 图片素材不渲染切换器、也不渲染播放器（只有热力图或空态）。
 */
const tab = ref<'heatmap' | 'video'>('heatmap')
const showVideo = computed(() => isVideo.value && tab.value === 'video')
const videoSrc = computed(() => resolveMediaUrl(store.selectedMedia?.url))

// 换素材时回到默认段：避免停留在一个已经不属于新素材的播放位置。
watch(
  () => store.selectedMediaId,
  () => {
    tab.value = 'heatmap'
  },
)

const title = computed(() => (showVideo.value ? '原始视频' : '注意力热力图'))
const subtitle = computed(() => {
  if (showVideo.value) return '本地回看 · 播放/进度/音量，不参与推理'
  return isVideo.value ? '16×16 · 逐帧采样 · 每 24 帧推理一次' : '16×16 · 单帧图片 · 单次推理'
})
</script>

<template>
  <section class="heatmap-card glass-card">
    <header class="heatmap-head">
      <div class="heatmap-head-text">
        <h2 class="section-title">{{ title }}</h2>
        <p class="heatmap-sub">{{ subtitle }}</p>
      </div>

      <div v-if="isVideo" class="heatmap-seg" role="tablist" aria-label="注意力热力图 / 原始视频">
        <button
          type="button"
          role="tab"
          class="heatmap-seg-btn"
          :class="{ 'is-active': tab === 'heatmap' }"
          :aria-selected="tab === 'heatmap'"
          @click="tab = 'heatmap'"
        >
          注意力热力图
        </button>
        <button
          type="button"
          role="tab"
          class="heatmap-seg-btn"
          :class="{ 'is-active': tab === 'video' }"
          :aria-selected="tab === 'video'"
          @click="tab = 'video'"
        >
          原始视频
        </button>
      </div>
      <span v-else-if="store.heatmapData.length" class="heatmap-state">模型输出</span>
    </header>

    <template v-if="showVideo">
      <MainVideoPlayer :src="videoSrc" :label="store.selectedMedia?.name" />
      <p class="heatmap-hint">这里回看原始视频；切回「注意力热力图」查看模型输出。</p>
    </template>

    <div v-else-if="!store.faceImageData" class="heatmap-empty">
      <EmptyState
        compact
        icon="Aim"
        title="尚无热力图"
        description="开始分析后，这里会显示模型对 16×16 面部区域的注意力分布。"
        hint="没有真实推理结果时不绘制占位热力图"
      />
    </div>

    <template v-else>
      <FacePreview embedded :size="280" />
      <FaceFrameGallery v-if="isVideo" layout="compact" embedded />
    </template>
  </section>
</template>

<style scoped>
.heatmap-card {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  min-width: 0;
}

.heatmap-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-2);
  flex-wrap: wrap;
}

.heatmap-head .section-title {
  margin-bottom: 0;
}

.heatmap-head-text {
  min-width: 0;
}

.heatmap-sub {
  margin: var(--space-1) 0 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.heatmap-state {
  flex-shrink: 0;
  padding: 2px 8px;
  border-radius: var(--radius-pill);
  background: var(--bg-inset);
  color: var(--text-secondary);
  font-size: var(--font-xs);
}

.heatmap-seg {
  display: inline-flex;
  flex: 0 0 auto;
  gap: 2px;
  padding: 2px;
  background: var(--bg-inset);
  border-radius: var(--radius-control);
}

.heatmap-seg-btn {
  padding: 4px 10px;
  border: none;
  border-radius: var(--radius-tag);
  background: transparent;
  color: var(--text-secondary);
  font-size: var(--font-xs);
  white-space: nowrap;
  cursor: pointer;
  transition: background var(--motion-press) ease, color var(--motion-press) ease;
}

.heatmap-seg-btn:hover {
  color: var(--color-primary-text);
}

.heatmap-seg-btn.is-active {
  background: var(--bg-card);
  color: var(--text-primary);
  box-shadow: var(--shadow-card);
}

.heatmap-seg-btn:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
}

.heatmap-hint {
  margin: 0;
  font-size: var(--font-xs);
  line-height: 1.6;
  color: var(--text-secondary);
}

.heatmap-empty {
  flex: 1;
  min-height: 220px;
  display: flex;
  align-items: center;
  justify-content: center;
}
</style>
