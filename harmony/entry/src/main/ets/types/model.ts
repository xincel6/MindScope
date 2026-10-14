/**
 * 领域模型 · 字段名**全部严格驼峰**，UI 层只认这一层
 *
 * 边界（docs/本轮开发交接.md 第 5.1 节）：
 *   dto.ts  ──(mapper.ts 显式逐字段转换)──▶  model.ts  ──▶  store  ──▶  UI
 * snake_case 只活在该 `.ts` 文件里；出了 mapper 一律驼峰。
 *
 * ArkTS 约束提醒：
 *  - 全部声明为 `interface`（JSON.parse 的结果不能用 class 接）
 *  - 不支持索引签名，动态字典用 `Record<string, T>`
 *  - 不支持交叉类型 `A & B`，需要组合时用 `extends`
 */

import { MediaType, SeverityLevel } from './enums';

// ───────────────────────────── 鉴权 ─────────────────────────────

/** 当前登录用户 */
export interface UserModel {
  id: number;
  username: string;
  email: string;
  /** 注册日期 "YYYY-MM-DD" */
  createdAt: string;
}

/** 登录/注册成功后写入内存与磁盘的会话 */
export interface SessionModel {
  accessToken: string;
  tokenType: string;
  /** 令牌落盘时间（毫秒时间戳），用于过期前的本地预判 */
  savedAt: number;
}

// ───────────────────────────── 媒体 ─────────────────────────────

/**
 * 媒体条目 · **全链路统一用字符串 id**
 * 由 `mapper.toMediaItem()` 调 `normalizeMediaId()` 归一化，
 * 规避「MediaItemOut.id 是字符串 / ReportListItem.media_id 是数字」导致的选中失效。
 */
export interface MediaItemModel {
  id: string;
  name: string;
  type: MediaType;
  thumbnailUrl: string;
  url: string;
  /** 图片无时长，为 null */
  duration: number | null;
  /** "YYYY-MM-DD" */
  createdAt: string;
}

// ───────────────────────────── 报告 ─────────────────────────────

/** 单条诊断报告 */
export interface DiagnosisReportModel {
  id: number;
  /** ★ 已归一化为字符串，可安全与 MediaItemModel.id 比较 */
  mediaId: string;
  bdiScore: number;
  severity: SeverityLevel;
  /** "YYYY-MM-DD HH:mm:ss" */
  detectedAt: string;
  inferenceTimeMs: number;
  notes: string;
}

/** 报告列表项（已联表带上媒体名与类型） */
export interface ReportListItemModel {
  id: number;
  mediaId: string;
  mediaName: string;
  mediaType: MediaType;
  bdiScore: number;
  severity: SeverityLevel;
  detectedAt: string;
  inferenceTimeMs: number;
}

/**
 * 报告备注 · RDB 投影查询的载体
 * 列表接口不返回 `notes`，它只存在镜像表的列里；需要单独投影出来再组装。
 */
export interface DiagnosisReportNotes {
  /** 报告 id 的字符串形式（Record 的键只能是字符串） */
  key: string;
  notes: string;
}

/** 报告分页结果 */
export interface ReportPageModel {
  items: ReportListItemModel[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

/** 报告列表筛选条件 */
export interface ReportFilterModel {
  /** 空字符串 = 不筛选 */
  severity: string;
  /** 空字符串 = 不筛选 */
  mediaType: string;
  page: number;
  pageSize: number;
}

// ───────────────────────────── 统计 ─────────────────────────────

/** BDI 趋势点 */
export interface BdiTrendPointModel {
  date: string;
  avgScore: number;
}

/** 统计面板数据 */
export interface StatsModel {
  totalAnalyses: number;
  totalMedia: number;
  severityDistribution: Record<string, number>;
  avgInferenceTimeMs: number;
  bdiTrend: BdiTrendPointModel[];
  recentReports: ReportListItemModel[];
}

/** 严重度分布的一项（把 Record 摊平成数组，UI 的 ForEach 需要数组） */
export interface SeverityBucketModel {
  severity: SeverityLevel;
  label: string;
  count: number;
  color: string;
  /** 占比 0–1 */
  ratio: number;
}

// ───────────────────────────── 分析 ─────────────────────────────

/** 一帧分析结果 */
export interface AnalysisFrameModel {
  frameId: number;
  timestamp: number;
  bdiScore: number;
  /** 对齐后人脸图裸 base64（无 data: 前缀） */
  alignedFace: string;
  /** 16×16 热力图 */
  heatmapData: number[][];
  inferenceTimeMs: number;
  /** 0–1；★ 服务端会从 0 直接跳到 1，不要每帧重绘 */
  progress: number;
}

/** 面部分析结果（POST /api/analyze/face） */
export interface FaceAnalyzeModel {
  bdiScore: number;
  inferenceTimeMs: number;
  heatmapData: number[][];
}

// ───────────────────────────── 辅助 ─────────────────────────────

/** 服务端连通性 */
export interface HealthModel {
  ok: boolean;
  status: string;
}

/** 交互结果 · 需要「成功/失败 + 文案」而不抛异常时使用 */
export interface ActionResultModel {
  ok: boolean;
  message: string;
}

/** 媒体库下拉选项（筛选器用） */
export interface MediaOptionModel {
  id: string;
  name: string;
  type: MediaType;
}
