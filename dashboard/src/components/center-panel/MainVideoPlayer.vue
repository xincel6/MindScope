<script setup lang="ts">
import { ref, watch, computed, onUnmounted, nextTick } from 'vue'
import { ElMessage } from 'element-plus'
import { useDashboardStore } from '@/stores/dashboard'
import { useWebSocket } from '@/composables/useWebSocket'
import { resolveMediaUrl } from '@/api/baseResolver'

const store = useDashboardStore()
const videoRef = ref<HTMLVideoElement | null>(null)

function goBack() {
  store.exitMainDisplayKeepFaceFrames()
}

function startUpload(file: File) {
  store.uploadAndAnalyze(file)
}

const showMainImage = computed(() => {
  if (store.singleFaceImageMode && store.singleFaceImageUrl) return true
  return store.selectedMedia?.type === 'image' && !!store.selectedMedia?.url
})

const mainImageSrc = computed(() => {
  if (store.singleFaceImageMode && store.singleFaceImageUrl) return store.singleFaceImageUrl
  return resolveMediaUrl(store.selectedMedia?.url)
})

const showMainVideo = computed(
  () =>
    !!store.selectedMedia &&
    store.selectedMedia.type === 'video' &&
    !store.singleFaceImageMode,
)

const mainMediaTitle = computed(
  () => store.singleFaceLabel || store.selectedMedia?.name || '',
)

const { wsStatus, ensureConnected, disconnect, send } = useWebSocket({
  onMessage(data) {
    store.handleWsMessage(data)
    // 后端发完最后一帧后还会补一条 vlm_analysis + done，收到 done 才算真正结束：
    // 这时才断开，既不会把 vlm 结果挡在门外，也不会空占一条连接。
    if (data?.type === 'done' || data?.type === 'error') {
      disconnect()
    }
  },
  onOpen() {
    store.setWsConnected(true)
  },
  onClose() {
    store.setWsConnected(false)
  },
  onError() {
    store.setWsConnected(false)
  },
  // 只有分析进行中才值得自动重连（分析结束/用户返回后不再重连）
  shouldReconnect: () => store.analyzing && !store.isDemo,
})

/** 本次连接是否已经把 media id 发给后端（重连后需要重发） */
let initSent = false

function sendInitIfNeeded(): boolean {
  if (initSent || !store.selectedMediaId) return false
  if (!send({ id: store.selectedMediaId })) return false
  initSent = true
  return true
}

watch(wsStatus, (v) => {
  if (store.isDemo) return
  store.setWsConnected(v === 'connected')
  if (v === 'connected') {
    // 断线重连后后端是一条新连接，必须重新告知要分析哪个素材
    if (store.analyzing) sendInitIfNeeded()
  } else {
    initSent = false
  }
})

// 按需连接：每次「开始分析」才建连，分析结束/退出主界面就断开。
// 触发信号用 analysisRunId 而不是 analyzing —— 后者在同一素材再点一次时不会变化，
// 会导致 watch 不触发、点了没反应。
watch(
  [() => store.analysisRunId, () => store.isDemo],
  async ([runId, demo]) => {
    if (demo || !runId) return // 演示模式全部由前端模拟，不走后端连接
    const mediaId = store.selectedMediaId
    if (!mediaId) return
    // 后端一条连接只服务一个分析任务：上一次的 id 已经发过了就换新连接
    if (initSent) disconnect()
    const ok = await ensureConnected()
    // 握手期间用户可能已经返回或切了素材，别把过期请求发出去
    if (!ok || store.analysisRunId !== runId || store.selectedMediaId !== mediaId) return
    sendInitIfNeeded()
  },
  { immediate: true },
)

// 退出主界面/清空素材：分析已中止，连接不必再挂着
watch(
  [() => store.analyzing, () => store.selectedMediaId],
  ([isAnalyzing, mediaId]) => {
    if (store.isDemo) return
    if (!isAnalyzing && !mediaId) disconnect()
  },
)

watch(() => store.selectedMedia, (media) => {
  if (!videoRef.value) return
  if (media?.type === 'video' && media.url) {
    videoRef.value.src = resolveMediaUrl(media.url)
    videoRef.value.load()
  } else {
    videoRef.value.pause()
    videoRef.value.removeAttribute('src')
  }
})

function onVideoChange(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (file) {
    startUpload(file)
    input.value = ''
  }
}

function onImageChange(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (file) {
    startUpload(file)
    input.value = ''
  }
}

// --- 在线拍照 ---
const cameraDialogVisible = ref(false)
const cameraVideoRef = ref<HTMLVideoElement | null>(null)
let cameraStream: MediaStream | null = null

