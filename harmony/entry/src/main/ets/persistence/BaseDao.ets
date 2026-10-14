/**
 * BaseDao · 数据访问基础类（用户硬性要求的 `base...` 基础类之一，见交接文档第 5.3 节）
 *
 * 职责：把 RDB 的通用动作收拢到一处，子类只负责「表名 + 建行 + 读行」三件事。
 * 子类命名 `XxxDao`（MediaDao / ReportDao / StatsCacheDao ...）。
 *
 * ★ 为什么基类要带泛型参数 `<T>`：
 *   ArkTS **不支持结构化类型**（`arkts-no-structural-typing`），两个形状相同的 interface
 *   之间不能互相赋值。若基类的解码器写成 `decodeRow<T>(row): T`，子类无法给出确定的返回类型，
 *   编译报 `DiagnosisReportModel[] is not assignable to ReportListItemModel[]`。
 *   把「本表解出来的模型类型」提到类上（`BaseDao<T>`），调用方拿到的就是精确类型。
 *
 * ★ 其它 ArkTS 约束落地：
 *   - 泛型实参在**方法**里出现时必须显式写（`arkts-no-inferred-generic-params`）；
 *   - 行记录统一用 `DbRow`（`Record<string, Object | null>`）跨层传递；
 *   - 抽象方法用 `abstract`，漏实现立刻编译失败。
 */

import { relationalStore } from '@kit.ArkData';
import { DbRow } from '../types/Index';
import { Logger } from '../common/Logger';

/**
 * 数据访问基础类
 * @typeParam T 本表解码出的领域模型类型（如 `MediaItemModel`）
 */
export abstract class BaseDao<T> {
  /** 表名（子类给出） */
  public abstract tableName(): string;

  /** 全部列名（用于查询与调试） */
  public abstract columnNames(): string[];

  private readonly log = Logger.scope('BaseDao');
  private store: relationalStore.RdbStore | null = null;

  // ────────────────── 对外接口 ──────────────────

  /** 绑定 RDB 实例（StorageManager 初始化后调用） */
  public attach(store: relationalStore.RdbStore): void {
    this.store = store;
  }

  /** 是否已就绪 · 未就绪时所有读写都安全空转，UI 不会崩 */
  public isReady(): boolean {
    return this.store !== null;
  }

  /** 建表（IF NOT EXISTS，可重复执行） */
  public async createTable(): Promise<void> {
    await this.execute(this.createTableSql(), []);
  }

  /** 子类给建表语句 */
  protected abstract createTableSql(): string;

  /** 子类给「查全部」的 SQL（必须自带 ORDER BY，RDB 不保证顺序） */
  protected abstract queryAllSql(): string;

  /** 行记录 → 领域模型（子类实现，返回类型由类上的 T 决定） */
  protected abstract decodeRow(row: DbRow): T;

