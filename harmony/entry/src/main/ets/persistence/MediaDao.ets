/**
 * MediaDao · media_asset 镜像表的读写（`BaseDao<MediaItemModel>` 子类）
 *
 * 只做持久化，**不含业务判断**：拉取/合并/状态标记都在 `store/MediaStore` 里。
 * 表的物理列名见 `DbSchema.MediaTable`（刻意沿用服务端 snake_case）。
 */

import { relationalStore } from '@kit.ArkData';
import { BaseDao } from './BaseDao';
import { MediaTable } from './DbSchema';
import { DbRow, Mapper, MediaItemModel } from '../types/Index';

/** 媒体持久化 · 集中对外接口在顶部 */
export class MediaDao extends BaseDao<MediaItemModel> {
  public tableName(): string {
    return MediaTable.tableName;
  }

  public columnNames(): string[] {
    return [
      MediaTable.colId, MediaTable.colName, MediaTable.colType, MediaTable.colFilePath,
      MediaTable.colThumbnailUrl, MediaTable.colDuration, MediaTable.colCreatedAt, MediaTable.colPatient
    ];
  }

  // ────────────────── 对外接口 ──────────────────

  /** 整表覆盖写入（服务器全量列表落盘） */
  public async replaceAll(items: MediaItemModel[]): Promise<boolean> {
    if (items.length === 0) {
      return true;
    }
    const rows: DbRow[] = [];
    for (let i = 0; i < items.length; i++) {
      rows.push(Mapper.toMediaRow(items[i]));
    }
    const affected: number = await this.insertOrReplaceBatch(rows);
    return affected >= 0;
  }

  /** 写入单条（上传成功后立刻入镜像表，冷启动立即可见） */
  public async save(item: MediaItemModel): Promise<boolean> {
    const affected: number = await this.insertOrReplace(Mapper.toMediaRow(item));
    return affected >= 0;
  }

  /** 按 id 删除单条 · 与 DELETE /api/media/{id} 配对调用 */
  public async deleteById(mediaId: string): Promise<boolean> {
    const sql: string = `DELETE FROM ${this.tableName()} WHERE ${MediaTable.colId} = ?`;
    const args: relationalStore.ValueType[] = [mediaId];
    await this.execute(sql, args);
    return true;
  }

  /** 读取全部（按创建时间倒序，与服务端一致） */
  public loadAll(): Promise<MediaItemModel[]> {
    return this.queryAll();
  }

  /** 更新单条素材的患者名（本地镜像 · 与 PATCH /api/media/{id}/patient 配对调用） */
  public async updatePatient(mediaId: string, patient: string): Promise<boolean> {
    const sql: string = `UPDATE ${this.tableName()} SET ${MediaTable.colPatient} = ? WHERE ${MediaTable.colId} = ?`;
    const args: relationalStore.ValueType[] = [patient, mediaId];
    await this.execute(sql, args);
    return true;
  }

  /** 按类型读取（媒体库筛选走这里，离线也能筛） */
  public loadByType(mediaType: string): Promise<MediaItemModel[]> {
    const sql: string = `SELECT ${this.columnNames().join(', ')} FROM ${this.tableName()}`
      + ` WHERE ${MediaTable.colType} = ?`
      + ` ORDER BY ${MediaTable.colCreatedAt} DESC, ${MediaTable.colId} DESC`;
    const args: relationalStore.ValueType[] = [mediaType];
    return this.queryDecoded(sql, args);
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  protected createTableSql(): string {
    return MediaTable.createSql;
  }

  protected queryAllSql(): string {
    return `SELECT ${this.columnNames().join(', ')} FROM ${this.tableName()}`
      + ` ORDER BY ${MediaTable.colCreatedAt} DESC, ${MediaTable.colId} DESC`;
  }

  protected decodeRow(row: DbRow): MediaItemModel {
    return Mapper.toMediaItemFromRow(row);
  }
}
