/**
 * DTO → 领域模型映射器 · 全工程**唯一**的 snake_case ↔ camelCase 转换点
 *
 * 硬规则（docs/本轮开发交接.md 第 5.1、5.2 节）：
 *  1. **每个字段手写赋值**，禁止对象展开 `{...dto}` —— ArkTS 不支持 `arkts-no-spread`，
 *     且显式赋值才能在服务端加字段时立刻暴露编译错误。
 *  2. **`as` 只是编译期断言，不做运行时转换**。`JSON.parse` 出来的 `media_id`
 *     到底是不是 number、`severity` 是不是合法枚举，都必须在这里显式归一化。
 *  3. 所有 `mediaId` 出海前一律 `normalizeMediaId()` → 字符串。
 */

import { MediaType, SeverityLevel } from './enums';
import {
  AnalysisFrameDto, BdiTrendPointDto, FaceAnalyzeOutDto, MediaItemOutDto,
  ReportListItemDto, ReportOutDto, StatsOutDto, UploadImageOutDto, UserOutDto
} from './dto';
import {
  AnalysisFrameModel, BdiTrendPointModel, DiagnosisReportModel, DiagnosisReportNotes, FaceAnalyzeModel,
  HealthModel, MediaItemModel, ReportListItemModel, ReportPageModel, SeverityBucketModel,
  StatsModel, UserModel
} from './model';
import { UiConstant } from './constant';

/**
 * RDB 行记录的类型别名
 *
 * ★ ArkTS 不支持结构化类型（`arkts-no-structural-typing`），
 *   形如 `{id: ..., name: ...}` 的不同 interface 之间**不能互相赋值**；
 *   `Record<string, T>` 是 ArkTS 明确支持的 4 个工具类型之一，跨层传递行记录用它最稳。
 *   取值类型写成 `Object | null`：RDB 的 NULL 列要能直接塞进来。
 */
export type DbRow = Record<string, Object | null>;

/**
 * ★ 归一化核心：把「可能是字符串、也可能是数字」的 id 统一成字符串。
 * 后端 `MediaItemOut.id` 是 str，`ReportListItem.media_id` 是 int，
 * 混用会让列表选中/删除**静默失效**（`12 === '12'` 为 false）。
 */
export function normalizeMediaId(raw: number | string): string {
  return typeof raw === 'string' ? raw : raw.toString();
}

/** 把任意数字归一化成安全数字（NaN/undefined → 兜底值） */
function toNumber(raw: number | undefined, fallback: number): number {
  if (raw === undefined || raw === null) {
    return fallback;
  }
  return Number.isFinite(raw) ? raw : fallback;
}

/** 把任意值归一化成安全字符串 */
function toText(raw: string | null | undefined, fallback: string): string {
  if (raw === undefined || raw === null) {
    return fallback;
  }
  return raw;
}

/** 枚举安全转换：后端下发未知取值时兜底，避免 UI 出现空白标签 */
function toSeverity(raw: string): SeverityLevel {
  if (raw === (SeverityLevel.mild as string)) {
    return SeverityLevel.mild;
  }
  if (raw === (SeverityLevel.moderate as string)) {
    return SeverityLevel.moderate;
  }
  if (raw === (SeverityLevel.severe as string)) {
    return SeverityLevel.severe;
  }
  return SeverityLevel.none;
}

/** 枚举安全转换：未知类型一律当图片处理（后端只有 image / video） */
function toMediaType(raw: string): MediaType {
  return raw === (MediaType.video as string) ? MediaType.video : MediaType.image;
}

/** 二维数组归一化 · 保证 heatmap 一定是 number[][]，不会是 undefined / string */
function normalizeMatrix(raw: number[][] | undefined): number[][] {
  if (raw === undefined || raw === null) {
    return [];
  }
  const out: number[][] = [];
  for (let i = 0; i < raw.length; i++) {
    const row: number[] | undefined = raw[i];
    if (row === undefined) {
      out.push([]);
      continue;
    }
    const cells: number[] = [];
    for (let j = 0; j < row.length; j++) {
      const cell: number = row[j];
      cells.push(Number.isFinite(cell) ? cell : 0);
    }
    out.push(cells);
  }
  return out;
}

