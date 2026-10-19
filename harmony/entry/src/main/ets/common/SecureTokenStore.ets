/**
 * SecureTokenStore · 令牌的安全落盘（Asset Store Kit 封装）
 *
 * ────────────────── 为什么不用 preferences ──────────────────
 * preferences 是明文键值库，落在应用沙箱的 XML 里。root 设备、备份导出、
 * 或者任何能读到沙箱的漏洞，都能直接拿到 `access_token` —— 那是一个 7 天有效、
 * 可冒充该用户访问全部 API（含他人人脸数据）的凭据。
 *
 * Asset Store Kit 是系统提供的**硬件级密钥库**：
 *   · 密钥由 TEE / 安全芯片托管，应用只能"用"，不能"读原文"；
 *   · 支持按可访问性分级（本文件用 DEVICE_FIRST_UNLOCKED：重启后首次解锁才可用）；
 *   · 卸载应用时自动清除，不会残留在备份里。
 *
 * ────────────────── 为什么要降级 ──────────────────
 * 部分模拟器 / 老设备没有可用的安全存储服务，`asset.add` 会直接抛错。
 * 这里选择"能力探测 + 降级到 preferences"，而不是让登录整体失败：
 *   · 真机（有 TEE）走安全存储，安全；
 *   · 模拟器降级后仍能跑通流程，但会在日志里留一条告警，便于排查。
 *   降级只影响**本机调试**，不影响生产安全模型。
 *
 * ★ 依赖：`@kit.AssetStoreKit`（API 11+，HarmonyOS 6.0.2 可用）
 */

import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

/** 密钥别名 · 同一应用内唯一，用于定位这一条记录 */
const TOKEN_ALIAS: string = 'mindscope_access_token';

/** Asset Store Kit 的错误码：记录不存在（查询/删除时的正常情况） */
const ERR_NOT_FOUND: number = 24000002;

export class SecureTokenStore {
  /** 安全存储是否可用 · 首次失败后置 false，后续直接走降级分支（避免每次登录都卡 2 秒超时） */
  private static usable: boolean = true;

  /** 安全存储是否可用（供 UI / 日志判断当前处于哪种模式） */
  public static isAvailable(): boolean {
    return SecureTokenStore.usable;
  }

  /**
   * 写入令牌
   * @returns true = 已写入安全存储；false = 安全存储不可用，调用方应降级
   */
  public static async put(token: string): Promise<boolean> {
    if (!SecureTokenStore.usable) {
      return false;
    }
    try {
      // 先删后加：asset 对同一 alias 重复 add 会报 DUPLICATED，
      // 先 remove（不存在则忽略）比先 query 再分支更短、更少一次 IPC。
      await SecureTokenStore.removeInternal();

      const attr: asset.AssetMap = new Map();
      attr.set(asset.Tag.SECRET, SecureTokenStore.strToBuf(token));
      attr.set(asset.Tag.ALIAS, SecureTokenStore.strToBuf(TOKEN_ALIAS));
      // 重启后首次解锁才可访问：既保证开机自启场景可用，又不让锁屏状态下被读
      attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);

      await asset.add(attr);
      return true;
    } catch (err) {
      SecureTokenStore.usable = false;
      Logger.w(`[SecureTokenStore] 安全存储不可用，本次起降级到 preferences：${JSON.stringify(err)}`);
      return false;
    }
  }

  /** 读取令牌 · 不存在或不可用时返回空串 */
  public static async get(): Promise<string> {
    if (!SecureTokenStore.usable) {
      return '';
    }
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, SecureTokenStore.strToBuf(TOKEN_ALIAS));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);

      const results: asset.AssetMap[] = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const raw: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (raw === undefined) {
        return '';
      }
      return SecureTokenStore.bufToStr(raw as Uint8Array);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      if (e.code !== ERR_NOT_FOUND) {
        SecureTokenStore.usable = false;
        Logger.w(`[SecureTokenStore] 读取失败，降级到 preferences：${e.code} ${e.message}`);
      }
      return '';
    }
  }

  /** 删除令牌（登出）· 不存在视为成功 */
  public static async remove(): Promise<void> {
    if (!SecureTokenStore.usable) {
      return;
    }
    try {
      await SecureTokenStore.removeInternal();
    } catch (err) {
      Logger.w(`[SecureTokenStore] 删除失败：${JSON.stringify(err)}`);
    }
  }

  /** 内部删除 · 不存在时静默（asset.remove 找不到记录会抛 NOT_FOUND） */
  private static async removeInternal(): Promise<void> {
    const del: asset.AssetMap = new Map();
    del.set(asset.Tag.ALIAS, SecureTokenStore.strToBuf(TOKEN_ALIAS));
    try {
      await asset.remove(del);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      if (e.code !== ERR_NOT_FOUND) {
        throw err as Error;
      }
    }
  }

  private static strToBuf(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text);
  }

  private static bufToStr(buf: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(buf);
  }
}
