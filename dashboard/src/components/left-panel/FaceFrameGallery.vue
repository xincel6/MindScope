<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { Picture } from '@element-plus/icons-vue'
import { useDashboardStore, type FaceFrameSnapshot } from '@/stores/dashboard'
import { analyzeFaceBase64 } from '@/api/index'

withDefaults(defineProps<{
  layout?: 'side' | 'compact'
  /** 嵌进工作台热力卡时不重复白卡 / 边框 / 内边距 */
  embedded?: boolean
}>(), {
  layout: 'side',
  embedded: false,
})

const store = useDashboardStore()
const LS_KEY = 'face-gallery-collapsed'

const collapsed = ref(false)
const selectedKey = ref<string | null>(null)
const singleLoading = ref(false)
// P5 T1：base64 帧理论上不会 404，但损坏/解码失败时同样切成中性占位，
// 避免 alt（此处为空）或破图图标破坏 1:1 缩略图栅格。
const brokenFrames = ref<Set<string>>(new Set())

function markFrameBroken(key: string) {
  brokenFrames.value.add(key)
}

onMounted(() => {
  collapsed.value = localStorage.getItem(LS_KEY) === '1'
})

function toggleCollapse() {
  collapsed.value = !collapsed.value
  localStorage.setItem(LS_KEY, collapsed.value ? '1' : '0')
}

function clearFrames() {
  store.clearFaceFrameHistory()
  selectedKey.value = null
  brokenFrames.value.clear()
}

watch(
  () => store.faceFrameHistory.length,
  (n) => {
    if (n === 0) selectedKey.value = null
  },
)

function selectItem(item: FaceFrameSnapshot) {
  selectedKey.value = item.key
  store.$patch({ faceImageData: item.b64 })
}

async function runSingleFrameDetect() {
  const item = store.faceFrameHistory.find((x) => x.key === selectedKey.value)
  if (!item?.b64) {
    ElMessage.warning('请先点击选择一个人脸帧')
    return
  }
  singleLoading.value = true
  try {
    const res = await analyzeFaceBase64(item.b64)
    const payload = {
      bdi_score: res.bdi_score,
      inference_time_ms: res.inference_time_ms,
      heatmap_data: res.heatmap_data,
      aligned_face_b64: item.b64,
    }
    if (store.selectedMedia?.type === 'video') {
      store.switchVideoAnalysisToSingleFaceImage(payload, {
        frameId: item.frameId,
        videoName: store.selectedMedia.name,
      })
      ElMessage.success(
        `已结束视频流式检测，主界面已切换为抽帧图片检测 · BDI ≈ ${res.bdi_score.toFixed(1)}`,
      )
    } else {
      store.applySingleFrameAnalysisResult(payload)
      ElMessage.success(`单帧检测完成 · BDI ≈ ${res.bdi_score.toFixed(1)}`)
    }
  } catch (e: unknown) {
    ElMessage.error(e instanceof Error ? e.message : '单帧检测失败')
  } finally {
    singleLoading.value = false
  }
}
</script>

<template>
  <div class="face-gallery-dock" :class="{ collapsed, compact: layout === 'compact' }">
    <button
      v-if="layout === 'side'"
      type="button"
      class="collapse-toggle"
      :title="collapsed ? '展开人脸帧' : '收起'"
      @click="toggleCollapse"
    >
      <el-icon :size="16">
        <DArrowRight v-if="collapsed" />
        <DArrowLeft v-else />
      </el-icon>
    </button>

    <div
      v-show="layout === 'compact' || !collapsed"
      class="face-gallery-inner"
      :class="embedded ? 'face-gallery-inner--embedded' : 'glass-card glass-card--flat'"
    >
      <div class="fg-header">
        <span class="fg-title">关键人脸帧</span>
        <div class="fg-header-actions">
          <span v-if="store.analyzing" class="fg-badge">检测中</span>
          <button
            v-if="store.faceFrameHistory.length"
            type="button"
            class="fg-clear"
            title="清空人脸帧列表"
            @click="clearFrames"
          >
            清空
          </button>
        </div>
      </div>
      <p v-if="layout === 'side'" class="fg-desc">
        视频分析中会累积关键帧。对视频帧做「单帧检测」会结束流式分析并切到主界面的抽帧图片结果。
      </p>

      <div v-if="!store.faceFrameHistory.length" class="fg-empty">
        <el-icon :size="22"><User /></el-icon>
        <span>分析后将显示人脸帧</span>
      </div>

      <el-scrollbar v-else class="fg-scroll" :class="{ 'fg-scroll--horizontal': layout === 'compact' }">
        <div class="fg-grid" :class="{ 'fg-grid--horizontal': layout === 'compact' }">
          <button
            v-for="item in store.faceFrameHistory"
            :key="item.key"
            type="button"
            class="fg-thumb"
            :class="{ active: selectedKey === item.key }"
            @click="selectItem(item)"
          >
            <img
              v-if="!brokenFrames.has(item.key)"
              :src="`data:image/jpeg;base64,${item.b64}`"
              alt=""
              @error="markFrameBroken(item.key)"
            />
            <span
              v-else
              class="thumb-fallback thumb-fallback--frame"
              role="img"
              :aria-label="`第 ${item.frameId} 帧：预览不可用`"
            >
              <el-icon :size="18"><Picture /></el-icon>
              <span class="thumb-fallback__text">预览不可用</span>
            </span>
            <span class="fg-meta">#{{ item.frameId }} · {{ item.score }}</span>
          </button>
        </div>
      </el-scrollbar>

      <el-button
        class="fg-action"
        type="primary"
        size="small"
        plain
        :loading="singleLoading"
        :disabled="!selectedKey"
        @click="runSingleFrameDetect"
      >
        单帧检测
      </el-button>
    </div>
  </div>