function stopCameraStream() {
  cameraStream?.getTracks().forEach((t) => t.stop())
  cameraStream = null
  if (cameraVideoRef.value) {
    cameraVideoRef.value.srcObject = null
  }
}

async function openCameraDialog() {
  if (!navigator.mediaDevices?.getUserMedia) {
    ElMessage.error('当前浏览器不支持摄像头采集')
    return
  }
  cameraDialogVisible.value = true
  await nextTick()
  stopCameraStream()
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } },
    })
    if (cameraVideoRef.value) {
      cameraVideoRef.value.srcObject = cameraStream
      await cameraVideoRef.value.play()
    }
  } catch (e: unknown) {
    const name = e && typeof e === 'object' && 'name' in e ? String((e as DOMException).name) : ''
    ElMessage.error(name === 'NotAllowedError' ? '请允许使用摄像头' : '无法打开摄像头')
    cameraDialogVisible.value = false
  }
}

function onCameraDialogClosed() {
  stopCameraStream()
}

function capturePhoto() {
  const v = cameraVideoRef.value
  if (!v?.videoWidth) {
    ElMessage.warning('请等待画面就绪后再拍照')
    return
  }
  const canvas = document.createElement('canvas')
  canvas.width = v.videoWidth
  canvas.height = v.videoHeight
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  ctx.drawImage(v, 0, 0)
  canvas.toBlob(
    (blob) => {
      if (!blob) return
      const file = new File([blob], `在线拍照-${Date.now()}.jpg`, { type: 'image/jpeg' })
      cameraDialogVisible.value = false
      stopCameraStream()
      startUpload(file)
    },
    'image/jpeg',
    0.92,
  )
}

// --- 在线录制 ---
const recordDialogVisible = ref(false)
const recordVideoRef = ref<HTMLVideoElement | null>(null)
const isRecording = ref(false)

let recordStream: MediaStream | null = null
let mediaRecorder: MediaRecorder | null = null
let recordChunks: Blob[] = []

function stopRecordStream() {
  recordStream?.getTracks().forEach((t) => t.stop())
  recordStream = null
  if (recordVideoRef.value) {
    recordVideoRef.value.srcObject = null
  }
}

function pickRecorderMime(): string | undefined {
  const types = [
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
    'video/mp4',
  ]
  for (const t of types) {
    if (MediaRecorder.isTypeSupported(t)) return t
  }
  return undefined
}

async function openRecordStream(): Promise<void> {
  stopRecordStream()
  const attempts: MediaStreamConstraints[] = [
    {
      video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: true,
    },
    {
      video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: false,
    },
  ]
  for (const constraints of attempts) {
    try {
      recordStream = await navigator.mediaDevices.getUserMedia(constraints)
      if (recordVideoRef.value) {
        recordVideoRef.value.srcObject = recordStream
        await recordVideoRef.value.play()
      }
      return
    } catch {
      /* try next */
    }
  }
  throw new Error('no stream')
}

async function openRecordDialog() {
  if (!navigator.mediaDevices?.getUserMedia) {
    ElMessage.error('当前浏览器不支持录制')
    return
  }
  if (typeof MediaRecorder === 'undefined') {
    ElMessage.error('当前浏览器不支持 MediaRecorder 录制')
    return
  }
  recordDialogVisible.value = true
  isRecording.value = false
  recordChunks = []
  mediaRecorder = null
  await nextTick()
  try {
    await openRecordStream()
  } catch (e: unknown) {
    const name = e && typeof e === 'object' && 'name' in e ? String((e as DOMException).name) : ''
    ElMessage.error(name === 'NotAllowedError' ? '请允许使用摄像头与麦克风' : '无法打开摄像头')
    recordDialogVisible.value = false
  }
}

function onRecordDialogClosed() {
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    const mr = mediaRecorder
    mr.onstop = () => {
      stopRecordStream()
      mediaRecorder = null
      recordChunks = []
      isRecording.value = false
    }
    mr.stop()
  } else {
    stopRecordStream()
    mediaRecorder = null
    recordChunks = []
    isRecording.value = false
  }
}

function beginRecording() {
  if (!recordStream) {
    ElMessage.warning('预览未就绪')
    return
  }
  if (mediaRecorder && mediaRecorder.state === 'recording') return

  recordChunks = []
  const mime = pickRecorderMime()
  try {
    mediaRecorder = mime
      ? new MediaRecorder(recordStream, { mimeType: mime })
      : new MediaRecorder(recordStream)
  } catch {
    mediaRecorder = new MediaRecorder(recordStream)
  }

  mediaRecorder.ondataavailable = (e) => {
    if (e.data.size > 0) recordChunks.push(e.data)
  }

  mediaRecorder.start(120)
  isRecording.value = true
}

