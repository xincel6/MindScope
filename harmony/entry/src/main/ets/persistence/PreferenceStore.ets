/**
 * PreferenceStore · `preferences`（`@kit.ArkData`）的唯一封装
 *
 * 存放「配置/令牌层」的轻量数据（方案 A · 混合持久化的上半层）：
 *   令牌、令牌落盘时间、服务端 host/port、轻量偏好。
 *
 * ★ 键名沿用服务端物理字段风格（snake_case），与 RDB 镜像表一致，便于对照；
 *   代码里的驼峰规则约束的是标识符，不是持久化键名。
 * ★ `ApiConfig` 通过 `attach()` 拿到同一个实例后自行读写，本类不再依赖 ApiConfig，
 *   避免出现「工具类 ↔ 配置类」双向依赖。
 */

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { PREFERENCES_NAME } from '../types/Index';
import { Logger } from '../common/Logger';

/** preferences 键名 · 集中一处，改名时只需改这里 */
export class PrefKey {
  /** JWT 令牌 */
  public static readonly token: string = 'access_token';
  /** 令牌落盘时间（毫秒时间戳） */
  public static readonly tokenSavedAt: string = 'token_saved_at';
  /** 服务端主机 */
  public static readonly host: string = 'server_host';
  /** 服务端端口 */
  public static readonly port: string = 'server_port';
  /** 上次成功同步时间（毫秒时间戳）· 冷启动展示「数据截止时间」 */
  public static readonly lastSyncAt: string = 'last_sync_at';
  /** 是否允许在登出时保留离线缓存 */
  public static readonly keepCacheOnLogout: string = 'keep_cache_on_logout';
}

/** 轻量偏好封装 · 集中对外接口在顶部 */
export class PreferenceStore {
  private readonly log = Logger.scope('PreferenceStore');
  private store: preferences.Preferences | null = null;

  // ────────────────── 对外接口 ──────────────────

  /** 打开（不存在则创建）preferences 实例 */
  public async open(context: Context): Promise<boolean> {
    try {
      this.store = await preferences.getPreferences(context, PREFERENCES_NAME);
      this.log.i('preferences 已就绪');
      return true;
    } catch (err) {
      this.log.e('preferences 打开失败', err as BusinessError);
      this.store = null;
      return false;
    }
  }

  /** 是否已就绪 · 未就绪时读写安全降级，UI 不崩 */
  public isReady(): boolean {
    return this.store !== null;
  }

  /** 直接拿实例 · 供 `ApiConfig.attach()` 绑定内存副本 */
  public raw(): preferences.Preferences | null {
    return this.store;
  }

  /** 读字符串 */
  public async getString(key: string, defValue: string): Promise<string> {
    const store: preferences.Preferences | null = this.store;
    if (store === null) {
      return defValue;
    }
    try {
      const value: preferences.ValueType = await store.get(key, defValue);
      return typeof value === 'string' ? value as string : defValue;
    } catch (err) {
      this.log.e(`读取 ${key} 失败`, err as BusinessError);
      return defValue;
    }
  }

  /** 读数字 */
  public async getNumber(key: string, defValue: number): Promise<number> {
    const store: preferences.Preferences | null = this.store;
    if (store === null) {
      return defValue;
    }
    try {
      const value: preferences.ValueType = await store.get(key, defValue);
      return typeof value === 'number' ? value as number : defValue;
    } catch (err) {
      this.log.e(`读取 ${key} 失败`, err as BusinessError);
      return defValue;
    }
  }

  /** 读布尔 */
  public async getBoolean(key: string, defValue: boolean): Promise<boolean> {
    const store: preferences.Preferences | null = this.store;
    if (store === null) {
      return defValue;
    }
    try {
      const value: preferences.ValueType = await store.get(key, defValue);
      return typeof value === 'boolean' ? value as boolean : defValue;
    } catch (err) {
      this.log.e(`读取 ${key} 失败`, err as BusinessError);
      return defValue;
    }
  }

  /** 写字符串（立即 flush，避免进程被杀丢配置） */
  public async putString(key: string, value: string): Promise<void> {
    await this.put(key, value);
  }

  /** 写数字 */
  public async putNumber(key: string, value: number): Promise<void> {
    await this.put(key, value);
  }

  /** 写布尔 */
  public async putBoolean(key: string, value: boolean): Promise<void> {
    await this.put(key, value);
  }

  /** 删键（登出时清令牌用） */
  public async remove(key: string): Promise<void> {
    const store: preferences.Preferences | null = this.store;
    if (store === null) {
      return;
    }
    try {
      await store.delete(key);
      await store.flush();
    } catch (err) {
      this.log.e(`删除 ${key} 失败`, err as BusinessError);
    }
  }

  /** 清空全部偏好（含令牌与地址）· 仅在「重置应用」这类极端场景使用 */
  public async clearAll(): Promise<void> {
    const store: preferences.Preferences | null = this.store;
    if (store === null) {
      return;
    }
    try {
      await store.clear();
      await store.flush();
      this.log.i('preferences 已清空');
    } catch (err) {
      this.log.e('preferences 清空失败', err as BusinessError);
    }
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  private async put(key: string, value: preferences.ValueType): Promise<void> {
    const store: preferences.Preferences | null = this.store;
    if (store === null) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (err) {
      this.log.e(`写入 ${key} 失败`, err as BusinessError);
    }
  }
}
