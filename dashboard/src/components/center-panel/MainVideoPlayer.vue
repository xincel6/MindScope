<script setup lang="ts">
/**
 * 原始视频回看播放器（P4a 重写）
 * ================================================================
 * P3 删掉旧 `MainVideoPlayer.vue` 的 WS / 摄像头 / 录制逻辑后，这个文件只剩一个 `<div />`
 * 空壳，导致「选中视频素材后工作台没有任何播放器」——能力回退。这里把它重写成
 * **纯展示型播放器**，只做四件事：播放/暂停、拖进度、音量/静音、显示时长。
 *
 * 边界（不要往这里加东西）：
 *   · 没有任何 WebSocket 逻辑：分析流在 `composables/useAnalysisSocket.ts`；
 *   · 不碰 store：素材地址由父组件用 `resolveMediaUrl()` 解析后通过 `src` 传入；
 *   · 不做抽帧/推理：那是服务端 + AttentionHeatmapCard 的事。
 */
import { onBeforeUnmount, ref, watch } from 'vue'
import { Mute, VideoPause, VideoPlay } from '@element-plus/icons-vue'

const props = defineProps<{
  /** 已解析成绝对地址（或 blob:）的视频地址 */
  src: string
  /** 无障碍名称，例如素材文件名 */
  label?: string
}>()

const videoRef = ref<HTMLVideoElement | null>(null)
const playing = ref(false)
const currentTime = ref(0)
const duration = ref(0)
const volume = ref(1)
const muted = ref(false)
const errorText = ref('')

function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return '0:00'
  const total = Math.floor(seconds)
  const minutes = Math.floor(total / 60)
  const rest = total % 60
  return `${minutes}:${String(rest).padStart(2, '0')}`
}

async function togglePlay() {
  const video = videoRef.value
  if (!video) return
  if (video.paused) {
    try {
      await video.play()
    } catch {
      errorText.value = '无法播放该视频：浏览器可能不支持该编码，或自动播放被拦截。'
    }
  } else {
    video.pause()
  }
}

function onSeek(event: Event) {
  const video = videoRef.value
  const target = Number((event.target as HTMLInputElement).value)
  if (!video || !Number.isFinite(target)) return
  video.currentTime = target
  currentTime.value = target
}

function onVolumeInput(event: Event) {
  const video = videoRef.value
  const next = Number((event.target as HTMLInputElement).value)
  if (!video || !Number.isFinite(next)) return
  video.volume = Math.min(1, Math.max(0, next))
  volume.value = video.volume
  // 拖到 0 等价于静音；从 0 拖回来自动解除静音，避免「看起来没声音」。
  const nextMuted = video.volume === 0
  video.muted = nextMuted
  muted.value = nextMuted
}

function toggleMute() {
  const video = videoRef.value
  if (!video) return
  video.muted = !video.muted
  muted.value = video.muted
}

function onLoadedMetadata() {
  const video = videoRef.value
  if (!video) return
  duration.value = Number.isFinite(video.duration) ? video.duration : 0
  volume.value = video.volume
  muted.value = video.muted
}

function onVolumeChange() {
  const video = videoRef.value
  if (!video) return
  volume.value = video.volume
  muted.value = video.muted
}

function onTimeUpdate() {
  const video = videoRef.value
  if (video) currentTime.value = video.currentTime
}

function onEnded() {
  playing.value = false
}

// 换素材时把播放器状态归零：同一个组件实例会被不同素材复用。
watch(
  () => props.src,
  () => {
    currentTime.value = 0
    duration.value = 0
    errorText.value = ''
    playing.value = false
  },
)

onBeforeUnmount(() => {
  videoRef.value?.pause()
})
</script>