</template>

<style scoped>
.face-gallery-dock.compact {
  width: 100%;
  flex-shrink: 0;
  max-height: 180px;
}

.face-gallery-dock.compact .face-gallery-inner {
  padding: 8px 10px;
  gap: 6px;
}

.face-gallery-dock.compact .fg-empty {
  min-height: 60px;
  flex-direction: row;
  gap: 8px;
}

.fg-scroll--horizontal :deep(.el-scrollbar__view) {
  display: flex;
}

.fg-grid--horizontal {
  flex-direction: row !important;
  gap: 6px !important;
}

.fg-grid--horizontal .fg-thumb {
  width: 64px;
  flex-shrink: 0;
}

.fg-grid--horizontal .fg-thumb img {
  aspect-ratio: 1;
  height: 64px;
  width: 64px;
}

.fg-grid--horizontal .fg-meta {
  font-size: var(--font-xs);
  padding: 2px 4px;
}

.face-gallery-dock {
  flex-shrink: 0;
  display: flex;
  flex-direction: row;
  align-items: stretch;
  min-height: 0;
  transition: width 0.22s ease;
  width: 200px;
}

.face-gallery-dock.collapsed {
  width: 36px;
}

.collapse-toggle {
  flex-shrink: 0;
  width: 32px;
  margin-right: 4px;
  align-self: stretch;
  border: 1px solid var(--border);
  border-radius: var(--radius-tag);
  background: var(--bg-inset);
  color: var(--color-primary-text);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.2s;
}

.collapse-toggle:hover {
  background: var(--bg-press);
}

.face-gallery-inner {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  padding: 10px;
  gap: 8px;
  overflow: hidden;
}

.face-gallery-inner--embedded {
  padding: var(--space-2) 0 0;
}

.fg-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.fg-header-actions {
  display: flex;
  align-items: center;
  gap: 6px;
}

.fg-clear {
  padding: 2px 8px;
  font-size: var(--font-xs);
  color: var(--severity-severe-text);
  background: var(--color-danger-soft);
  border: 1px solid color-mix(in srgb, var(--color-danger) 28%, transparent);
  border-radius: var(--radius-tag);
  cursor: pointer;
  transition: background 0.2s, color 0.2s;
}

.fg-clear:hover {
  color: var(--severity-severe-text);
  background: color-mix(in srgb, var(--color-danger) 14%, transparent);
}

.fg-title {
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-secondary);
}

.fg-badge {
  font-size: var(--font-xs);
  color: var(--color-danger);
  animation: pulse-soft 1.2s ease-in-out infinite;
}

@keyframes pulse-soft {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.55;
  }
}

.fg-desc {
  margin: 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  line-height: 1.45;
}

.fg-empty {
  flex: 1;
  min-height: 100px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: var(--text-secondary);
  font-size: var(--font-xs);
  text-align: center;
  padding: 12px 4px;
}

.fg-scroll {
  flex: 1;
  min-height: 80px;
}

.fg-grid {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding-right: 4px;
}

.fg-thumb {
  position: relative;
  border: 2px solid transparent;
  border-radius: var(--radius-tag);
  overflow: hidden;
  padding: 0;
  cursor: pointer;
  background: var(--bg-inset);
  transition: border-color 0.2s, box-shadow 0.2s;
}

.fg-thumb:hover {
  border-color: color-mix(in srgb, var(--color-primary) 35%, transparent);
}

.fg-thumb.active {
  border-color: var(--color-primary);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--color-primary) 20%, transparent);
}

.fg-thumb:focus-visible,
.collapse-toggle:focus-visible,
.fg-clear:focus-visible {
  outline: 2px solid var(--color-primary-text);
  outline-offset: 2px;
}

.fg-thumb img {
  display: block;
  width: 100%;
  aspect-ratio: 1;
  object-fit: cover;
}

.fg-meta {
  display: block;
  font-size: var(--font-xs);
  color: var(--bg-card);
  padding: 4px 6px;
  background: color-mix(in srgb, var(--text-primary) 55%, transparent);
  text-align: center;
  font-family: var(--font-mono, monospace);
}

.fg-action {
  width: 100%;
  margin-top: auto;
}
</style>
