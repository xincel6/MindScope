export interface MediaItem {
  id: string
  name: string
  type: 'image' | 'video'
  thumbnail_url: string
  url: string
  duration?: number
  /** 所属患者名；后端 MediaItemOut 已返回该字段，null/空串 = 未标注（P4a 新增） */
  patient?: string | null
  created_at: string
}

export interface AnalysisFrame {
  frame_id: number
  timestamp: number
  bdi_score: number
  aligned_face: string
  heatmap_data: number[][]
  inference_time_ms: number
  progress: number
}

import { apiFetch, parseApiError } from '@/api/http'

export async function fetchMediaList(): Promise<MediaItem[]> {
  const res = await apiFetch('/api/media/list')
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const data = await res.json()
  return data.items ?? data
}

/**
 * 上传素材（P4a 新增）。
 * 后端签名：`POST /api/upload/image`，`patient` 是 **query 参数**
 * （`backend/routers/upload.py` 的 `upload_image(file: UploadFile = File(...),
 * patient: Optional[str] = Query(None, ...))`），不是 form 字段。
 * 返回里没有 `created_at`：上传时间就用当天日期兜底，保证「最新在前」排序正确。
 */
export async function uploadMedia(file: File, patient?: string): Promise<MediaItem> {
  const form = new FormData()
  form.append('file', file)
  const trimmed = (patient ?? '').trim()
  const query = trimmed ? `?patient=${encodeURIComponent(trimmed)}` : ''
  const res = await apiFetch(`/api/upload/image${query}`, { method: 'POST', body: form })
  if (!res.ok) throw new Error(await parseApiError(res, '上传失败'))
  const data = await res.json()
  return {
    id: data.id,
    name: data.name,
    type: data.type,
    thumbnail_url: data.thumbnail_url ?? '',
    url: data.url,
    patient: data.patient ?? null,
    created_at: new Date().toISOString().split('T')[0],
  }
}

/**
 * 修改素材所属患者（P4a 新增）。
 * 后端签名：`PUT /api/media/{media_id}/patient`，body `PatientUpdateIn { patient?: string }`
 * （`backend/routers/media.py`），`patient` 传空串/null 表示清除；超过 64 字符返回 400。
 * 返回值是后端实际保存后的患者名。
 */
export async function renamePatient(id: string, patient: string): Promise<string> {
  const res = await apiFetch(`/api/media/${encodeURIComponent(id)}/patient`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ patient }),
  })
  if (!res.ok) throw new Error(await parseApiError(res, '修改所属患者失败'))
  const data = await res.json().catch(() => ({}))
  return typeof data?.patient === 'string' ? data.patient : patient
}

export async function deleteMedia(id: string): Promise<void> {
  const res = await apiFetch(`/api/media/${encodeURIComponent(id)}`, { method: 'DELETE' })
  if (!res.ok) throw new Error(await parseApiError(res))
}

export async function triggerAnalysis(id: string): Promise<{ task_id: string }> {
  const res = await apiFetch('/api/analyze', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id }),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

/** 单张对齐人脸 base64 → LMTformer 抑郁分数（与实时帧 aligned_face 格式一致） */
export async function analyzeFaceBase64(imageBase64: string): Promise<{
  bdi_score: number
  inference_time_ms: number
  heatmap_data: number[][]
}> {
  const res = await apiFetch('/api/analyze/face', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ image_base64: imageBase64 }),
  })
  if (!res.ok) throw new Error(await parseApiError(res))
  return res.json()
}

// --- Report list ---
export interface ReportListItem {
  id: number
  media_id: number
  media_name: string
  media_type: string
  bdi_score: number
  severity: string
  detected_at: string
  inference_time_ms: number
}

// --- Stats ---
export interface StatsData {
  total_analyses: number
  total_media: number
  severity_distribution: Record<string, number>
  avg_inference_time_ms: number
  bdi_trend: { date: string; avg_score: number }[]
  recent_reports: ReportListItem[]
}

export async function fetchStats(): Promise<StatsData> {
  const res = await apiFetch('/api/stats')
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

export async function fetchReports(params?: {
  severity?: string
  media_type?: string
  page?: number
  limit?: number
}): Promise<{ items: ReportListItem[]; total: number }> {
  const query = new URLSearchParams()
  if (params?.severity) query.set('severity', params.severity)
  if (params?.media_type) query.set('media_type', params.media_type)
  if (params?.page) query.set('page', String(params.page))
  if (params?.limit) query.set('limit', String(params.limit))
  const res = await apiFetch(`/api/reports?${query}`)
  if (!res.ok) throw new Error(await parseApiError(res, `加载报告列表失败（HTTP ${res.status}）`))
  return res.json()
}

// --- Report detail ---
/**
 * 后端签名：`GET /api/report/{media_id}`，路径参数是 **int**
 * （`backend/routers/report.py`），返回的是该素材的报告数组（按 detected_at 倒序），
 * 不是单个对象；素材不存在时返回空数组。
 */
export interface ReportDetail {
  id: number
  media_id: number
  bdi_score: number
  severity: string
  detected_at: string
  inference_time_ms: number
  notes: string | null
}

export async function fetchReportDetail(mediaId: number): Promise<ReportDetail[]> {
  if (!Number.isInteger(mediaId) || mediaId <= 0) {
    throw new Error('素材编号必须是正整数')
  }
  const res = await apiFetch(`/api/report/${mediaId}`)
  if (!res.ok) throw new Error(await parseApiError(res, `加载报告详情失败（HTTP ${res.status}）`))
  const data = await res.json()
  return Array.isArray(data) ? data : []
}