<template>
  <div class="video-player">
    <div class="player-stage">
      <video
        ref="videoRef"
        class="player-video"
        :src="src"
        :aria-label="label || '原始视频'"
        preload="metadata"
        playsinline
        @click="togglePlay"
        @play="playing = true"
        @pause="playing = false"
        @ended="onEnded"
        @timeupdate="onTimeUpdate"
        @loadedmetadata="onLoadedMetadata"
        @volumechange="onVolumeChange"
        @error="errorText = '无法加载该视频：文件可能已被删除，或格式不受支持。'"
      />
      <p v-if="errorText" class="player-error" role="status">{{ errorText }}</p>
    </div>

    <div class="player-controls">
      <button
        type="button"
        class="player-btn"
        :aria-label="playing ? '暂停' : '播放'"
        :title="playing ? '暂停' : '播放'"
        @click="togglePlay"
      >
        <el-icon :size="16">
          <VideoPause v-if="playing" />
          <VideoPlay v-else />
        </el-icon>
      </button>

      <span class="player-time mono-num">{{ formatTime(currentTime) }}</span>

      <input
        class="player-range player-range--seek"
        type="range"
        min="0"
        :max="duration || 0"
        step="0.01"
        :value="currentTime"
        aria-label="播放进度"
        @input="onSeek"
      />

      <span class="player-time mono-num">{{ formatTime(duration) }}</span>

      <button
        type="button"
        class="player-btn player-btn--mute"
        :class="{ 'is-on': muted }"
        :aria-pressed="muted"
        :aria-label="muted ? '取消静音' : '静音'"
        :title="muted ? '取消静音' : '静音'"
        @click="toggleMute"
      >
        <el-icon :size="16"><Mute /></el-icon>
      </button>

      <input
        class="player-range player-range--volume"
        type="range"
        min="0"
        max="1"
        step="0.01"
        :value="muted ? 0 : volume"
        aria-label="音量"
        @input="onVolumeInput"
      />
    </div>
  </div>
</template>

<style scoped>
.video-player {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  min-width: 0;
}

.player-stage {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  background: var(--bg-inset);
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
}

.player-video {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: var(--bg-inset);
  cursor: pointer;
}

.player-error {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0;
  padding: var(--space-4);
  background: var(--bg-inset);
  color: var(--text-secondary);
  font-size: var(--font-xs);
  line-height: 1.6;
  text-align: center;
}

.player-controls {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-3);
  background: var(--bg-inset);
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
}

.player-btn {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  padding: 0;
  border: 1px solid var(--border);
  border-radius: var(--radius-pill);
  background: var(--bg-card);
  color: var(--text-secondary);
  cursor: pointer;
  transition: color var(--motion-press) ease, border-color var(--motion-press) ease;
}

.player-btn:hover {
  color: var(--color-primary-text);
  border-color: var(--color-primary);
}

.player-btn:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
}

.player-btn.is-on {
  color: var(--color-primary-text);
  border-color: var(--color-primary);
  background: var(--bg-press);
}

.player-time {
  flex: 0 0 auto;
  color: var(--text-secondary);
  font-size: var(--font-xs);
  font-variant-numeric: tabular-nums;
}

.player-range {
  flex: 1 1 auto;
  min-width: 0;
  height: 4px;
  appearance: none;
  -webkit-appearance: none;
  background: var(--bg-skeleton);
  border-radius: var(--radius-pill);
  outline: none;
  cursor: pointer;
}

.player-range--volume {
  flex: 0 0 72px;
}

.player-range::-webkit-slider-thumb {
  appearance: none;
  -webkit-appearance: none;
  width: 12px;
  height: 12px;
  border: none;
  border-radius: var(--radius-pill);
  background: var(--color-primary);
  cursor: pointer;
}

.player-range::-moz-range-thumb {
  width: 12px;
  height: 12px;
  border: none;
  border-radius: var(--radius-pill);
  background: var(--color-primary);
  cursor: pointer;
}

.player-range:focus-visible {
  box-shadow: var(--focus-ring);
}

@media (max-width: 480px) {
  .player-range--volume {
    flex: 0 0 48px;
  }
}
</style>
