<script setup lang="ts">
import { nextTick, onBeforeUnmount, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { Camera, Upload, VideoCamera } from '@element-plus/icons-vue'
import { useDashboardStore } from '@/stores/dashboard'
import UploadMediaDialog from '@/components/common/UploadMediaDialog.vue'

const store = useDashboardStore()
const router = useRouter()

/** 上传素材走对话框（可填患者名）；在线拍照/录制也在各自对话框里填同一个字段。 */
const uploadVisible = ref(false)
const patientName = ref('')

function openUploadDialog() {
  uploadVisible.value = true
}

/**
 * 拍照/录制的上传：带对话框里填的患者名，**不自动开始分析**（P4a 变更）。
 * 上传成功后 store 只把素材加入列表并选中，用户在工作台点「开始分析」才发起推理。
 */
async function uploadCaptured(file: File) {
  const item = await store.uploadMedia(file, patientName.value.trim() || undefined)
  if (item) ElMessage.success('已上传并选中，点「开始分析」发起评估')
  else ElMessage.error(store.mediaError || '上传失败')
}

// ── 在线拍照（Web 独有能力，从旧 MainVideoPlayer 迁入） ──
const cameraDialogVisible = ref(false)
const cameraVideoRef = ref<HTMLVideoElement | null>(null)
let cameraStream: MediaStream | null = null

async function openCameraDialog() {
  if (!navigator.mediaDevices?.getUserMedia) {
    ElMessage.error('当前浏览器不支持摄像头采集')
    return
  }
  cameraDialogVisible.value = true
  await nextTick()
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } },
    })
    if (cameraVideoRef.value) {
      cameraVideoRef.value.srcObject = cameraStream
      await cameraVideoRef.value.play()
    }
  } catch (e: unknown) {
    const name = e instanceof Error ? e.name : ''
    ElMessage.error(name === 'NotAllowedError' ? '请允许使用摄像头' : '无法打开摄像头')
    stopCamera()
    cameraDialogVisible.value = false
  }
}

function stopCamera() {
  cameraStream?.getTracks().forEach((track) => track.stop())
  cameraStream = null
  if (cameraVideoRef.value) cameraVideoRef.value.srcObject = null
}

function capturePhoto() {
  const video = cameraVideoRef.value
  if (!video?.videoWidth) {
    ElMessage.warning('摄像头画面尚未就绪，请稍后重试')
    return
  }
  const canvas = document.createElement('canvas')
  canvas.width = video.videoWidth
  canvas.height = video.videoHeight
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
  canvas.toBlob(
    (blob) => {
      if (!blob) {
        ElMessage.error('拍照失败，请重试')
        return
      }
      const file = new File([blob], `在线拍照-${Date.now()}.jpg`, { type: 'image/jpeg' })
      stopCamera()
      cameraDialogVisible.value = false
      void uploadCaptured(file)
    },
    'image/jpeg',
    0.92,
  )
}

// ── 在线录制（Web 独有能力，从旧 MainVideoPlayer 迁入） ──
const recordDialogVisible = ref(false)
const recordVideoRef = ref<HTMLVideoElement | null>(null)
const isRecording = ref(false)
let recordStream: MediaStream | null = null
let mediaRecorder: MediaRecorder | null = null
let recordChunks: Blob[] = []

async function openRecordDialog() {
  if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
    ElMessage.error('当前浏览器不支持视频录制')
    return
  }
  recordDialogVisible.value = true
  await nextTick()
  await openRecordStream()
}

async function openRecordStream() {
  const constraints: MediaStreamConstraints[] = [
    { video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }, audio: true },
    { video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false },
  ]
  for (const constraint of constraints) {
    try {
      recordStream = await navigator.mediaDevices.getUserMedia(constraint)
      break
    } catch {
      recordStream = null
    }
  }
  if (!recordStream) {
    ElMessage.error('无法打开摄像头或麦克风')
    recordDialogVisible.value = false
    return
  }
  if (recordVideoRef.value) {
    recordVideoRef.value.srcObject = recordStream
    await recordVideoRef.value.play()
  }
}

function pickRecorderMime(): string {
  const candidates = [
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
    'video/mp4',
  ]
  return candidates.find((type) => MediaRecorder.isTypeSupported(type)) ?? ''
}

function beginRecording() {
  if (!recordStream || isRecording.value) return
  try {
    const mimeType = pickRecorderMime()
    mediaRecorder = new MediaRecorder(recordStream, mimeType ? { mimeType } : undefined)
  } catch {
    try {
      mediaRecorder = new MediaRecorder(recordStream)
    } catch {
      ElMessage.error('无法启动录制')
      return
    }
  }
  recordChunks = []
  mediaRecorder.ondataavailable = (event) => {
    if (event.data.size > 0) recordChunks.push(event.data)
  }
  mediaRecorder.start(120)
  isRecording.value = true
}

function stopRecordStream() {
  recordStream?.getTracks().forEach((track) => track.stop())
  recordStream = null
  if (recordVideoRef.value) recordVideoRef.value.srcObject = null
}

function finishRecordingAndUpload() {
  const recorder = mediaRecorder
  if (!recorder || recorder.state === 'inactive') {
    ElMessage.warning('还没有开始录制')
    return
  }
  recorder.onstop = () => {
    const blob = new Blob(recordChunks, { type: recorder.mimeType || 'video/webm' })
    const ext = blob.type.includes('mp4') ? 'mp4' : 'webm'
    recordChunks = []
    mediaRecorder = null
    isRecording.value = false
    stopRecordStream()
    recordDialogVisible.value = false
    if (blob.size < 64) {
      ElMessage.warning('录制过短，请重试')
      return
    }
    const file = new File([blob], `在线录制-${Date.now()}.${ext}`, { type: blob.type })
    void uploadCaptured(file)
  }
  recorder.stop()
}

