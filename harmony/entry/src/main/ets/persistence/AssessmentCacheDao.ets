/**
 * AssessmentCacheDao · `workbench_assessment` 单行快照表
 *
 * 只做一件事：把「当前任务 + 最终分析会话」的整包 JSON 原样存取。
 * 会话结构是嵌套的（frames / scores / heatmap），拆列没有查询收益，
 * 所以沿用 `stats_cache` 的"单行 KV"模式；具体字段由 `AppStore` 序列化/校验。
 *
 * ★ 与业务无关：DAO 不解析 JSON、不认识 `WorkbenchAssessmentModel`，
 *   换载荷字段时只改 AppStore，不动数据层。
 * ★ 未 attach / RDB 不可用时安全空转：save 返回 -1，load 返回空串。
 */

import { relationalStore } from '@kit.ArkData';
import { BaseDao } from './BaseDao';
import { WorkbenchAssessmentTable } from './DbSchema';
import { DbRow, Mapper } from '../types/Index';

/** 工作台评估快照持久化 */
export class AssessmentCacheDao extends BaseDao<string> {
  public tableName(): string {
    return WorkbenchAssessmentTable.tableName;
  }

  public columnNames(): string[] {
    return [
      WorkbenchAssessmentTable.colKey,
      WorkbenchAssessmentTable.colPayload,
      WorkbenchAssessmentTable.colUpdatedAt
    ];
  }

  // ────────────────── 对外接口 ──────────────────

  /** 保存当前评估载荷（整包 JSON） */
  public async save(payloadJson: string, updatedAt: number): Promise<boolean> {
    const row: DbRow = {};
    row[WorkbenchAssessmentTable.colKey] = WorkbenchAssessmentTable.keyLatest;
    row[WorkbenchAssessmentTable.colPayload] = payloadJson;
    row[WorkbenchAssessmentTable.colUpdatedAt] = updatedAt;
    const affected: number = await this.insertOrReplace(row);
    return affected >= 0;
  }

  /** 读回当前评估载荷；没有则空串 */
  public async loadPayload(): Promise<string> {
    const sql: string = `SELECT ${WorkbenchAssessmentTable.colPayload} AS payload`
      + ` FROM ${this.tableName()} WHERE ${WorkbenchAssessmentTable.colKey} = ?`;
    const args: relationalStore.ValueType[] = [WorkbenchAssessmentTable.keyLatest];
    const rows: DbRow[] = await this.queryRows(sql, args);
    return rows.length === 0 ? '' : Mapper.payloadFromRow(rows[0]);
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  protected createTableSql(): string {
    return WorkbenchAssessmentTable.createSql;
  }

  protected queryAllSql(): string {
    return `SELECT ${this.columnNames().join(', ')} FROM ${this.tableName()}`;
  }

  /** 解码结果就是 payload 字符串 */
  protected decodeRow(row: DbRow): string {
    return Mapper.payloadFromRow(row);
  }
}
