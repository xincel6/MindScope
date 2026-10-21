<script setup lang="ts">
/**
 * 演示素材列表 —— 只出现在 `/demo`
 * ================================================================
 * 为什么不直接用主流程的 `MediaLibrary`：
 *   1. 它的 `onMounted` 会 `loadMediaList()`，把演示列表覆盖成后端真实列表；
 *   2. 它的「上传」会向真实后端 POST 文件，它的删除会调用 DELETE /api/media/{id}。
 * 演示页不该有这个副作用，所以这里只做「点选 → 播放」。
 */
import type { MediaItem } from '@/api/index'

defineProps<{
  items: MediaItem[]
  selectedId: string | null
  playing: boolean
}>()

const emit = defineEmits<{ select: [item: MediaItem] }>()
</script>

<template>
  <div class="demo-media glass-card">
    <div class="section-title section-title--bordered">
      <span>演示素材</span>
      <span class="demo-media-count mono-num">{{ items.length }} 条 · 虚构</span>
    </div>

    <ul class="demo-media-list">
      <li v-for="item in items" :key="item.id">
        <button
          type="button"
          class="demo-media-row"
          :class="{ 'is-active': item.id === selectedId }"
          @click="emit('select', item)"
        >
          <el-icon :size="15" class="row-icon">
            <VideoCamera v-if="item.type === 'video'" />
            <Picture v-else />
          </el-icon>
          <span class="row-name">{{ item.name }}</span>
          <span v-if="playing && item.id === selectedId" class="row-live">播放中</span>
        </button>
      </li>
    </ul>

    <p class="demo-media-note">
      以上条目由前端硬编码生成，没有对应的视频文件。
    </p>
  </div>
</template>

<style scoped>
.demo-media {
  display: flex;
  flex-direction: column;
  padding: 12px 14px;
  height: 100%;
  min-height: 0;
  overflow: hidden;
}

.section-title {
  flex-shrink: 0;
}

.demo-media-count {
  font-size: var(--font-xs);
  font-weight: 400;
  color: var(--text-secondary);
  margin-left: auto;
}

.demo-media-list {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.demo-media-row {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 8px 10px;
  text-align: left;
  background: transparent;
  border: 1px solid transparent;
  border-radius: var(--radius-tag);
  cursor: pointer;
  transition: background var(--motion-press) ease, border-color var(--motion-press) ease;
}

.demo-media-row:hover {
  background: var(--bg-inset);
}

.demo-media-row.is-active {
  background: var(--bg-press);
  border-color: color-mix(in srgb, var(--color-primary) 32%, transparent);
}

.row-icon {
  color: var(--text-secondary);
  flex-shrink: 0;
}

.demo-media-row.is-active .row-icon {
  color: var(--color-primary-text);
}

.row-name {
  flex: 1;
  min-width: 0;
  font-size: var(--font-xs);
  color: var(--text-primary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.demo-media-row.is-active .row-name {
  color: var(--color-primary-text);
  font-weight: 600;
}

.row-live {
  flex-shrink: 0;
  font-size: var(--font-xs);
  color: var(--color-primary-text);
}

.demo-media-note {
  flex-shrink: 0;
  margin: 8px 0 0;
  font-size: var(--font-xs);
  line-height: 1.5;
  color: var(--text-secondary);
}
</style>