function onRecordDialogClosed() {
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    mediaRecorder.onstop = null
    mediaRecorder.stop()
  }
  mediaRecorder = null
  recordChunks = []
  isRecording.value = false
  stopRecordStream()
}

onBeforeUnmount(() => {
  stopCamera()
  onRecordDialogClosed()
})
</script>

<template>
  <section class="start-card glass-card">
    <header class="start-head">
      <h2 class="start-title">开始新的辅助评估</h2>
      <p class="start-desc">
        选择一张图片或一段视频，服务端会逐帧推理并给出 BDI-II 辅助评分。
      </p>
    </header>

    <div class="start-types">
      <span class="start-type start-type--image">
        <span class="start-dot" aria-hidden="true" />
        图片 · 单次推理
      </span>
      <span class="start-type start-type--video">
        <span class="start-dot" aria-hidden="true" />
        视频 · 逐帧采样
      </span>
    </div>

    <el-button type="primary" class="start-primary" :icon="Upload" @click="router.push('/library')">
      从素材库选择
    </el-button>

    <p class="start-divider">或直接采集</p>

    <div class="start-tools">
      <button type="button" class="start-tool" :disabled="store.uploadLoading" @click="openUploadDialog">
        <el-icon :size="18"><Upload /></el-icon>
        <span>{{ store.uploadLoading ? '上传中…' : '上传素材' }}</span>
      </button>
      <button type="button" class="start-tool" @click="openCameraDialog">
        <el-icon :size="18"><Camera /></el-icon>
        <span>在线拍照</span>
      </button>
      <button type="button" class="start-tool" @click="openRecordDialog">
        <el-icon :size="18"><VideoCamera /></el-icon>
        <span>在线录制</span>
      </button>
    </div>

    <UploadMediaDialog v-model="uploadVisible" title="上传素材" />

    <p class="start-note">
      上传不会自动开始分析：素材会加入列表并自动选中，由你点「开始分析」发起评估；请确保已获得受试者授权。
    </p>

    <el-dialog
      v-model="cameraDialogVisible"
      title="在线拍照"
      width="min(520px, 92vw)"
      :close-on-click-modal="false"
      @closed="stopCamera"
    >
      <label class="form-field">
        <span class="form-label">所属患者（可选）</span>
        <el-input v-model="patientName" maxlength="64" show-word-limit placeholder="例如：张三；留空表示未标注患者" />
      </label>
      <div class="camera-box">
        <video ref="cameraVideoRef" class="camera-video" autoplay muted playsinline />
      </div>
      <template #footer>
        <el-button @click="cameraDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="capturePhoto">拍照并上传</el-button>
      </template>
    </el-dialog>

    <el-dialog
      v-model="recordDialogVisible"
      title="在线录制"
      width="min(520px, 92vw)"
      :close-on-click-modal="false"
      @closed="onRecordDialogClosed"
    >
      <label class="form-field">
        <span class="form-label">所属患者（可选）</span>
        <el-input v-model="patientName" maxlength="64" show-word-limit placeholder="例如：张三；留空表示未标注患者" />
      </label>
      <div class="camera-box">
        <video ref="recordVideoRef" class="camera-video" autoplay muted playsinline />
      </div>
      <p class="record-note">录制完成后会上传并自动选中，不会自动开始分析；请确保已获得受试者授权。</p>
      <template #footer>
        <el-button @click="recordDialogVisible = false">取消</el-button>
        <el-button v-if="!isRecording" type="primary" @click="beginRecording">开始录制</el-button>
        <el-button v-else type="danger" @click="finishRecordingAndUpload">停止并上传</el-button>
      </template>
    </el-dialog>
  </section>
</template>

<style scoped>
.start-card {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  min-width: 0;
}

.start-title {
  margin: 0;
  font-size: var(--font-base);
  font-weight: 600;
  color: var(--text-primary);
}

.start-desc {
  margin: var(--space-1) 0 0;
  font-size: var(--font-sm);
  line-height: 1.55;
  color: var(--text-secondary);
}

.start-types {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
}

.start-type {
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  padding: 4px 10px;
  border-radius: var(--radius-control);
  background: var(--bg-inset);
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.start-dot {
  width: 6px;
  height: 6px;
  border-radius: var(--radius-pill);
  background: var(--color-primary);
}

.start-type--video .start-dot {
  background: var(--color-accent);
}

.start-primary {
  width: 100%;
  min-height: 44px;
}

.start-divider {
  margin: 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  text-align: center;
}

.start-tools {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: var(--space-2);
}

.start-tool {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--space-1);
  min-height: 64px;
  padding: var(--space-2);
  border: 1px solid var(--border);
  border-radius: var(--radius-tag);
  background: var(--bg-card);
  color: var(--text-secondary);
  font-size: var(--font-xs);
  cursor: pointer;
  transition: background var(--motion-press) ease, border-color var(--motion-press) ease;
}

.start-tool:hover {
  background: var(--bg-press);
  border-color: var(--color-primary);
  color: var(--color-primary-text);
}

.start-tool:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

.start-note {
  margin: 0;
  font-size: var(--font-xs);
  line-height: 1.5;
  color: var(--text-secondary);
}

.form-field {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  margin-bottom: var(--space-3);
}

.form-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.camera-box {
  width: 100%;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border-radius: var(--radius-tag);
  background: var(--bg-inset);
}

.camera-video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.record-note {
  margin: var(--space-2) 0 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

@media (max-width: 480px) {
  .start-tools {
    grid-template-columns: 1fr;
  }
}
</style>
