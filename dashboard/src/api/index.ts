export interface MediaItem {
  id: string
  name: string
  type: 'image' | 'video'
  thumbnail_url: string
  url: string
  duration?: number
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
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}
