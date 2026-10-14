import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { MediaItem, AnalysisFrame } from '@/api/index'
import { apiFetch, parseApiError } from '@/api/http'
import { fetchMediaList, triggerAnalysis, deleteMedia as deleteMediaApi } from '@/api/index'

export interface FaceFrameSnapshot {
  key: string
  frameId: number
  b64: string
  score: number
  inferenceTimeMs: number
  progress: number
}

export type SeverityLevel = 'none' | 'mild' | 'moderate' | 'severe'

export interface BdiPoint {
  time: string
  score: number
}

export function getSeverity(score: number): SeverityLevel {
  if (score <= 13) return 'none'
  if (score <= 19) return 'mild'
  if (score <= 28) return 'moderate'
  return 'severe'
}

export const severityLabels: Record<SeverityLevel, string> = {
  none: '正常范围',
  mild: '轻度抑郁',
  moderate: '中度抑郁',
  severe: '重度抑郁',
}

export const severityColors: Record<SeverityLevel, string> = {
  none: '#f2f3b2',
  mild: '#b2f3cd',
  moderate: '#b2c3f3',
  severe: '#f3b2bd',
}

export const severitySuggestions: Record<SeverityLevel, string> = {
  none: '当前情绪状态良好，建议保持健康的生活作息和社交活动。',
  mild: '建议结构化心理治疗（CBT/IPT），结合运动处方和正念训练。',
  moderate: '建议 CBT 联合 SSRI 药物治疗，强化随访频率，评估自杀风险。',
  severe: '建议立即转诊精神专科，考虑 SNRI/augmented 方案或 ECT/rTMS。',
}