function finishRecordingAndUpload() {
  if (!mediaRecorder || mediaRecorder.state !== 'recording') {
    ElMessage.warning('请先开始录制')
    return
  }
  const mr = mediaRecorder
  mr.onstop = () => {
    const blob = new Blob(recordChunks, { type: mr.mimeType || 'video/webm' })
    if (blob.size < 64) {
      ElMessage.warning('录制过短，请重试')
      stopRecordStream()
      mediaRecorder = null
      recordChunks = []
      isRecording.value = false
      recordDialogVisible.value = false
      return
    }
    const isMp4 = blob.type.includes('mp4')
    const ext = isMp4 ? 'mp4' : 'webm'
    const file = new File([blob], `在线录制-${Date.now()}.${ext}`, { type: blob.type || `video/${ext}` })
    mediaRecorder = null
    recordChunks = []
    isRecording.value = false
    stopRecordStream()
    recordDialogVisible.value = false
    startUpload(file)
  }
  mr.stop()
}

function cancelRecordDialog() {
  recordDialogVisible.value = false
}

onUnmounted(() => {
  if (videoRef.value) {
    videoRef.value.pause()
  }
  stopCameraStream()
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    mediaRecorder.onstop = null
    mediaRecorder.stop()
  }
  mediaRecorder = null
  stopRecordStream()
})
</script>

<template>
  <div class="main-player glass-card glass-card--flat">
    <div class="player-header">
      <div class="section-title">主监控画面</div>
      <div class="header-actions">
        <span v-if="store.analyzing" class="recording-dot">● 分析中</span>
        <button v-if="store.selectedMedia" class="back-btn" @click="goBack" title="返回">
          <el-icon :size="14"><Close /></el-icon>
          <span>返回</span>
        </button>
      </div>
    </div>

    <div class="video-container">
      <img
        v-if="showMainImage && mainImageSrc"
        :src="mainImageSrc"
        class="image-preview"
        alt=""
      />
      <video
        v-else-if="showMainVideo"
        ref="videoRef"
        controls
        autoplay
        muted
        loop
        class="video-player"
        poster=""
      />
      <div v-if="!store.selectedMedia" class="video-placeholder">
        <div class="placeholder-icon">
          <el-icon :size="36"><VideoCamera /></el-icon>
        </div>
        <p class="placeholder-title">开始评估采集</p>
        <span class="placeholder-desc">上传本地视频或图片，或使用在线拍照 / 录制</span>
        <div class="local-btns">
          <label class="local-btn" :class="{ disabled: store.uploadLoading }">
            <input
              type="file"
              accept="video/*"
              style="display:none"
              :disabled="store.uploadLoading"
              @change="onVideoChange"
            />
            <el-icon :size="16"><VideoCamera /></el-icon>
            <span>选择本地视频</span>
          </label>
          <label class="local-btn" :class="{ disabled: store.uploadLoading }">
            <input
              type="file"
              accept="image/*"
              style="display:none"
              :disabled="store.uploadLoading"
              @change="onImageChange"
            />
            <el-icon :size="16"><Picture /></el-icon>
            <span>选择本地图片</span>
          </label>
        </div>
        <div class="local-btns online-btns">
          <button
            type="button"
            class="local-btn online-btn"
            :disabled="store.uploadLoading"
            @click="openCameraDialog"
          >
            <el-icon :size="16"><Camera /></el-icon>
            <span>在线拍照</span>
          </button>
          <button
            type="button"
            class="local-btn online-btn"
            :disabled="store.uploadLoading"
            @click="openRecordDialog"
          >
            <el-icon :size="16"><Film /></el-icon>
            <span>在线录制</span>
          </button>
        </div>
      </div>
    </div>

    <div v-if="store.selectedMedia" class="media-info">
      <span class="media-name-ellipsis" :title="mainMediaTitle">{{ mainMediaTitle }}</span>
      <span v-if="store.selectedMedia.duration && !store.singleFaceImageMode" class="mono-num">{{
        store.selectedMedia.duration
      }}s</span>
    </div>

    <el-dialog
      v-model="cameraDialogVisible"
      title="在线拍照"
      width="min(520px, 92vw)"
      class="camera-dialog"
      :close-on-click-modal="false"
      destroy-on-close
      @closed="onCameraDialogClosed"
    >
      <div class="camera-preview-wrap">
        <video
          ref="cameraVideoRef"
          class="camera-preview"
          playsinline
          muted
        />
      </div>
      <template #footer>
        <el-button @click="cameraDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="store.uploadLoading" @click="capturePhoto">
          拍照并分析
        </el-button>
      </template>
    </el-dialog>

    <el-dialog
      v-model="recordDialogVisible"
      title="在线录制"
      width="min(520px, 92vw)"
      class="camera-dialog"
      :close-on-click-modal="false"
      destroy-on-close
      @closed="onRecordDialogClosed"
    >
      <div class="camera-preview-wrap">
        <video
          ref="recordVideoRef"
          class="camera-preview"
          playsinline
          muted
        />
        <div v-if="isRecording" class="rec-indicator">● 录制中</div>
      </div>
      <p class="record-hint">开始录制后，点击「停止并完成」将视频保存到素材库并自动开始分析。</p>
      <template #footer>
        <el-button @click="cancelRecordDialog">取消</el-button>
        <el-button :disabled="isRecording || store.uploadLoading" @click="beginRecording">
          开始录制
        </el-button>
        <el-button
          type="primary"
          :disabled="!isRecording || store.uploadLoading"
          :loading="store.uploadLoading"
          @click="finishRecordingAndUpload"
        >
          停止并完成
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.main-player {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  padding: 12px;
  overflow: hidden;
}

