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

import { MediaType, SeverityLevel, TaskStatus } from './enums';

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
  /** 所属患者名 · 空串表示未命名 */
  patient: string;
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
  /** 上传该素材的账号名 · 旧数据可能为空 */
  uploaderName: string;
  bdiScore: number;
  severity: SeverityLevel;
  detectedAt: string;
  inferenceTimeMs: number;
}

/**
 * 历史报告按素材聚合后的一项
 *
 * 同一 mediaId 可能被重复分析多次，服务端会写多条 diagnosis_report。
 * 历史页按 mediaId 聚合成一张卡，`latest` 用于展示和打开详情，
 * 分析次数与分数范围用于提示同一素材是否产生过不同结果。
 */
export interface ReportMediaGroupModel {
  mediaId: string;
  latest: ReportListItemModel;
  analysisCount: number;
  minBdiScore: number;
  maxBdiScore: number;
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

/**
 * **一次分析的归档会话**（按 `mediaId` 归档，一个素材一条）
 *
 * ────────────────── 为什么需要它 ──────────────────
 * 旧实现只有"一份全局帧缓冲"：开始分析 B 时把 A 的帧清空，历史素材页又拿
 * "全局最新一帧"顶替 → 结果就是「换一个素材，所有素材的热力图都变成最近那个人」。
 * 归档改成**按素材存**：同一素材再次分析只覆盖它自己那一条，其它素材的结果保留。
 *
 * ★ 与 `AnalysisState` 的分工（避免两份真相）：
 *   · `AnalysisState` 只保留"当前 live 会话的指针"（mediaId / running / 进度 / 末帧…）；
 *   · 逐帧数据（`frames` / `scores`）**只存在于本结构的会话里**，live 会话就是
 *     归档里 `mediaId === liveMediaId` 的那一条。
 *
 * ★ 只在内存里，App 重启即消失（本轮非目标：不做持久化，见交付说明）。
 */
export interface AnalysisSessionModel {
  /** 服务端媒体 id（字符串，已归一化） */
  mediaId: string;
  /** 素材类型 · 决定"图片 = 单帧 / 视频 = 逐帧"的所有展示语义 */
  mediaType: MediaType;
  /** 会话状态：running / done / failed */
  status: TaskStatus;
  /** 0–1 */
  progress: number;
  /** 最新分数（done 之后为 done 消息里的 finalScore） */
  score: number;
  /** **实际收到的帧数**（不因 frames 尾部裁剪而变小，图片恒为 1） */
  frameCount: number;
  /**
   * 逐帧结果（含各自的人脸图与 16×16 热度矩阵）· 供横向逐帧列表
   * ★ live 期间上限 90 帧，收尾后裁剪到 30 帧（内存可控）
   */
  frames: AnalysisFrameModel[];
  /**
   * **首帧**的对齐人脸图（裸 base64，无 `data:` 前缀）· 空串表示还没收到任何帧
   *
   * ★ 为什么不直接用 `frames[0]`：`frames` 为省内存会被裁剪，而且是**从头部切**
   *   （live 只留最后 90 帧、收尾裁到 30 帧）。视频跑完后 `frames[0]` 早已不是
   *   真正的第一帧；而工作台「当前任务」卡片要展示的正是"这次分析的第一帧照片"。
   *   所以首帧图单独存一份、**永不裁剪**（一张 128×128 JPEG 约 5–15KB，代价可忽略）。
   */
  firstFrameFace: string;
  /**
   * 逐帧 BDI 分数（整数）· 供情绪曲线
   * ★ 与 `frames` 分开存：帧数组会为省内存被裁剪，而曲线要看完整走势
   */
  scores: number[];
  /** VLM 文本解读（可能一直为空） */
  vlmText: string;
  /** 失败/重连文案（空串表示无错） */
  errorMsg: string;
  /** 最近一次写入时刻（毫秒）· 归档淘汰按它排序 */
  updatedAt: number;
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

// ───────────────────────────── 工作台 ─────────────────────────────

/**
 * 工作台「当前任务」· 一次分析的会话摘要
 *
 * ★ 它**不是**新数据源，而是 `AppStore` 上几个 `@Trace` 字段的只读投影：
 *   由窗口层在"开始分析 / 收到 done / 收到 error"三个时机刷新。
 *   这样工作台的「当前任务」卡片不需要自己拼 store 里的零散字段。
 */
export interface CurrentTaskModel {
  mediaId: string;
  /** 素材名（原始文件名） */
  mediaName: string;
  mediaType: MediaType;
  status: TaskStatus;
  /** 0–1 */
  progress: number;
  /** 最新 BDI 分数（未出分时为 0） */
  bdiScore: number;
  /** 失败文案（status = failed 时非空） */
  errorMsg: string;
  /**
   * 首帧照片 · 可直接喂给 `Image` 的地址
   *
   * 取值顺序（由 `AppStore.currentTask()` 决定，组件不再做判断）：
   *   ① 该素材会话里的**首帧对齐人脸**（data URL）—— 图片=那唯一一帧，视频=采样出的第一帧；
   *   ② 首帧还没到但媒体库有缩略图（图片上传后后端会生成）→ 用缩略图；
   *   ③ 都没有（视频刚上传、还没收到帧）→ 空串，组件画占位块。
   */
  firstFrameUrl: string;
  /** BDI 填充比例 = `bdiScore / BDI_MAX_SCORE`，0–1（进度条用；未出分时为 0） */
  scoreRatio: number;
  /** BDI 档位中文标签（正常 / 轻度 / 中度 / 重度）· 未出分时为空串 */
  severityLabel: string;
  /**
   * BDI 档位色（四档严重度色，**不是**错误危险色 `UiTheme.danger`）
   * ★ 未出分时取中性次要文字色：此时进度条是空的，颜色不该暗示任何档位。
   */
  severityColor: string;
}

/**
 * 工作台「最近使用的素材」一行
 *
 * ★ 数据是**两个 store 拼出来的**，后端没有这个接口：
 *   分数/档位来自 `reportItems`（按 detected_at 倒序），
 *   缩略图/文件名来自 `mediaItems`（按 mediaId 关联）。
 *   所以 mediaItems 缺失时（离线且无缓存）缩略图为空串，UI 必须能降级。
 */
export interface RecentMediaModel {
  mediaId: string;
  name: string;
  type: MediaType;
  /** 已拼好的绝对地址；空串表示无缩略图（视频场景后端不生成） */
  thumbnailUrl: string;
  /** BDI 分数，0–63 */
  bdiScore: number;
  severity: SeverityLevel;
  /** 档位中文标签（正常/轻度/中度/重度） */
  severityLabel: string;
  /** 档位颜色（来自 UiConstant.severityMeta） */
  severityColor: string;
  /** 进度条填充比例 = bdiScore / BDI_MAX_SCORE，0–1 */
  scoreRatio: number;
  /** "YYYY-MM-DD HH:mm:ss" */
  detectedAt: string;
}

// ───────────────────────────── 素材选择 ─────────────────────────────

/**
 * 用户从系统选择器选中的素材
 *
 * ★ 必须带 `type`：系统选择器只返回 URI，不告诉我们这是图片还是视频，
 *   而工作台要按类型显示「图片 / 视频」。类型判定在 `common/MediaPicker.ets`
 *   里按扩展名 + MIME 双条件做，判定结果存这里。
 */
export interface PickedMediaModel {
  /** 系统相册 URI（形如 file://media/Photo/12/IMG_xxx/IMG_20260101_120000.jpg）· 只用于 `Image` 预览 */
  uri: string;
  /**
   * 上传用的**应用沙箱绝对路径**（形如 `<cacheDir>/picked/IMG_20260101_120000.jpg`）
   *
   * ★★ 为什么不能直接拿 `uri` 去上传（真机实测踩过，见 `BUG清单.md` BUG-12）：
   *   相册 URI 是**媒体库 provider 的 URI**，不是文件系统路径。上传走
   *   `http.MultiFormData.filePath`，它只认本地路径，吃这个 URI 会抛
   *   **2300026 "Failed to open or read local data from the file or application"**，
   *   看起来像"服务端连不上"，实际请求连正文都没读出来。
   *   所以 `MediaPicker` 选完会先 `fs.copyFile` 到应用缓存，再把这个路径交给上传。
   */
  uploadPath: string;
  /** 用于上传的文件名（后端把它写进 media_assets.name，会显示在列表上） */
  fileName: string;
  /** MIME，如 image/jpeg；不确定时为 application/octet-stream */
  mimeType: string;
  /** 图片还是视频（按扩展名判定） */
  type: MediaType;
}