export const useDashboardStore = defineStore('dashboard', () => {
  // --- Media ---
  const mediaList = ref<MediaItem[]>([])
  const mediaLoading = ref(false)
  const mediaError = ref('')
  const selectedMediaId = ref<string | null>(null)

  // --- Analysis ---
  const analyzing = ref(false)
  const currentFrame = ref<AnalysisFrame | null>(null)
  const bdiHistory = ref<BdiPoint[]>([])
  const faceImageData = ref<string>('')
  const heatmapData = ref<number[][]>([])
  const inferenceTimeMs = ref(0)
  const analysisProgress = ref(0)

  // --- WebSocket ---
  const wsConnected = ref(false)
  const isDemo = ref(false)

  // --- VLM ---
  const vlmAnalysis = ref('')

  // --- Patient info ---
  const patientInfo = ref<{
    patientId: string
    gender: string
    ageRange: string
    assessmentDate: string
  } | null>(null)

  const demoPlaying = ref(false)

  /** 视频/图片分析过程中累积的人脸帧缩略图（base64），用于左侧人脸帧模块 */
  const faceFrameHistory = ref<FaceFrameSnapshot[]>([])

  /** 来自视频单帧检测：忽略 WS 续传的帧，主界面显示为静态人脸图 */
  const ignoreIncomingWsFrames = ref(false)
  const singleFaceImageMode = ref(false)
  const singleFaceImageUrl = ref('')
  const singleFaceLabel = ref('')

  // --- Computed ---
  const currentScore = computed(() => Math.round(currentFrame.value?.bdi_score ?? 0))
  const severity = computed(() => getSeverity(currentScore.value))
  const severityLabel = computed(() => severityLabels[severity.value])
  const severityColor = computed(() => severityColors[severity.value])
  const suggestion = computed(() => severitySuggestions[severity.value])

  const selectedMedia = computed(() =>
    mediaList.value.find((m) => m.id === selectedMediaId.value) ?? null
  )

  // --- Actions ---
  async function loadMediaList() {
    mediaLoading.value = true
    mediaError.value = ''
    try {
      mediaList.value = await fetchMediaList()
    } catch (e: any) {
      mediaError.value = e.message ?? '加载失败'
    } finally {
      mediaLoading.value = false
    }
  }

  /** 删除素材：演示模式与本地视频仅更新前端；其余调用后端并移除磁盘文件 */
  async function removeMedia(id: string) {
    if (id === 'local-video') {
      if (localVideoUrl.value) {
        URL.revokeObjectURL(localVideoUrl.value)
        localVideoUrl.value = ''
      }
      localVideoName.value = ''
      mediaList.value = mediaList.value.filter((m) => m.id !== id)
      if (selectedMediaId.value === id) {
        selectedMediaId.value = null
        reset()
        stopDemoAnalysis()
      }
      return
    }
    if (isDemo.value) {
      mediaList.value = mediaList.value.filter((m) => m.id !== id)
      if (selectedMediaId.value === id) {
        selectedMediaId.value = null
        reset()
        stopDemoAnalysis()
      }
      return
    }
    await deleteMediaApi(id)
    mediaList.value = mediaList.value.filter((m) => m.id !== id)
    if (selectedMediaId.value === id) {
      selectedMediaId.value = null
      reset()
      stopDemoAnalysis()
    }
  }

  async function startAnalysis(id: string) {
    selectedMediaId.value = id
    analyzing.value = true
    bdiHistory.value = []
    analysisProgress.value = 0
    currentFrame.value = null
    faceFrameHistory.value = []
    ignoreIncomingWsFrames.value = false
    singleFaceImageMode.value = false
    singleFaceImageUrl.value = ''
    singleFaceLabel.value = ''
    try {
      await triggerAnalysis(id)
    } catch {
      // even if HTTP fails, WS may succeed
    }
  }

  const uploadLoading = ref(false)

  async function uploadAndAnalyze(file: File) {
    uploadLoading.value = true
    mediaError.value = ''
    try {
      const form = new FormData()
      form.append('file', file)
      const res = await apiFetch('/api/upload/image', { method: 'POST', body: form })
      if (!res.ok) {
        throw new Error(await parseApiError(res, '上传失败'))
      }
      const uploaded = await res.json()
      // Add to media list
      mediaList.value.unshift({
        id: uploaded.id,
        name: uploaded.name,
        type: uploaded.type,
        thumbnail_url: '',
        url: uploaded.url,
        duration: undefined,
        created_at: new Date().toISOString().split('T')[0],
      })
      // Auto-start analysis
      await startAnalysis(uploaded.id)
    } catch (e: any) {
      mediaError.value = e.message ?? '上传失败'
    } finally {
      uploadLoading.value = false
    }
  }

  function handleWsMessage(data: any) {
    if (ignoreIncomingWsFrames.value) {
      return
    }
    if (data.type === 'status' || data.type === 'done' || data.type === 'error') {
      return
    }
    if (data.type === 'vlm_analysis') {
      vlmAnalysis.value = data.content
      return
    }
    handleFrame(data as AnalysisFrame)
  }

  function handleFrame(frame: AnalysisFrame) {
    currentFrame.value = frame
    analysisProgress.value = frame.progress
    inferenceTimeMs.value = frame.inference_time_ms

    bdiHistory.value.push({
      time: new Date(frame.timestamp * 1000).toLocaleTimeString('zh-CN'),
      score: Math.round(frame.bdi_score),
    })

    if (frame.aligned_face) {
      faceImageData.value = frame.aligned_face
      const media = selectedMedia.value
      if (media?.type === 'video' && analyzing.value) {
        const dup = faceFrameHistory.value.some((x) => x.frameId === frame.frame_id)
        if (!dup) {
          faceFrameHistory.value.push({
            key: `${frame.frame_id}-${frame.timestamp}`,
            frameId: frame.frame_id,
            b64: frame.aligned_face,
            score: Math.round(frame.bdi_score),
            inferenceTimeMs: frame.inference_time_ms,
            progress: frame.progress,
          })
          if (faceFrameHistory.value.length > 48) {
            faceFrameHistory.value.shift()
          }
        }
      } else if (media?.type === 'image' && analyzing.value && faceFrameHistory.value.length === 0) {
        faceFrameHistory.value.push({
          key: `img-${frame.frame_id}`,
          frameId: frame.frame_id,
          b64: frame.aligned_face,
          score: Math.round(frame.bdi_score),
          inferenceTimeMs: frame.inference_time_ms,
          progress: frame.progress,
        })
      }
    }
    if (frame.heatmap_data) {
      heatmapData.value = frame.heatmap_data
    }

    if (frame.progress >= 1) {
      analyzing.value = false
    }
  }

  function setWsConnected(v: boolean) {
    wsConnected.value = v
  }

  function reset() {
    analyzing.value = false
    currentFrame.value = null
    bdiHistory.value = []
    faceImageData.value = ''
    heatmapData.value = []
    inferenceTimeMs.value = 0
    analysisProgress.value = 0
    patientInfo.value = null
    vlmAnalysis.value = ''
    faceFrameHistory.value = []
    ignoreIncomingWsFrames.value = false
    singleFaceImageMode.value = false
    singleFaceImageUrl.value = ''
    singleFaceLabel.value = ''
  }

  /** 主界面「返回」：清空主监控区与选中素材，但保留左侧人脸帧列表 */
  function exitMainDisplayKeepFaceFrames() {
    stopDemoAnalysis()
    analyzing.value = false
    currentFrame.value = null
    bdiHistory.value = []
    faceImageData.value = ''
    heatmapData.value = []
    inferenceTimeMs.value = 0
    analysisProgress.value = 0
    patientInfo.value = null
    vlmAnalysis.value = ''
    selectedMediaId.value = null
    ignoreIncomingWsFrames.value = false
    singleFaceImageMode.value = false
    singleFaceImageUrl.value = ''
    singleFaceLabel.value = ''
  }

  function clearFaceFrameHistory() {
    faceFrameHistory.value = []
  }

  /**
   * 视频分析中单帧检测完成后：结束视频流式检测态，主界面改为展示该帧的「图片检测」结果。
   */
  function switchVideoAnalysisToSingleFaceImage(
    payload: {
      bdi_score: number
      inference_time_ms: number
      heatmap_data: number[][]
      aligned_face_b64: string
    },
    meta: { frameId: number; videoName: string },
  ) {
    stopDemoAnalysis()
    analyzing.value = false
    ignoreIncomingWsFrames.value = true
    singleFaceImageMode.value = true
    singleFaceImageUrl.value = `data:image/jpeg;base64,${payload.aligned_face_b64}`
    singleFaceLabel.value = `抽帧图片 · #${meta.frameId} · ${meta.videoName}`
    applySingleFrameAnalysisResult(payload)
    const t = new Date().toLocaleTimeString('zh-CN')
    bdiHistory.value = [{ time: t, score: Math.round(payload.bdi_score) }]
    analysisProgress.value = 1
  }

  /** 将某张人脸缩略图的单帧推理结果同步到中间面部预览 / 分数展示 */
  function applySingleFrameAnalysisResult(payload: {
    bdi_score: number
    inference_time_ms: number
    heatmap_data: number[][]
    aligned_face_b64: string
  }) {
    faceImageData.value = payload.aligned_face_b64
    heatmapData.value = payload.heatmap_data
    inferenceTimeMs.value = payload.inference_time_ms
    currentFrame.value = {
      frame_id: -1,
      timestamp: Date.now() / 1000,
      bdi_score: payload.bdi_score,
      aligned_face: payload.aligned_face_b64,
      heatmap_data: payload.heatmap_data,
      inference_time_ms: payload.inference_time_ms,
      progress: 1,
    }
  }

  // --- Local video ---
  const localVideoUrl = ref<string>('')
  const localVideoName = ref<string>('')

  function setLocalVideo(file: File) {
    if (localVideoUrl.value) {
      URL.revokeObjectURL(localVideoUrl.value)
    }
    localVideoUrl.value = URL.createObjectURL(file)
    localVideoName.value = file.name
    const id = 'local-video'
    mediaList.value = mediaList.value.filter((m) => m.id !== id)
    mediaList.value.unshift({
      id,
      name: file.name,
      type: 'video',
      thumbnail_url: '',
      url: localVideoUrl.value,
      duration: 0,
      created_at: new Date().toISOString().split('T')[0],
    })
    selectedMediaId.value = id
  }

  // --- Demo mode: simulate analysis without backend ---
  let demoInterval: ReturnType<typeof setInterval> | null = null

  function loadDemoData() {
    isDemo.value = true
    mediaList.value = [
      { id: '1', name: '患者A_初始访谈.mp4', type: 'video', thumbnail_url: '', url: '', duration: 120, created_at: '2026-04-10' },
      { id: '2', name: '患者B_随访记录.mp4', type: 'video', thumbnail_url: '', url: '', duration: 90, created_at: '2026-04-12' },
      { id: '3', name: '患者C_情绪评估.png', type: 'image', thumbnail_url: '', url: '', created_at: '2026-04-15' },
      { id: '4', name: '患者D_心理咨询.mp4', type: 'video', thumbnail_url: '', url: '', duration: 180, created_at: '2026-04-18' },
      { id: '5', name: '患者A_复诊.png', type: 'image', thumbnail_url: '', url: '', created_at: '2026-04-20' },
      { id: '6', name: '匿名样本_001.mp4', type: 'video', thumbnail_url: '', url: '', duration: 60, created_at: '2026-04-22' },
    ]
    mediaError.value = ''
    mediaLoading.value = false
  }

  function startDemoAnalysis(id: string) {
    stopDemoAnalysis()
    selectedMediaId.value = id
    analyzing.value = true
    bdiHistory.value = []
    analysisProgress.value = 0
    currentFrame.value = null
    faceFrameHistory.value = []
    ignoreIncomingWsFrames.value = false
    singleFaceImageMode.value = false
    singleFaceImageUrl.value = ''
    singleFaceLabel.value = ''
    wsConnected.value = true

    let frameId = 0
    const totalFrames = 60
    // Simulate a score trajectory that moves from normal to moderate and back
    const baseScore = 18 + Math.random() * 10

    demoInterval = setInterval(() => {
      frameId++
      const progress = frameId / totalFrames
      const noise = Math.sin(frameId * 0.3) * 6 + (Math.random() - 0.5) * 4
      const score = Math.max(0, Math.min(63, baseScore + noise))

      const frame: AnalysisFrame = {
        frame_id: frameId,
        timestamp: Date.now() / 1000,
        bdi_score: score,
        aligned_face: '',
        heatmap_data: generateDemoHeatmap(),
        inference_time_ms: 24 + Math.random() * 8,
        progress,
      }

      handleFrame(frame)

      // 演示模式无人脸图时跳过人脸帧条；若有 base64 可在此填入

      if (progress >= 1) {
        stopDemoAnalysis()
      }
    }, 300)
  }

  function generateDemoHeatmap(): number[][] {
    const size = 16
    const data: number[][] = []
    for (let y = 0; y < size; y++) {
      const row: number[] = []
      for (let x = 0; x < size; x++) {
        // Gaussian-like hotspot near center
        const dx = (x - size / 2) / (size / 4)
        const dy = (y - size / 2) / (size / 4)
        const v = Math.exp(-(dx * dx + dy * dy) / 1.5)
        row.push(Math.round(v * 100) / 100)
      }
      data.push(row)
    }
    return data
  }

  function stopDemoAnalysis() {
    if (demoInterval) {
      clearInterval(demoInterval)
      demoInterval = null
    }
    analyzing.value = false
  }

  function setPatientInfo(info: typeof patientInfo.value) {
    patientInfo.value = info
  }

  return {
    mediaList, mediaLoading, mediaError, selectedMediaId,
    analyzing, currentFrame, bdiHistory, faceImageData, heatmapData,
    inferenceTimeMs, analysisProgress, wsConnected, isDemo, demoPlaying,
    currentScore, severity, severityLabel, severityColor, suggestion, selectedMedia,
    patientInfo, setPatientInfo,
    faceFrameHistory,
    ignoreIncomingWsFrames, singleFaceImageMode, singleFaceImageUrl, singleFaceLabel,
    loadMediaList, removeMedia, startAnalysis, uploadAndAnalyze, uploadLoading, handleFrame, handleWsMessage, setWsConnected, reset,
    exitMainDisplayKeepFaceFrames, clearFaceFrameHistory,
    applySingleFrameAnalysisResult, switchVideoAnalysisToSingleFaceImage,
    localVideoUrl, localVideoName, setLocalVideo,
    loadDemoData, startDemoAnalysis, stopDemoAnalysis,
    vlmAnalysis,
  }
})
