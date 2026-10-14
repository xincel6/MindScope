
<script setup lang="ts">
import { onMounted, computed, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useDashboardStore } from '@/stores/dashboard'
import type { MediaItem } from '@/api/index'

const store = useDashboardStore()
const deletingId = ref<string | null>(null)

const images = computed(() => store.mediaList.filter((m: MediaItem) => m.type === 'image'))
const videos = computed(() => store.mediaList.filter((m: MediaItem) => m.type === 'video'))

/** 后端常为空；缩略图加载失败时回退到视频首帧 */
const videoThumbImgFailed = ref<Record<string, boolean>>({})

function onVideoThumbImgError(item: MediaItem) {
  videoThumbImgFailed.value = { ...videoThumbImgFailed.value, [item.id]: true }
}

/** 使用 Media Fragments 拉取首帧附近画面作为静态预览（相对路径也可） */
function videoThumbSrc(url: string) {
  if (!url) return ''
  return url.includes('#') ? url : `${url}#t=0.1`
}

// 图片加载失败处理
function handleImageError(e: Event, item: MediaItem) {
  console.warn(`图片加载失败: ${item.name}`, (e.target as HTMLImageElement)?.src)
  const target = e.target as HTMLImageElement
  if (target) {
    target.style.display = 'none'
  }
}

onMounted(async () => {
  await store.loadMediaList()
  
  if (store.mediaList.length === 0) {
    store.loadDemoData()
    store.mediaError = ''
  }

  // 调试信息（生产环境可删除）
  console.log('📸 图片素材数量:', images.value.length)
  images.value.forEach(item => {
    console.log(`   ${item.id} | ${item.name} | thumbnail: ${item.thumbnail_url} | url: ${item.url}`)
  })
})

function handleClick(item: MediaItem) {
  if (store.isDemo) {
    store.startDemoAnalysis(item.id)
  } else {
    store.startAnalysis(item.id)
  }
}

async function confirmDelete(item: MediaItem) {
  try {
    await ElMessageBox.confirm(`确定删除「${item.name}」吗？删除后不可恢复。`, '删除素材', {
      confirmButtonText: '删除',
      cancelButtonText: '取消',
      type: 'warning',
      confirmButtonClass: 'el-button--danger',
    })
  } catch {
    return
  }
  deletingId.value = item.id
  try {
    await store.removeMedia(item.id)
    ElMessage.success('已删除')
  } catch (e: unknown) {
    ElMessage.error(e instanceof Error ? e.message : '删除失败')
  } finally {
    deletingId.value = null
  }
}

const typeIcon: Record<string, string> = {
  image: 'Picture',
  video: 'VideoCamera',
}

function onUploadChange(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (file) {
    store.uploadAndAnalyze(file)
    input.value = ''
  }
}
</script>

<template>
  <div class="media-library glass-card">
    <div class="section-title section-title--bordered">
      <span>评估素材库</span>
      <label class="media-upload-btn" :class="{ disabled: store.uploadLoading }">
        <input
          type="file"
          accept="image/*,video/*"
          style="display:none"
          :disabled="store.uploadLoading"
          @change="onUploadChange"
        />
        <el-icon :size="14"><Upload /></el-icon>
        <span>上传</span>
      </label>
    </div>

    <!-- Loading -->
    <el-skeleton v-if="store.mediaLoading" :rows="5" animated />

    <!-- Error -->
    <el-alert
      v-else-if="store.mediaError"
      :title="store.mediaError"
      type="error"
      show-icon
      :closable="false"
    >
      <template #default>
        <el-button size="small" text @click="store.loadMediaList">重试</el-button>
      </template>
    </el-alert>

    <!-- Content -->
    <el-tabs v-else model-value="video" type="border-card" class="media-tabs">
      <!-- 视频 Tab -->
      <el-tab-pane label="视频素材" name="video">
        <div class="media-tab-scroll">
          <div class="media-grid" v-if="videos.length">
            <div
              v-for="item in videos"
              :key="item.id"
              class="media-item"
              :class="{ active: store.selectedMediaId === item.id }"
              @click="handleClick(item)"
            >
            <button
              type="button"
              class="media-delete-btn"
              title="删除"
              :disabled="deletingId === item.id"
              @click.stop="confirmDelete(item)"
            >
              <el-icon :size="14"><Delete /></el-icon>
            </button>
            <div class="media-thumb">
              <img
                v-if="item.thumbnail_url && !videoThumbImgFailed[item.id]"
                :src="item.thumbnail_url"
                alt=""
                @error="onVideoThumbImgError(item)"
              />
              <video
                v-else-if="item.url"
                :src="videoThumbSrc(item.url)"
                muted
                playsinline
                preload="metadata"
                tabindex="-1"
                class="media-thumb-video"
              />
              <el-icon v-else :size="28"><VideoPlay /></el-icon>
              <div class="media-overlay">
                <el-icon v-if="store.selectedMediaId === item.id && store.analyzing" class="is-loading" :size="20"><Loading /></el-icon>
                <el-icon v-else :size="20"><VideoPlay /></el-icon>
              </div>
            </div>
            <div class="media-name">{{ item.name }}</div>
            <div v-if="item.duration" class="media-duration">{{ item.duration }}s</div>
          </div>
          </div>
          <el-empty v-else description="暂无视频素材" />
        </div>
      </el-tab-pane>

      <!-- 图片 Tab（已修复） -->
      <el-tab-pane label="图片素材" name="image">
        <div class="media-tab-scroll">
          <div class="media-grid" v-if="images.length">
            <div
              v-for="item in images"
              :key="item.id"
              class="media-item"
              :class="{ active: store.selectedMediaId === item.id }"
              @click="handleClick(item)"
            >
            <button
              type="button"
              class="media-delete-btn"
              title="删除"
              :disabled="deletingId === item.id"
              @click.stop="confirmDelete(item)"
            >
              <el-icon :size="14"><Delete /></el-icon>
            </button>
            <div class="media-thumb">
              <!-- 优先级：thumbnail_url → url → 图标 -->
              <img 
                v-if="item.thumbnail_url || item.url"
                :src="item.thumbnail_url || item.url"
                alt=""
                @error="handleImageError($event, item)"
              />
              <el-icon v-else :size="28"><Picture /></el-icon>

              <div class="media-overlay">
                <el-icon :size="18"><Search /></el-icon>
              </div>
            </div>
            <div class="media-name">{{ item.name }}</div>
          </div>
          </div>
          <el-empty v-else description="暂无图片素材" />
        </div>
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<style scoped>
.media-library {
  flex: 1;
  min-height: 0;
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: 12px;
}