.player-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-shrink: 0;
  margin-bottom: 10px;
}

.player-header .section-title {
  margin-bottom: 0;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}

.video-container {
  flex: 1;
  position: relative;
  background: linear-gradient(145deg, #ecfdf5 0%, #e0f2fe 50%, #f8fafc 100%);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-card);
  overflow: hidden;
  min-height: 0;
}

.video-container:has(.video-player),
.video-container:has(.image-preview) {
  background: var(--bg-muted);
}

.video-player,
.image-preview {
  position: absolute;
  inset: 0;
  display: block;
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: transparent;
}

.video-placeholder {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  text-align: center;
  padding: 24px 20px;
}

.placeholder-icon {
  width: 72px;
  height: 72px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(255, 255, 255, 0.75);
  border: 1px solid rgba(13, 148, 136, 0.18);
  border-radius: 50%;
  color: var(--accent-primary);
  margin-bottom: 4px;
  box-shadow: var(--shadow-sm);
}

.placeholder-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.placeholder-desc {
  font-size: 13px;
  color: var(--text-muted);
  max-width: 280px;
  line-height: 1.5;
}

.local-btns {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 4px;
  justify-content: center;
}

.online-btns {
  margin-top: 8px;
}

.local-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  color: var(--accent-primary);
  font-size: 13px;
  padding: 8px 16px;
  border: 1px solid rgba(13, 148, 136, 0.25);
  border-radius: var(--radius-sm);
  transition: all 0.2s;
  background: rgba(255, 255, 255, 0.85);
  box-shadow: var(--shadow-sm);
}

.local-btn.online-btn {
  border-style: solid;
}

.local-btn:hover:not(.disabled) {
  background: #ffffff;
  border-color: var(--accent-primary);
  box-shadow: var(--shadow-card);
}

.local-btn.disabled {
  opacity: 0.45;
  pointer-events: none;
}

.recording-dot {
  color: var(--accent-red);
  font-size: 12px;
  animation: breathe 1.2s ease-in-out infinite;
  white-space: nowrap;
}

.back-btn {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px;
  font-size: 12px;
  color: var(--text-secondary);
  background: var(--bg-muted);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  cursor: pointer;
  transition: all 0.2s;
  white-space: nowrap;
}

.back-btn:hover {
  color: var(--text-primary);
  background: var(--bg-muted);
  border-color: var(--border-color);
}

.media-info {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  margin-top: 8px;
  font-size: 12px;
  color: var(--text-secondary);
  min-width: 0;
  flex-shrink: 0;
  background: var(--bg-muted);
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-sm);
}

.camera-preview-wrap {
  position: relative;
  background: var(--bg-muted);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  overflow: hidden;
  aspect-ratio: 16 / 10;
  max-height: 56vh;
}

.camera-preview {
  width: 100%;
  height: 100%;
  object-fit: cover;
  vertical-align: middle;
}

.rec-indicator {
  position: absolute;
  top: 10px;
  left: 12px;
  font-size: 13px;
  color: var(--accent-red);
  background: rgba(255, 255, 255, 0.9);
  padding: 2px 8px;
  border-radius: 12px;
  font-weight: 600;
}

.media-name-ellipsis {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.record-hint {
  margin: 12px 0 0;
  font-size: 12px;
  color: var(--text-muted);
  line-height: 1.5;
}
</style>

<style>
.camera-dialog .el-dialog__body {
  padding-top: 8px;
}
</style>