  /** 新增或整行覆盖 · 返回受影响行数（-1 表示未就绪或失败而跳过） */
  public async insertOrReplace(row: DbRow): Promise<number> {
    const store: relationalStore.RdbStore | null = this.store;
    if (store === null) {
      return -1;
    }
    try {
      const values: relationalStore.ValuesBucket = row as relationalStore.ValuesBucket;
      const id: number = await store.insert(
        this.tableName(), values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
      return id;
    } catch (err) {
      this.log.e(`insertOrReplace 失败 · ${this.tableName()}`, err as Object);
      return -1;
    }
  }

  /** 批量整行覆盖（一次写入整页数据，离线快照灌入用） */
  public async insertOrReplaceBatch(rows: DbRow[]): Promise<number> {
    const store: relationalStore.RdbStore | null = this.store;
    if (store === null || rows.length === 0) {
      return -1;
    }
    try {
      const buckets: relationalStore.ValuesBucket[] = [];
      for (let i = 0; i < rows.length; i++) {
        buckets.push(rows[i] as relationalStore.ValuesBucket);
      }
      const affected: number = await store.batchInsert(this.tableName(), buckets);
      return affected;
    } catch (err) {
      this.log.e(`batchInsert 失败 · ${this.tableName()}`, err as Object);
      return -1;
    }
  }

  /** 查询全部（按子类默认排序） */
  public async queryAll(): Promise<T[]> {
    return this.queryDecoded(this.queryAllSql(), []);
  }

  /** 按 SQL 查询并用子类解码器转成领域模型 */
  public async queryDecoded(sql: string, args: relationalStore.ValueType[]): Promise<T[]> {
    const rows: DbRow[] = await this.queryRows(sql, args);
    const out: T[] = [];
    for (let i = 0; i < rows.length; i++) {
      out.push(this.decodeRow(rows[i]));
    }
    return out;
  }

  /**
   * 按 SQL 查询原始行记录（不做解码）
   * 聚合查询（COUNT/SUM）用这个：结果列不是表的列，走解码器会拿到空模型。
   */
  public async queryRows(sql: string, args: relationalStore.ValueType[]): Promise<DbRow[]> {
    const store: relationalStore.RdbStore | null = this.store;
    const out: DbRow[] = [];
    if (store === null) {
      return out;
    }
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await store.querySql(sql, args);
      while (resultSet.goToNextRow()) {
        out.push(BaseDao.readCurrentRow(resultSet));
      }
    } catch (err) {
      this.log.e(`querySql 失败 · ${sql}`, err as Object);
    } finally {
      BaseDao.closeQuietly(resultSet);
    }
    return out;
  }

  /** 查询行数 */
  public async count(): Promise<number> {
    const sql: string = `SELECT COUNT(*) AS total FROM ${this.tableName()}`;
    const rows: DbRow[] = await this.queryRows(sql, []);
    const total: Object | null | undefined = rows.length > 0 ? rows[0]['total'] : undefined;
    return total === undefined || total === null ? 0 : total as number;
  }

  /** 清空本表（登出 / 手动清缓存用） */
  public async deleteAll(): Promise<number> {
    const store: relationalStore.RdbStore | null = this.store;
    if (store === null) {
      return -1;
    }
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(this.tableName());
      const affected: number = await store.delete(predicates);
      this.log.i(`已清空 ${this.tableName()} · ${affected} 行`);
      return affected;
    } catch (err) {
      this.log.e(`deleteAll 失败 · ${this.tableName()}`, err as Object);
      return -1;
    }
  }

  /** 执行 DDL / 无返回语句 */
  public async execute(sql: string, args: relationalStore.ValueType[]): Promise<void> {
    const store: relationalStore.RdbStore | null = this.store;
    if (store === null) {
      return;
    }
    try {
      await store.executeSql(sql, args);
    } catch (err) {
      this.log.e(`executeSql 失败 · ${sql}`, err as Object);
    }
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  /**
   * 把 `ResultSet` 当前行读成 `DbRow`
   * ★ 用列名而不是硬编码下标：列顺序变了也不会静默读错。
   * ★ `ResultSet` 的读取 API 都可能抛异常，这里整体兜住，坏行退化为空值而不是崩掉调用方。
   */
  private static readCurrentRow(resultSet: relationalStore.ResultSet): DbRow {
    const row: DbRow = {};
    try {
      const columns: string[] = resultSet.getColumnNames();
      for (let i = 0; i < columns.length; i++) {
        const name: string = columns[i];
        if (resultSet.isColumnNull(i)) {
          row[name] = null;
          continue;
        }
        // getValue 返回 ValueType；统一收敛后存放
        row[name] = resultSet.getValue(i) as Object;
      }
    } catch (err) {
      Logger.e('[BaseDao] 读取结果集当前行失败', err as Object);
    }
    return row;
  }

  /** 安静关闭结果集 · 关闭失败不影响查询结果返回 */
  private static closeQuietly(resultSet: relationalStore.ResultSet | null): void {
    if (resultSet === null) {
      return;
    }
    try {
      resultSet.close();
    } catch (err) {
      Logger.w('[BaseDao] 关闭结果集失败');
    }
  }
}
