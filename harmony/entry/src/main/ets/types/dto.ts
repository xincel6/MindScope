/**
 * Wire DTO · 与服务端 `dashboard/backend/schemas.py` **逐字段 1:1**
 *
 * ★ 本文件是全工程**唯一**允许出现 snake_case 的 `.ts` 文件，且**仅限字段名**。
 *   类型名、函数名、变量名一律严格驼峰。
 * ★ 服务端字段一旦变动，只需改 `dto.ts` + `mapper.ts`，UI 层完全不感知。
 * ★ DTO 一律声明为 `interface`，**不要声明成 class**：
 *   `JSON.parse(s) as SomeClass` 拿到的对象没有原型，方法在运行时是 undefined。
 *
 * 对应后端 schemas.py 行号见行尾注释。
 */

// ───────────────────────────── 鉴权 ─────────────────────────────

/** POST /api/auth/login · 请求体 */
export interface LoginReqDto {
  username: string;
  password: string;
}

/** POST /api/auth/register · 请求体（email 为 Optional） */
export interface RegisterReqDto {
  username: string;
  password: string;
  email: string | null;
}

/** POST /api/auth/login | /api/auth/register · 响应体 */
export interface TokenOutDto {
  access_token: string;
  token_type: string;
}

/** GET /api/auth/me · 响应体（created_at 形如 "2026-06-17"） */
export interface UserOutDto {
  id: number;
  username: string;
  email: string | null;
  created_at: string;
}

// ───────────────────────────── 媒体 ─────────────────────────────

/** GET /api/media/list 的元素 · ★ id 是**字符串**，与 ReportListItem.media_id（数字）不同 */
export interface MediaItemOutDto {
  id: string;
  name: string;
  type: string;
  thumbnail_url: string;
  url: string;
  duration?: number;
  created_at: string;
  /** 所属患者名 · 空串表示未命名 */
  patient?: string;
}

/** GET /api/media/list · 响应体 */
export interface MediaListOutDto {
  items: MediaItemOutDto[];
}

/** POST /api/upload/image · 响应体 ★ 后端只回 4 个字段，其余需客户端补齐 */
export interface UploadImageOutDto {
  id: string;
  name: string;
  type: string;
  url: string;
  /** 上传时一并提交的患者名（后端回显） */
  patient?: string;
}

/** PATCH /api/media/{id}/patient · 请求体 · 给素材命名/改所属患者 */
export interface UpdatePatientReqDto {
  patient: string;
}

// ───────────────────────────── 报告 ─────────────────────────────

/** GET /api/report/{media_id} 的元素（detected_at 形如 "2026-06-17 21:03:44"） */
export interface ReportOutDto {
  id: number;
  media_id: number;
  bdi_score: number;
  severity: string;
  detected_at: string;
  inference_time_ms: number;
  notes: string | null;
}

/** GET /api/reports 的元素 · ★ media_id 是**数字** */
export interface ReportListItemDto {
  id: number;
  media_id: number;
  media_name: string;
  media_type: string;
  bdi_score: number;
  severity: string;
  detected_at: string;
  inference_time_ms: number;
}

/** GET /api/reports · 响应体 */
export interface ReportListOutDto {
  items: ReportListItemDto[];
  total: number;
}

// ───────────────────────────── 统计 ─────────────────────────────

/** GET /api/stats 中 bdi_trend 的元素 */
export interface BdiTrendPointDto {
  date: string;
  avg_score: number;
}

/** GET /api/stats · 响应体 */
export interface StatsOutDto {
  total_analyses: number;
  total_media: number;
  severity_distribution: Record<string, number>;
  avg_inference_time_ms: number;
  bdi_trend: BdiTrendPointDto[];
  recent_reports: ReportListItemDto[];
}

// ───────────────────────────── 分析 ─────────────────────────────

/** POST /api/analyze · 请求体（⚠ 该接口是空壳，不触发分析） */
export interface AnalysisReqDto {
  id: string;
}

/** POST /api/analyze · 响应体 */
export interface AnalysisResDto {
  task_id: string;
}

/** POST /api/analyze/face · 请求体 */
export interface FaceB64ReqDto {
  image_base64: string;
}

/** POST /api/analyze/face · 响应体（heatmap_data 为 16×16） */
export interface FaceAnalyzeOutDto {
  bdi_score: number;
  inference_time_ms: number;
  heatmap_data: number[][];
}

/** WS /ws/analysis 帧消息 · ★ 帧消息**没有** type 字段，全部字段可选 */
export interface AnalysisFrameDto {
  frame_id: number;
  timestamp: number;
  bdi_score: number;
  aligned_face: string;
  heatmap_data: number[][];
  inference_time_ms: number;
  progress: number;
}

/**
 * WS 入站消息联合体 · ★ 分流判据是 `type === undefined`，不是 `type === 'frame'`
 * 控制消息：status / vlm_analysis / done / error；帧消息：无 type。
 */
export interface WsInboundDto {
  type?: string;
  message?: string;
  task_id?: string;
  content?: string;
  final_score?: number;
  frame_id?: number;
  timestamp?: number;
  bdi_score?: number;
  aligned_face?: string;
  heatmap_data?: number[][];
  inference_time_ms?: number;
  progress?: number;
}

/** GET /health · 响应体 */
export interface HealthOutDto {
  status: string;
}

/**
 * 错误响应体 · ★ 422 时 `detail` 是**数组**，不能直接 `as { detail: string }`
 * 用 Object 接住，再用 typeof 显式判断（ArkTS 没有 any）
 */
export interface ErrorBodyDto {
  detail?: Object;
}