.media-tabs {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  --el-tabs-header-bg-color: transparent;
  --el-tabs-content-bg-color: transparent;
  --el-border-color-light: var(--border-color);
}

.media-tabs :deep(.el-tabs__header) {
  flex-shrink: 0;
}

.media-tabs :deep(.el-tabs__content) {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  padding: 12px 0 0;
}

.media-tabs :deep(.el-tab-pane) {
  height: 100%;
}

.media-tab-scroll {
  height: 100%;
  max-height: 100%;
  overflow-x: hidden;
  overflow-y: auto;
  padding-right: 4px;
}

.media-tab-scroll::-webkit-scrollbar {
  width: 6px;
}

.media-tab-scroll::-webkit-scrollbar-thumb {
  background: rgba(148, 163, 184, 0.35);
  border-radius: 4px;
}

.media-tab-scroll::-webkit-scrollbar-track {
  background: rgba(0, 0, 0, 0.15);
  border-radius: 4px;
}

.media-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}

.media-item {
  position: relative;
  cursor: pointer;
  border-radius: 8px;
  border: 1px solid var(--border-color);
  overflow: hidden;
  transition: all 0.3s;
  background: rgba(0, 0, 0, 0.2);
}

.media-delete-btn {
  position: absolute;
  top: 4px;
  right: 4px;
  z-index: 4;
  width: 26px;
  height: 26px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  color: #f87171;
  background: rgba(0, 0, 0, 0.55);
  transition: background 0.2s, color 0.2s;
}

.media-delete-btn:hover:not(:disabled) {
  color: #fecaca;
  background: rgba(220, 38, 38, 0.65);
}

.media-delete-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.media-item:hover {
  border-color: var(--accent-cyan);
}

.media-item.active {
  border-color: var(--accent-cyan);
  box-shadow: 0 0 0 2px rgba(56, 189, 248, 0.15);
}

.media-thumb {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 10;
  background: var(--bg-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  overflow: hidden;
}

.media-thumb img,
.media-thumb-video {
  width: 100%;
  height: 100%;
  object-fit: cover;
  background: #1a1a1a;
}

.media-thumb-video {
  display: block;
  pointer-events: none;
}

.media-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  opacity: 0;
  transition: opacity 0.3s;
  color: var(--accent-cyan);
}

.media-item:hover .media-overlay,
.media-item.active .media-overlay {
  opacity: 1;
}

.media-name {
  padding: 6px 8px;
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.media-duration {
  padding: 0 8px 6px;
  font-size: 11px;
  color: var(--text-muted);
  font-family: var(--font-mono);
}

.media-library :deep(.el-tabs__item) {
  color: var(--text-secondary);
  font-size: 13px;
}

.media-upload-btn {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 4px 12px;
  font-size: 12px;
  font-weight: 500;
  color: var(--accent-primary);
  background: rgba(13, 148, 136, 0.08);
  border: 1px solid rgba(13, 148, 136, 0.32);
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.18s, border-color 0.18s;
  white-space: nowrap;
  user-select: none;
}

.media-upload-btn:hover {
  background: rgba(13, 148, 136, 0.16);
  border-color: rgba(13, 148, 136, 0.5);
}

.media-upload-btn.disabled {
  opacity: 0.5;
  pointer-events: none;
}
</style>