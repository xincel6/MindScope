/**
 * StatsCacheDao · stats_cache 单行快照表（离线统计面板的数据来源）
 *
 * `/api/stats` 的响应是聚合结果，逐个字段拆列没有意义（且后端随时可能加字段），
 * 因此**整包 JSON 存一行**。RDB 只承担「缓存」职责，业务字段仍由 Mapper 解析。
 *
 * ★ 本表的「解码结果」就是那个 JSON 字符串，所以 `BaseDao<string>`。
 */

import { relationalStore } from '@kit.ArkData';
import { BaseDao } from './BaseDao';
import { StatsCacheTable } from './DbSchema';
import { DbRow, Mapper } from '../types/Index';

/** 统计快照持久化 · 集中对外接口在顶部 */
export class StatsCacheDao extends BaseDao<string> {
  public tableName(): string {
    return StatsCacheTable.tableName;
  }

  public columnNames(): string[] {
    return [StatsCacheTable.colKey, StatsCacheTable.colPayload, StatsCacheTable.colUpdatedAt];
  }

  // ────────────────── 对外接口 ──────────────────

  /** 保存最近一次统计响应（原始 JSON 字符串） */
  public async save(payloadJson: string, updatedAt: number): Promise<boolean> {
    const row: DbRow = {};
    row[StatsCacheTable.colKey] = StatsCacheTable.keyLatest;
    row[StatsCacheTable.colPayload] = payloadJson;
    row[StatsCacheTable.colUpdatedAt] = updatedAt;
    const affected: number = await this.insertOrReplace(row);
    return affected >= 0;
  }

  /** 读回最近一次统计响应；无缓存返回空串 */
  public async loadPayload(): Promise<string> {
    const sql: string = `SELECT ${StatsCacheTable.colPayload} AS payload FROM ${this.tableName()}`
      + ` WHERE ${StatsCacheTable.colKey} = ?`;
    const args: relationalStore.ValueType[] = [StatsCacheTable.keyLatest];
    const rows: DbRow[] = await this.queryRows(sql, args);
    return rows.length === 0 ? '' : Mapper.statsPayloadFromRow(rows[0]);
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  protected createTableSql(): string {
    return StatsCacheTable.createSql;
  }

  protected queryAllSql(): string {
    return `SELECT ${this.columnNames().join(', ')} FROM ${this.tableName()}`;
  }

  /** 解码结果就是 payload 字符串 */
  protected decodeRow(row: DbRow): string {
    return Mapper.statsPayloadFromRow(row);
  }
}
