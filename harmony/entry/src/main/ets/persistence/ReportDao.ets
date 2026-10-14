/**
 * ReportDao · diagnosis_report 镜像表的读写（`BaseDao<ReportListItemModel>` 子类）
 *
 * 承接服务端 `/api/reports` 的 `severity` / `media_type` / `page` / `limit` 过滤分页，
 * 离线时仍可查询、翻页（方案 A 的核心收益之一）。
 *
 * ★ 本表解码出的统一模型是 `ReportListItemModel`（列表项形状）；
 *   详情接口独有的 `notes` 由 `loadDetailByMedia()` 单独补出来，
 *   再交给 Mapper 组装成 `DiagnosisReportModel` —— 这样避开了 ArkTS
 *   「不支持结构化类型、两个 interface 不能互相赋值」的限制。
 */

import { relationalStore } from '@kit.ArkData';
import { BaseDao } from './BaseDao';
import { ReportTable } from './DbSchema';
import {
  DbRow, DiagnosisReportModel, DiagnosisReportNotes, Mapper, MediaType, ReportFilterModel,
  ReportListItemModel
} from '../types/Index';

/** 报告持久化 · 集中对外接口在顶部 */
export class ReportDao extends BaseDao<ReportListItemModel> {
  public tableName(): string {
    return ReportTable.tableName;
  }

  public columnNames(): string[] {
    return [
      ReportTable.colId, ReportTable.colMediaId, ReportTable.colMediaName, ReportTable.colMediaType,
      ReportTable.colBdiScore, ReportTable.colSeverity, ReportTable.colDetectedAt,
      ReportTable.colInferenceTimeMs, ReportTable.colNotes
    ];
  }

  // ────────────────── 对外接口 ──────────────────

  /** 整页覆盖写入 */
  public async replaceAll(items: ReportListItemModel[]): Promise<boolean> {
    if (items.length === 0) {
      return true;
    }
    const rows: DbRow[] = [];
    for (let i = 0; i < items.length; i++) {
      rows.push(Mapper.toReportRow(items[i]));
    }
    const affected: number = await this.insertOrReplaceBatch(rows);
    return affected >= 0;
  }

  /** 写入单条含 notes 的明细（来自 GET /api/report/{media_id}） */
  public async saveDetail(item: DiagnosisReportModel, mediaName: string, mediaType: MediaType): Promise<boolean> {
    const row: DbRow = Mapper.toReportRowFromDetail(item, mediaName, mediaType);
    const affected: number = await this.insertOrReplace(row);
    return affected >= 0;
  }

  /**
   * 分页 + 筛选查询（语义与服务端 `/api/reports` 一致）
   * 空字符串表示不筛选，与 `ReportFilterModel` 的约定一致。
   */
  public queryPage(filter: ReportFilterModel): Promise<ReportListItemModel[]> {
    const conditions: string[] = [];
    const args: relationalStore.ValueType[] = [];
    ReportDao.appendFilter(conditions, args, filter.severity, filter.mediaType);
    const sql: string = `${this.selectSql()}${ReportDao.buildWhere(conditions)}`
      + ` ORDER BY ${ReportTable.colDetectedAt} DESC, ${ReportTable.colId} DESC`
      + ` LIMIT ? OFFSET ?`;
    args.push(filter.pageSize);
    args.push((filter.page - 1) * filter.pageSize);
    return this.queryDecoded(sql, args);
  }

  /** 按筛选条件统计总数（分页要显示 total、判断 hasMore） */
  public async countByFilter(filter: ReportFilterModel): Promise<number> {
    const conditions: string[] = [];
    const args: relationalStore.ValueType[] = [];
    ReportDao.appendFilter(conditions, args, filter.severity, filter.mediaType);
    const sql: string = `SELECT COUNT(*) AS total FROM ${this.tableName()}${ReportDao.buildWhere(conditions)}`;
    const rows: DbRow[] = await this.queryRows(sql, args);
    const total: Object | null | undefined = rows.length > 0 ? rows[0]['total'] : undefined;
    return total === undefined || total === null ? 0 : total as number;
  }

  /** 按媒体 id 读取报告明细（详情页离线可读） */
  public async loadDetailByMedia(mediaId: string): Promise<DiagnosisReportModel[]> {
    const sql: string = `SELECT ${this.columnNames().join(', ')} FROM ${this.tableName()}`
      + ` WHERE ${ReportTable.colMediaId} = ?`
      + ` ORDER BY ${ReportTable.colDetectedAt} DESC, ${ReportTable.colId} DESC`;
    const args: relationalStore.ValueType[] = [mediaId];
    const items: ReportListItemModel[] = await this.queryDecoded(sql, args);
    const notesMap: Record<string, string> = await this.loadNotesByMedia(mediaId);
    const out: DiagnosisReportModel[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: ReportListItemModel = items[i];
      const notes: string | undefined = notesMap[`${item.id}`];
      out.push(Mapper.toDiagnosisReportFromItem(item, notes === undefined ? '' : notes));
    }
    return out;
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  protected createTableSql(): string {
    return ReportTable.createSql;
  }

  protected queryAllSql(): string {
    return `${this.selectSql()} ORDER BY ${ReportTable.colDetectedAt} DESC, ${ReportTable.colId} DESC`;
  }

  protected decodeRow(row: DbRow): ReportListItemModel {
    return Mapper.toReportItemFromRow(row);
  }

  /** 单独读 notes（列表项形状不含该字段）· 返回 id → notes */
  private async loadNotesByMedia(mediaId: string): Promise<Record<string, string>> {
    const sql: string = `SELECT ${ReportTable.colId} AS report_id, ${ReportTable.colNotes} AS notes`
      + ` FROM ${this.tableName()} WHERE ${ReportTable.colMediaId} = ?`;
    const args: relationalStore.ValueType[] = [mediaId];
    const rows: DbRow[] = await this.queryRows(sql, args);
    const out: Record<string, string> = {};
    for (let i = 0; i < rows.length; i++) {
      const note: DiagnosisReportNotes = Mapper.toReportNotesFromRow(rows[i]);
      out[note.key] = note.notes;
    }
    return out;
  }

  private selectSql(): string {
    return `SELECT ${this.columnNames().join(', ')} FROM ${this.tableName()}`;
  }

  /** 追加筛选条件 · severity / mediaType 为空串时跳过（与后端 Query 语义一致） */
  private static appendFilter(
    conditions: string[], args: relationalStore.ValueType[], severity: string, mediaType: string
  ): void {
    if (severity.length > 0) {
      conditions.push(`${ReportTable.colSeverity} = ?`);
      args.push(severity);
    }
    if (mediaType.length > 0) {
      conditions.push(`${ReportTable.colMediaType} = ?`);
      args.push(mediaType);
    }
  }

  private static buildWhere(conditions: string[]): string {
    return conditions.length === 0 ? '' : ` WHERE ${conditions.join(' AND ')}`;
  }
}
