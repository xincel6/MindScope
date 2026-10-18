/**
 * RDB 镜像表 DDL · 与服务端 SQLite **同构**（方案 A · 混合持久化）
 *
 * 设计依据（docs/本轮开发交接.md 第 3.1 节）：
 *   服务端本身就是 SQLite 关系库，客户端用 `relationalStore` 做镜像表，
 *   schema 一一对应最不易漂移；`/api/reports` 自带 severity / media_type / page / limit 过滤分页，
 *   RDB 能 1:1 承接（preferences / JSON 文件只能整包替换）。
 *
 * 命名约定：
 *   - **表名与列名沿用服务端 snake_case** —— 它们镜像的是服务端物理 schema，
 *     刻意保持同构才能一眼对照；代码里的驼峰规则约束的是标识符，不是数据库物理列名。
 *   - 服务端 `media_assets.id` 是 INTEGER，但 `/api/media/list` 下发的是**字符串**，
 *     本端全链路以字符串为准（见 normalizeMediaId），故物理列用 TEXT + 唯一索引。
 */

/** 媒体镜像表 */
export class MediaTable {
  /**
   * ★ 不能命名为 `name`：ArkTS 报
   *   「Static property 'name' conflicts with built-in property 'Function.name'」
   *   静态属性名必须避开 `name` / `length` 等函数内建属性。
   */
  public static readonly tableName: string = 'media_asset';

  public static readonly colId: string = 'id';
  public static readonly colName: string = 'name';
  public static readonly colType: string = 'type';
  public static readonly colFilePath: string = 'file_path';
  public static readonly colThumbnailUrl: string = 'thumbnail_url';
  public static readonly colDuration: string = 'duration';
  public static readonly colCreatedAt: string = 'created_at';
  /** 所属患者名（空串 = 未命名）· 素材库患者筛选/命名的本地镜像列 */
  public static readonly colPatient: string = 'patient';

  /** 建表语句 · 列顺序与 DbSchema.createTables 的数组一致 */
  public static readonly createSql: string = `CREATE TABLE IF NOT EXISTS ${MediaTable.tableName} (
    ${MediaTable.colId} TEXT PRIMARY KEY NOT NULL,
    ${MediaTable.colName} TEXT NOT NULL DEFAULT '',
    ${MediaTable.colType} TEXT NOT NULL DEFAULT 'image',
    ${MediaTable.colFilePath} TEXT NOT NULL DEFAULT '',
    ${MediaTable.colThumbnailUrl} TEXT NOT NULL DEFAULT '',
    ${MediaTable.colDuration} INTEGER,
    ${MediaTable.colCreatedAt} TEXT NOT NULL DEFAULT '',
    ${MediaTable.colPatient} TEXT NOT NULL DEFAULT ''
  )`;
}

/** 诊断报告镜像表 */
export class ReportTable {
  public static readonly tableName: string = 'diagnosis_report';

  public static readonly colId: string = 'id';
  public static readonly colMediaId: string = 'media_id';
  public static readonly colMediaName: string = 'media_name';
  public static readonly colMediaType: string = 'media_type';
  public static readonly colBdiScore: string = 'bdi_score';
  public static readonly colSeverity: string = 'severity';
  public static readonly colDetectedAt: string = 'detected_at';
  public static readonly colInferenceTimeMs: string = 'inference_time_ms';
  public static readonly colNotes: string = 'notes';

  public static readonly createSql: string = `CREATE TABLE IF NOT EXISTS ${ReportTable.tableName} (
    ${ReportTable.colId} INTEGER PRIMARY KEY NOT NULL,
    ${ReportTable.colMediaId} TEXT NOT NULL DEFAULT '',
    ${ReportTable.colMediaName} TEXT NOT NULL DEFAULT '',
    ${ReportTable.colMediaType} TEXT NOT NULL DEFAULT 'image',
    ${ReportTable.colBdiScore} REAL NOT NULL DEFAULT 0,
    ${ReportTable.colSeverity} TEXT NOT NULL DEFAULT 'none',
    ${ReportTable.colDetectedAt} TEXT NOT NULL DEFAULT '',
    ${ReportTable.colInferenceTimeMs} REAL NOT NULL DEFAULT 0,
    ${ReportTable.colNotes} TEXT NOT NULL DEFAULT ''
  )`;
}

/** 统计快照表 · 单行 KV（key='latest'），存最近一次 /api/stats 的原始 JSON */
export class StatsCacheTable {
  public static readonly tableName: string = 'stats_cache';

  public static readonly colKey: string = 'cache_key';
  public static readonly colPayload: string = 'payload';
  public static readonly colUpdatedAt: string = 'updated_at';

  /** 固定主键 */
  public static readonly keyLatest: string = 'latest';

  public static readonly createSql: string = `CREATE TABLE IF NOT EXISTS ${StatsCacheTable.tableName} (
    ${StatsCacheTable.colKey} TEXT PRIMARY KEY NOT NULL,
    ${StatsCacheTable.colPayload} TEXT NOT NULL DEFAULT '',
    ${StatsCacheTable.colUpdatedAt} INTEGER NOT NULL DEFAULT 0
  )`;
}

/** 索引语句 · 报告表按媒体/时间检索是高频路径 */
export class DbIndex {
  public static readonly createSqlList: string[] = [
    `CREATE INDEX IF NOT EXISTS idx_report_media ON ${ReportTable.tableName} (${ReportTable.colMediaId})`,
    `CREATE INDEX IF NOT EXISTS idx_report_detected ON ${ReportTable.tableName} (${ReportTable.colDetectedAt})`,
    `CREATE INDEX IF NOT EXISTS idx_media_created ON ${MediaTable.tableName} (${MediaTable.colCreatedAt})`
  ];
}

/** 建表总入口 · StorageManager 初始化时按序执行 */
export class DbSchema {
  /** 全部建表语句，顺序即执行顺序 */
  public static createTableSqlList(): string[] {
    return [MediaTable.createSql, ReportTable.createSql, StatsCacheTable.createSql];
  }

  /** 全部索引语句 */
  public static createIndexSqlList(): string[] {
    return DbIndex.createSqlList;
  }
}