/**
 * 生成后端同款日期串 "YYYY-MM-DD"（本地时区）。
 * ★ 绝不能用 `Date.prototype.toISOString()` —— 它带 `Z` 时区偏移，
 *   在东八区会把 10-14 的 00:30 写成 "2026-10-13"，与后端 `%Y-%m-%d` 不一致。
 */
export function formatDateLocal(date: Date): string {
  const y: number = date.getFullYear();
  const m: number = date.getMonth() + 1;
  const d: number = date.getDate();
  return `${y}-${m < 10 ? '0' : ''}${m}-${d < 10 ? '0' : ''}${d}`;
}

/** 生成后端同款日期时间串 "YYYY-MM-DD HH:mm:ss" */
export function formatDateTimeLocal(date: Date): string {
  const hh: number = date.getHours();
  const mm: number = date.getMinutes();
  const ss: number = date.getSeconds();
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${formatDateLocal(date)} ${pad(hh)}:${pad(mm)}:${pad(ss)}`;
}

/**
 * 数据映射总入口 · 所有对外转换方法集中在此，便于阅读与替换。
 * 全部为静态方法，不做实例状态，可直接 `Mapper.toMediaItem(dto)` 调用。
 */
export class Mapper {
  // ────────────────────────── 鉴权 ──────────────────────────

  /** GET /api/auth/me → UserModel */
  public static toUser(dto: UserOutDto): UserModel {
    const user: UserModel = {
      id: toNumber(dto.id, 0),
      username: toText(dto.username, ''),
      email: toText(dto.email, ''),
      createdAt: toText(dto.created_at, '')
    };
    return user;
  }

  // ────────────────────────── 媒体 ──────────────────────────

  /** GET /api/media/list 元素 → MediaItemModel */
  public static toMediaItem(dto: MediaItemOutDto): MediaItemModel {
    const item: MediaItemModel = {
      id: normalizeMediaId(dto.id),
      name: toText(dto.name, ''),
      type: toMediaType(dto.type),
      thumbnailUrl: toText(dto.thumbnail_url, ''),
      url: toText(dto.url, ''),
      duration: dto.duration === undefined || dto.duration === null ? null : dto.duration,
      createdAt: toText(dto.created_at, ''),
      patient: toText(dto.patient, '')
    };
    return item;
  }

  /** GET /api/media/list → MediaItemModel[] */
  public static toMediaItems(dtos: MediaItemOutDto[] | undefined): MediaItemModel[] {
    const out: MediaItemModel[] = [];
    if (dtos === undefined || dtos === null) {
      return out;
    }
    for (let i = 0; i < dtos.length; i++) {
      out.push(Mapper.toMediaItem(dtos[i]));
    }
    return out;
  }

  /**
   * POST /api/upload/image → MediaItemModel
   * ★ 后端只回 `{id, name, type, url}` 四个字段，缺 thumbnail_url / duration / created_at，
   *   这里按 Web 端同款策略补齐：缩略图留空由端上自行处理，时长置 null，
   *   created_at 用**本地日期**（%Y-%m-%d）拼，不用 toISOString()。
   */
  public static toUploadedMedia(dto: UploadImageOutDto, now: Date): MediaItemModel {
    const item: MediaItemModel = {
      id: normalizeMediaId(dto.id),
      name: toText(dto.name, ''),
      type: toMediaType(dto.type),
      thumbnailUrl: '',
      url: toText(dto.url, ''),
      duration: null,
      createdAt: formatDateLocal(now),
      patient: toText(dto.patient, '')
    };
    return item;
  }

  // ────────────────────────── 报告 ──────────────────────────

  /** GET /api/report/{media_id} 元素 → DiagnosisReportModel */
  public static toDiagnosisReport(dto: ReportOutDto): DiagnosisReportModel {
    const report: DiagnosisReportModel = {
      id: toNumber(dto.id, 0),
      mediaId: normalizeMediaId(dto.media_id),
      bdiScore: toNumber(dto.bdi_score, 0),
      severity: toSeverity(dto.severity),
      detectedAt: toText(dto.detected_at, ''),
      inferenceTimeMs: toNumber(dto.inference_time_ms, 0),
      notes: toText(dto.notes, '')
    };
    return report;
  }

  /** GET /api/report/{media_id} → DiagnosisReportModel[] */
  public static toDiagnosisReports(dtos: ReportOutDto[] | undefined): DiagnosisReportModel[] {
    const out: DiagnosisReportModel[] = [];
    if (dtos === undefined || dtos === null) {
      return out;
    }
    for (let i = 0; i < dtos.length; i++) {
      out.push(Mapper.toDiagnosisReport(dtos[i]));
    }
    return out;
  }

  /** GET /api/reports 元素 → ReportListItemModel */
  public static toReportListItem(dto: ReportListItemDto): ReportListItemModel {
    const item: ReportListItemModel = {
      id: toNumber(dto.id, 0),
      mediaId: normalizeMediaId(dto.media_id),
      mediaName: toText(dto.media_name, ''),
      mediaType: toMediaType(dto.media_type),
      bdiScore: toNumber(dto.bdi_score, 0),
      severity: toSeverity(dto.severity),
      detectedAt: toText(dto.detected_at, ''),
      inferenceTimeMs: toNumber(dto.inference_time_ms, 0)
    };
    return item;
  }

  /** GET /api/reports 元素数组 → ReportListItemModel[] */
  public static toReportListItems(dtos: ReportListItemDto[] | undefined): ReportListItemModel[] {
    const out: ReportListItemModel[] = [];
    if (dtos === undefined || dtos === null) {
      return out;
    }
    for (let i = 0; i < dtos.length; i++) {
      out.push(Mapper.toReportListItem(dtos[i]));
    }
    return out;
  }

  /** GET /api/reports → ReportPageModel */
  public static toReportPage(
    items: ReportListItemDto[] | undefined, total: number, page: number, pageSize: number
  ): ReportPageModel {
    const list: ReportListItemModel[] = Mapper.toReportListItems(items);
    const safeTotal: number = toNumber(total, list.length);
    const result: ReportPageModel = {
      items: list,
      total: safeTotal,
      page: page,
      pageSize: pageSize,
      hasMore: page * pageSize < safeTotal
    };
    return result;
  }

  // ────────────────────────── 统计 ──────────────────────────

  private static toBdiTrendPoint(dto: BdiTrendPointDto): BdiTrendPointModel {
    const point: BdiTrendPointModel = {
      date: toText(dto.date, ''),
      avgScore: toNumber(dto.avg_score, 0)
    };
    return point;
  }

  /** GET /api/stats → StatsModel */
  public static toStats(dto: StatsOutDto): StatsModel {
    const trend: BdiTrendPointModel[] = [];
    const rawTrend: BdiTrendPointDto[] | undefined = dto.bdi_trend;
    if (rawTrend !== undefined && rawTrend !== null) {
      for (let i = 0; i < rawTrend.length; i++) {
        trend.push(Mapper.toBdiTrendPoint(rawTrend[i]));
      }
    }
    const stats: StatsModel = {
      totalAnalyses: toNumber(dto.total_analyses, 0),
      totalMedia: toNumber(dto.total_media, 0),
      severityDistribution: Mapper.normalizeDistribution(dto.severity_distribution),
      avgInferenceTimeMs: toNumber(dto.avg_inference_time_ms, 0),
      bdiTrend: trend,
      recentReports: Mapper.toReportListItems(dto.recent_reports)
    };
    return stats;
  }

  /**
   * 严重度分布归一化：后端 dict 可能缺档位，这里补齐 none/mild/moderate/severe 四档，
   * 避免 UI 图例数量随数据抖动。
   */
  public static normalizeDistribution(raw: Record<string, number> | undefined): Record<string, number> {
    const out: Record<string, number> = {};
    out[SeverityLevel.none as string] = Mapper.pickCount(raw, SeverityLevel.none as string);
    out[SeverityLevel.mild as string] = Mapper.pickCount(raw, SeverityLevel.mild as string);
    out[SeverityLevel.moderate as string] = Mapper.pickCount(raw, SeverityLevel.moderate as string);
    out[SeverityLevel.severe as string] = Mapper.pickCount(raw, SeverityLevel.severe as string);
    return out;
  }

  private static pickCount(raw: Record<string, number> | undefined, key: string): number {
    if (raw === undefined || raw === null) {
      return 0;
    }
    const value: number | undefined = raw[key];
    return value === undefined ? 0 : toNumber(value, 0);
  }

  /**
   * 把 `Record<string, number>` 摊平成数组 —— ArkUI 的 `ForEach` 只吃数组。
   * @param total 用于计算占比；传 0 时占比按各项之和自行推算
   */
  public static toSeverityBuckets(distribution: Record<string, number>, total: number): SeverityBucketModel[] {
    const sum: number = total > 0 ? total : Mapper.sumDistribution(distribution);
    const out: SeverityBucketModel[] = [];
    const levels: SeverityLevel[] = UiConstant.severityList;
    for (let i = 0; i < levels.length; i++) {
      const level: SeverityLevel = levels[i];
      const count: number = Mapper.pickCount(distribution, level as string);
      const bucket: SeverityBucketModel = {
        severity: level,
        label: UiConstant.severityMeta(level).label,
        count: count,
        color: UiConstant.severityMeta(level).color,
        ratio: sum > 0 ? count / sum : 0
      };
      out.push(bucket);
    }
    return out;
  }

  private static sumDistribution(distribution: Record<string, number>): number {
    const levels: SeverityLevel[] = UiConstant.severityList;
    let sum: number = 0;
    for (let i = 0; i < levels.length; i++) {
      sum += Mapper.pickCount(distribution, levels[i] as string);
    }
    return sum;
  }

  // ────────────────────────── 分析 ──────────────────────────

  /** WS 帧 → AnalysisFrameModel · ★ 逐字段拷贝（ArkTS 无对象展开） */
  public static toAnalysisFrame(raw: AnalysisFrameDto): AnalysisFrameModel {
    const frame: AnalysisFrameModel = {
      frameId: toNumber(raw.frame_id, 0),
      timestamp: toNumber(raw.timestamp, 0),
      bdiScore: toNumber(raw.bdi_score, 0),
      alignedFace: toText(raw.aligned_face, ''),
      heatmapData: normalizeMatrix(raw.heatmap_data),
      inferenceTimeMs: toNumber(raw.inference_time_ms, 0),
      progress: toNumber(raw.progress, 0)
    };
    return frame;
  }

  /** POST /api/analyze/face → FaceAnalyzeModel */
  public static toFaceAnalyze(dto: FaceAnalyzeOutDto): FaceAnalyzeModel {
    const result: FaceAnalyzeModel = {
      bdiScore: toNumber(dto.bdi_score, 0),
      inferenceTimeMs: toNumber(dto.inference_time_ms, 0),
      heatmapData: normalizeMatrix(dto.heatmap_data)
    };
    return result;
  }

  /** GET /health → HealthModel */
  public static toHealth(status: string): HealthModel {
    const health: HealthModel = {
      ok: status === 'ok',
      status: toText(status, 'unknown')
    };
    return health;
  }

  // ────────────────────────── 领域模型 ↔ RDB 行记录 ──────────────────────────
  //
  // 往返链路（每一跳都显式、可查）：
  //   DTO ──Mapper.toMediaItem()──▶ 领域模型 ──Mapper.toMediaRow()──▶ RDB
  //   RDB ──Mapper.toMediaItemFromRow()──▶ 领域模型 ──▶ store ──▶ UI
  //
  // ★ 物理列名沿用服务端 snake_case（镜像表刻意与服务端同构），
  //   所以这一节里出现字符串形式的 snake_case 是**刻意的**，见 DbSchema.ets 顶部说明。

  /** 领域模型 → media_asset 行 */
  public static toMediaRow(item: MediaItemModel): DbRow {
    const row: DbRow = {};
    row['id'] = item.id;
    row['name'] = item.name;
    row['type'] = item.type as string;
    row['file_path'] = item.url;
    row['thumbnail_url'] = item.thumbnailUrl;
    row['duration'] = item.duration === null ? null : item.duration;
    row['created_at'] = item.createdAt;
    row['patient'] = item.patient;
    return row;
  }

  /** media_asset 行 → 领域模型 */
  public static toMediaItemFromRow(row: DbRow): MediaItemModel {
    const rawDuration: Object | undefined = row['duration'];
    const item: MediaItemModel = {
      id: normalizeMediaId(toText(row['id'] as string | null, '')),
      name: toText(row['name'] as string | null, ''),
      type: toMediaType(toText(row['type'] as string | null, 'image')),
      thumbnailUrl: toText(row['thumbnail_url'] as string | null, ''),
      url: toText(row['file_path'] as string | null, ''),
      duration: rawDuration === undefined || rawDuration === null ? null : toNumber(rawDuration as number, 0),
      createdAt: toText(row['created_at'] as string | null, ''),
      patient: toText(row['patient'] as string | null, '')
    };
    return item;
  }

  /** 领域模型 → diagnosis_report 行 */
  public static toReportRow(item: ReportListItemModel): DbRow {
    const row: DbRow = {};
    row['id'] = item.id;
    row['media_id'] = item.mediaId;
    row['media_name'] = item.mediaName;
    row['media_type'] = item.mediaType as string;
    row['bdi_score'] = item.bdiScore;
    row['severity'] = item.severity as string;
    row['detected_at'] = item.detectedAt;
    row['inference_time_ms'] = item.inferenceTimeMs;
    row['notes'] = '';
    return row;
  }

  /** diagnosis_report 行 → 领域模型（列表项形状） */
  public static toReportItemFromRow(row: DbRow): ReportListItemModel {
    const item: ReportListItemModel = {
      id: toNumber(row['id'] as number, 0),
      mediaId: normalizeMediaId(toText(row['media_id'] as string | null, '')),
      mediaName: toText(row['media_name'] as string | null, ''),
      mediaType: toMediaType(toText(row['media_type'] as string | null, 'image')),
      bdiScore: toNumber(row['bdi_score'] as number, 0),
      severity: toSeverity(toText(row['severity'] as string | null, 'none')),
      detectedAt: toText(row['detected_at'] as string | null, ''),
      inferenceTimeMs: toNumber(row['inference_time_ms'] as number, 0)
    };
    return item;
  }

  /**
   * 明细报告（含 notes）→ diagnosis_report 行
   * 列表项不带 notes，详情接口带；两者写同一张表，notes 单独补写。
   */
  public static toReportRowFromDetail(item: DiagnosisReportModel, mediaName: string, mediaType: MediaType): DbRow {
    const row: DbRow = {};
    row['id'] = item.id;
    row['media_id'] = item.mediaId;
    row['media_name'] = mediaName;
    row['media_type'] = mediaType as string;
    row['bdi_score'] = item.bdiScore;
    row['severity'] = item.severity as string;
    row['detected_at'] = item.detectedAt;
    row['inference_time_ms'] = item.inferenceTimeMs;
    row['notes'] = item.notes;
    return row;
  }

  /** diagnosis_report 行 → 明细报告（含 notes） */
  public static toDiagnosisReportFromRow(row: DbRow): DiagnosisReportModel {
    const item: DiagnosisReportModel = {
      id: toNumber(row['id'] as number, 0),
      mediaId: normalizeMediaId(toText(row['media_id'] as string | null, '')),
      bdiScore: toNumber(row['bdi_score'] as number, 0),
      severity: toSeverity(toText(row['severity'] as string | null, 'none')),
      detectedAt: toText(row['detected_at'] as string | null, ''),
      inferenceTimeMs: toNumber(row['inference_time_ms'] as number, 0),
      notes: toText(row['notes'] as string | null, '')
    };
    return item;
  }

  /** 列表项（不带 notes）→ 明细报告 · 列表页同步后用详情接口补齐 notes */
  public static toDiagnosisReportFromItem(item: ReportListItemModel, notes: string): DiagnosisReportModel {
    const report: DiagnosisReportModel = {
      id: item.id,
      mediaId: item.mediaId,
      bdiScore: item.bdiScore,
      severity: item.severity,
      detectedAt: item.detectedAt,
      inferenceTimeMs: item.inferenceTimeMs,
      notes: notes
    };
    return report;
  }

  /** 投影行（report_id + notes）→ 备注载体 */
  public static toReportNotesFromRow(row: DbRow): DiagnosisReportNotes {
    const notes: DiagnosisReportNotes = {
      key: toText(row['report_id'] as string | null, ''),
      notes: toText(row['notes'] as string | null, '')
    };
    return notes;
  }

  /**
   * 单行快照表的 payload 列 → 字符串
   * 统计快照与工作台评估快照都使用 `payload` 列；由调用方再 JSON.parse。
   */
  public static payloadFromRow(row: DbRow): string {
    return toText(row['payload'] as string | null, '');
  }
}
