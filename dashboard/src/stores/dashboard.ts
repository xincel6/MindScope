import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { MediaItem, AnalysisFrame } from '@/api/index'
import {
  fetchMediaList,
  triggerAnalysis,
  deleteMedia as deleteMediaApi,
  uploadMedia as uploadMediaApi,
  renamePatient as renamePatientApi,
} from '@/api/index'

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

/** 数据表达色（色块 / 图例 / 饼图扇区 / 边框）：鸿蒙 UiConstant.severityMeta().color 四色。
 *  对白底对比度 3.30 / 4.10 / 3.19 / 4.83 —— 只有 severe 够正文，其余**只做填充与图标**。 */
export const severityColors: Record<SeverityLevel, string> = {
  none: '#16A34A',
  mild: '#0284C7',
  moderate: '#D97706',
  severe: '#DC2626',
}

/** 文字态（badge 文字 / 数值 / 标签）：对白底 5.02 / 5.93 / 5.02 / 6.47，全部过 AA 正文。 */
export const severityTextColors: Record<SeverityLevel, string> = {
  none: '#15803D',
  mild: '#0369A1',
  moderate: '#B45309',
  severe: '#B91C1C',
}

/** 取数据表达色。入参常是接口返回的 string/any，这里一次性收窄，避免各组件重复 TS7053 断言。 */
export function severityColorOf(level: SeverityLevel | string): string {
  return severityColors[level as SeverityLevel] ?? severityColors.none
}

/** 取文字态色。语义同 severityColorOf（文字一律走这个）。 */
export function severityTextColorOf(level: SeverityLevel | string): string {
  return severityTextColors[level as SeverityLevel] ?? severityTextColors.none
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
  /** 每次发起分析自增：作为「按需建立 WebSocket」的触发信号（同一素材再分析一次也能触发） */
  const analysisRunId = ref(0)
  const currentFrame = ref<AnalysisFrame | null>(null)
  const bdiHistory = ref<BdiPoint[]>([])
  const faceImageData = ref<string>('')
  const heatmapData = ref<number[][]>([])
  const inferenceTimeMs = ref(0)
  const analysisProgress = ref(0)

  // --- WebSocket ---
  const wsConnected = ref(false)

  // --- VLM ---
  const vlmAnalysis = ref('')

  // --- Patient info ---
  const patientInfo = ref<{
    patientId: string
    gender: string
    ageRange: string
    assessmentDate: string
  } | null>(null)

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
  /** 文字态：数值 / 标签 / badge 一律用它（数据色只做填充） */
  const severityTextColor = computed(() => severityTextColors[severity.value])
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

  /** 删除素材：本地视频仅更新前端；其余调用后端并移除磁盘文件 */
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
      }
      return
    }
    await deleteMediaApi(id)
    mediaList.value = mediaList.value.filter((m) => m.id !== id)
    if (selectedMediaId.value === id) {
      selectedMediaId.value = null
      reset()
    }
  }

  async function startAnalysis(id: string) {
    selectedMediaId.value = id
    analyzing.value = true
    analysisRunId.value += 1
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

  /**
   * 上传素材：只「加入列表 + 选中」，**不再自动开始分析**（P4a 行为变更）。
   *
   * 原 `uploadAndAnalyze` 会在上传成功后立刻 `startAnalysis()`，导致：
   *   · 用户还没确认患者名，推理已经跑起来了；
   *   · 想改患者名只能等一次完整分析跑完。
   * 现在改为与鸿蒙一致的两步式：上传 → 选中 → 用户在工作台点「开始分析」
   * （`AssessmentHeroCard` 在「有素材、无帧、未分析」时正好显示「开始分析」按钮）。
   *
   * `patient` 可选，走后端 query 参数（`upload.py` 里 `patient` 是 Query(None)）。
   * 返回上传后的素材；失败返回 null 并把原因写进 `mediaError`。
   */
  async function uploadMedia(file: File, patient?: string): Promise<MediaItem | null> {
    uploadLoading.value = true
    mediaError.value = ''
    try {
      const uploaded = await uploadMediaApi(file, patient)
      mediaList.value.unshift(uploaded)
      // 选中新素材前先清掉上一个素材的分析态：否则旧 WebSocket 的帧会继续
      // 落在 currentFrame 上，看起来像是新素材的评分（reset 不动 mediaList/selectedMediaId）。
      reset()
      selectedMediaId.value = uploaded.id
      return uploaded
    } catch (e: unknown) {
      mediaError.value = e instanceof Error ? e.message : '上传失败'
      return null
    } finally {
      uploadLoading.value = false
    }
  }

  /** @deprecated P4a 起上传不再自动分析，请用 `uploadMedia`；保留别名只为不遗漏旧调用点。 */
  const uploadAndAnalyze = uploadMedia

  /**
   * 修改素材所属患者：调 `PUT /api/media/{id}/patient`，成功后**只局部更新列表**，
   * 不重新拉整页（素材库按患者分组，改完分组会自然重算）。
   * `local-video` 是纯前端 blob 素材（没有后端记录），只改本地字段、跳过请求。
   */
  async function renamePatient(id: string, patient: string) {
    const name = (patient ?? '').trim()
    const saved = id === 'local-video' ? name : await renamePatientApi(id, name)
    const item = mediaList.value.find((m) => m.id === id)
    if (item) item.patient = saved
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

  function setPatientInfo(info: typeof patientInfo.value) {
    patientInfo.value = info
  }

  return {
    mediaList, mediaLoading, mediaError, selectedMediaId,
    analyzing, currentFrame, bdiHistory, faceImageData, heatmapData,
    inferenceTimeMs, analysisProgress, wsConnected, analysisRunId,
    currentScore, severity, severityLabel, severityColor, severityTextColor, suggestion, selectedMedia,
    patientInfo, setPatientInfo,
    faceFrameHistory,
    ignoreIncomingWsFrames, singleFaceImageMode, singleFaceImageUrl, singleFaceLabel,
    loadMediaList, removeMedia, startAnalysis, uploadMedia, uploadAndAnalyze, uploadLoading,
    renamePatient, handleFrame, handleWsMessage, setWsConnected, reset,
    exitMainDisplayKeepFaceFrames, clearFaceFrameHistory,
    applySingleFrameAnalysisResult, switchVideoAnalysisToSingleFaceImage,
    localVideoUrl, localVideoName, setLocalVideo,
    vlmAnalysis,
  }
})
