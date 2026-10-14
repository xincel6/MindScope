/**
 * StorageManager · RDB + preferences 的**统一初始化入口**
 *
 * 启动时序中的第 ① 步（docs/本轮开发交接.md 第六节）：
 *   `AppBootstrap.start()` → `StorageManager.init(context)`
 *      → preferences 打开 + ApiConfig 绑定并读回地址/令牌
 *      → RDB 打开 + 建表 + 建索引 + 版本迁移
 *      → 三个 DAO 各自 attach 到同一个 RdbStore
 *
 * ★ ArkTS 踩坑记录（已规避，改动时请勿回退）：
 *   1. **静态字段不能与方法同名** —— 会报 `Duplicate identifier` 与
 *      `This expression is not callable`。故字段一律 `daoXxx` 前缀、方法用 `xxxDao()`。
 *   2. **不要写「null 判断 + 内部赋值」的惰性单例** —— ArkTS 的类型收窄不会跨静态字段生效，
 *      会报 `Cannot invoke an object which is possibly 'null'`。改为**立即初始化**。
 *
 * ★ 版本迁移策略：`RDB_VERSION` 变了才递增 `store.version`；
 *   迁移分支写在 `migrate()` 里，未来加列只需在这里追加一段。
 */

import { preferences, relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { RDB_STORE_NAME, RDB_VERSION } from '../types/Index';
import { ApiConfig } from '../common/ApiConfig';
import { Logger } from '../common/Logger';
import { DbSchema } from './DbSchema';
import { MediaDao } from './MediaDao';
import { ReportDao } from './ReportDao';
import { StatsCacheDao } from './StatsCacheDao';
import { PrefKey, PreferenceStore } from './PreferenceStore';

/** 存储层唯一入口 · 集中对外接口在顶部 */
export class StorageManager {
  /** 立即初始化 · 未 attach 前各方法安全空转（isReady() 会返回 false） */
  private static readonly prefStore: PreferenceStore = new PreferenceStore();
  private static readonly daoMedia: MediaDao = new MediaDao();
  private static readonly daoReport: ReportDao = new ReportDao();
  private static readonly daoStats: StatsCacheDao = new StatsCacheDao();
  private static rdbStore: relationalStore.RdbStore | null = null;
  private static initialized: boolean = false;
  private static readonly log = Logger.scope('StorageManager');

  // ────────────────── 对外接口 ──────────────────

  /**
   * 初始化存储层 · **可重复调用**（幂等）
   * @returns 是否至少把 preferences 建起来了（RDB 失败不阻断 UI，只丢离线能力）
   */
  public static async init(context: Context): Promise<boolean> {
    if (StorageManager.initialized) {
      return true;
    }
    const prefOk: boolean = await StorageManager.initPreferences(context);
    const rdbOk: boolean = await StorageManager.initRdb(context);
    StorageManager.initialized = prefOk;
    StorageManager.log.i(`存储层初始化完成 · preferences=${prefOk} · rdb=${rdbOk}`);
    return prefOk;
  }

  /** 是否已初始化 */
  public static isReady(): boolean {
    return StorageManager.initialized;
  }

  /** RDB 是否可用（离线兜底的前提） */
  public static isRdbReady(): boolean {
    return StorageManager.rdbStore !== null;
  }

  /** preferences 封装 */
  public static preferences(): PreferenceStore {
    return StorageManager.prefStore;
  }

  /** 媒体镜像表 DAO */
  public static mediaDao(): MediaDao {
    return StorageManager.daoMedia;
  }

  /** 报告镜像表 DAO */
  public static reportDao(): ReportDao {
    return StorageManager.daoReport;
  }

  /** 统计快照 DAO */
  public static statsDao(): StatsCacheDao {
    return StorageManager.daoStats;
  }

  /** 记录一次成功同步时间（冷启动展示「数据截止时间」用） */
  public static async markSynced(): Promise<void> {
    await StorageManager.prefStore.putNumber(PrefKey.lastSyncAt, Date.now());
  }

  /** 读上次同步时间；0 表示从未同步 */
  public static lastSyncAt(): Promise<number> {
    return StorageManager.prefStore.getNumber(PrefKey.lastSyncAt, 0);
  }

  /** 清空全部业务缓存（登出时调用，避免换账号看到上一个用户的数据） */
  public static async clearBusinessCache(): Promise<void> {
    await StorageManager.daoMedia.deleteAll();
    await StorageManager.daoReport.deleteAll();
    await StorageManager.daoStats.deleteAll();
    await StorageManager.prefStore.remove(PrefKey.lastSyncAt);
    StorageManager.log.i('业务缓存已清空');
  }

  /** 关闭 RDB（应用退出时调用，正常场景不必手动调） */
  public static async close(): Promise<void> {
    const store: relationalStore.RdbStore | null = StorageManager.rdbStore;
    StorageManager.rdbStore = null;
    StorageManager.initialized = false;
    if (store === null) {
      return;
    }
    try {
      await store.close();
      StorageManager.log.i('RDB 已关闭');
    } catch (err) {
      StorageManager.log.e('RDB 关闭失败', err as BusinessError);
    }
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  private static async initPreferences(context: Context): Promise<boolean> {
    const ok: boolean = await StorageManager.prefStore.open(context);
    if (!ok) {
      return false;
    }
    // 把同一个实例交给 ApiConfig，让它自行读写 host/port/token（避免工具类 ↔ 配置类双向依赖）
    const raw: preferences.Preferences | null = StorageManager.prefStore.raw();
    if (raw !== null) {
      ApiConfig.attach(raw);
      await ApiConfig.load();
    }
    return true;
  }

  private static async initRdb(context: Context): Promise<boolean> {
    // 本次进程内已建好就不再重建；失败过则允许重试（RDB 是离线能力的唯一前提）
    if (StorageManager.rdbStore !== null) {
      return true;
    }
    try {
      const config: relationalStore.StoreConfig = {
        name: RDB_STORE_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
      StorageManager.rdbStore = store;

      const currentVersion: number = store.version;
      if (currentVersion === 0) {
        await StorageManager.createSchema(store);
        store.version = RDB_VERSION;
        StorageManager.log.i(`RDB 首次创建 · version=${RDB_VERSION}`);
      } else if (currentVersion < RDB_VERSION) {
        await StorageManager.migrate(store, currentVersion, RDB_VERSION);
        store.version = RDB_VERSION;
      }

      // 幂等补建（版本正确但表被删掉的极端情况）
      await StorageManager.createSchema(store);
      StorageManager.attachDaos(store);
      return true;
    } catch (err) {
      StorageManager.log.e('RDB 初始化失败，将只提供在线能力', err as BusinessError);
      StorageManager.rdbStore = null;
      return false;
    }
  }

  /** 建表 + 建索引 · 全部 IF NOT EXISTS，可重复执行；单条失败不影响其余（幂等补建） */
  private static async createSchema(store: relationalStore.RdbStore): Promise<void> {
    const statements: string[] = [];
    const tables: string[] = DbSchema.createTableSqlList();
    for (let i = 0; i < tables.length; i++) {
      statements.push(tables[i]);
    }
    const indexes: string[] = DbSchema.createIndexSqlList();
    for (let j = 0; j < indexes.length; j++) {
      statements.push(indexes[j]);
    }
    for (let k = 0; k < statements.length; k++) {
      try {
        await store.executeSql(statements[k]);
      } catch (err) {
        StorageManager.log.e(`建表/建索引失败 · ${statements[k]}`, err as BusinessError);
      }
    }
  }

  /**
   * 版本迁移
   * 现在只有 v1，暂无迁移动作；后续加列时按 `fromVersion` 追加分支：
   *   ```
   *   if (fromVersion < 2) { await store.executeSql('ALTER TABLE media_asset ADD COLUMN x TEXT'); }
   *   ```
   */
  private static async migrate(
    store: relationalStore.RdbStore, fromVersion: number, toVersion: number
  ): Promise<void> {
    StorageManager.log.i(`RDB 迁移 ${fromVersion} → ${toVersion}`);
    await StorageManager.createSchema(store);
  }

  private static attachDaos(store: relationalStore.RdbStore): void {
    StorageManager.daoMedia.attach(store);
    StorageManager.daoReport.attach(store);
    StorageManager.daoStats.attach(store);
  }
}
