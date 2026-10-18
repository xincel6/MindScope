/**
 * 服务端地址与运行期配置 · 全工程**唯一**的地址拼装处
 *
 * ★ 服务端**已部署完成**（鸿蒙组服务器，监听 0.0.0.0:8000），默认地址指向它：
 *     Tailscale（推荐 · 任意网络可达）：100.122.178.113:8000
 *     局域网（手机与服务器同一 Wi-Fi）：192.168.0.123:8000
 *   默认烧 **Tailscale** 地址；换地址二选一：
 *     ① 代码：改下面的 `host` / `port`
 *     ② 运行期：设置页走 `AppStore.changeServer(host, port)` → 落到 `saveHost`（已持久化，重装才会丢）
 *   ★ 后端已监听 0.0.0.0（systemd 用户服务 `mindscope.service`），客户端换地址不必动服务端。
 *
 * ★ 令牌在内存里留一份副本：WebSocket 的 token 通过**子协议头**携带
 *   （`Sec-WebSocket-Protocol: auth.<jwt>`，见 `wsSubprotocol()`），
 *   而拼装是同步调用，不能每次去 await preferences。
 */

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { TOKEN_TTL_MS } from '../types/Index';
import { Logger } from './Logger';

/** preferences 中的键名 · 与后端物理字段风格保持一致（snake_case），便于与 RDB 表对照 */
class PrefKey {
  public static readonly token: string = 'access_token';
  public static readonly host: string = 'server_host';
  public static readonly port: string = 'server_port';
  public static readonly tokenSavedAt: string = 'token_saved_at';
}

/** 当前服务端配置快照（UI 设置页展示/修改用） */
export interface NetConfig {
  host: string;
  port: number;
  /** 形如 http://100.122.178.113:8000 */
  baseUrl: string;
  /** 形如 ws://100.122.178.113:8000 */
  wsBase: string;
}

/** 地址与令牌的唯一出口 · 集中对外接口在顶部 */
export class ApiConfig {
  // ────────────────── 对外只读状态 ──────────────────

  /**
   * 服务端主机 · 默认指向已部署的鸿蒙组服务器
   * ★ 已烧 Tailscale 地址；现场只有局域网时改设置页或这里换成 192.168.0.123
   */
  public static host: string = '100.122.178.113';

  /** 服务端端口（服务端监听 0.0.0.0:8000） */
  public static port: number = 8000;

  /** 令牌内存副本 · 供 WS 同步拼 query 使用 */
  public static token: string = '';

  /** 令牌落盘时间（毫秒），用于本地预判是否过期 */
  public static tokenSavedAt: number = 0;

  /** preferences 实例（StorageManager 启动时注入，这里只做缓存） */
  private static pref: preferences.Preferences | null = null;

  // ────────────────── 地址拼装 ──────────────────

  /** REST 基地址 */
  public static baseUrl(): string {
    return `http://${ApiConfig.host}:${ApiConfig.port}`;
  }

  /** WS 基地址 */
  public static wsBase(): string {
    return `ws://${ApiConfig.host}:${ApiConfig.port}`;
  }

  /**
   * WebSocket 完整地址
   * ★ token 不再放 query（?token=…），改用子协议头携带（见 `wsSubprotocol()`）。
   *   这样 token 不会进入访问日志 / 代理日志 / 反向代理的 URL 记录。
   */
  public static analysisWsUrl(): string {
    const base: string = ApiConfig.wsBase();
    return `${base}/ws/analysis`;
  }

  /**
   * WebSocket 子协议 · 形如 `auth.<jwt>`，用于在握手时通过
   * `Sec-WebSocket-Protocol` 头携带 token（后端 `ws.headers.get("sec-websocket-protocol")`）。
   * token 为空时返回空串（调用方不应带子协议头）。
   */
  public static wsSubprotocol(): string {
    const token: string = ApiConfig.token;
    if (token.length === 0) {
      return '';
    }
    return `auth.${token}`;
  }

  /**
   * 把接口返回的相对路径（如 `/media/xxx.jpg`）拼成可直接喂给 Image/Video 组件的绝对地址。
   * ★ 静态资源 `/media/{filename}` **无鉴权**，不需要带 token。
   */
  public static resolveMediaUrl(path: string): string {
    if (path.length === 0) {
      return '';
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return path.startsWith('/') ? `${ApiConfig.baseUrl()}${path}` : `${ApiConfig.baseUrl()}/${path}`;
  }

  /** 当前配置快照 */
  public static snapshot(): NetConfig {
    const config: NetConfig = {
      host: ApiConfig.host,
      port: ApiConfig.port,
      baseUrl: ApiConfig.baseUrl(),
      wsBase: ApiConfig.wsBase()
    };
    return config;
  }

  // ────────────────── 初始化与持久化 ──────────────────

  /** 绑定 preferences 实例并读回上次保存的地址与令牌（由 StorageManager 调用） */
  public static attach(pref: preferences.Preferences): void {
    ApiConfig.pref = pref;
  }

  /** 从 preferences 读回 host / port / token；无存储则保留默认占位值 */
  public static async load(): Promise<void> {
    const pref: preferences.Preferences | null = ApiConfig.pref;
    if (pref === null) {
      Logger.w('ApiConfig.load 在 attach 之前被调用，跳过');
      return;
    }
    try {
      const host: preferences.ValueType = await pref.get(PrefKey.host, ApiConfig.host);
      const port: preferences.ValueType = await pref.get(PrefKey.port, ApiConfig.port);
      const token: preferences.ValueType = await pref.get(PrefKey.token, '');
      const savedAt: preferences.ValueType = await pref.get(PrefKey.tokenSavedAt, 0);
      ApiConfig.host = host as string;
      ApiConfig.port = port as number;
      ApiConfig.token = token as string;
      ApiConfig.tokenSavedAt = savedAt as number;
      Logger.i(`ApiConfig 已加载 · ${ApiConfig.baseUrl()} · token=${ApiConfig.token.length > 0 ? '已就绪' : '空'}`);
    } catch (err) {
      Logger.e('ApiConfig.load 失败', err as BusinessError);
    }
  }

  /** 运行期切换服务端地址（答辩现场改 IP 不必重装） */
  public static async saveHost(host: string, port: number): Promise<void> {
    ApiConfig.host = host;
    ApiConfig.port = port;
    const pref: preferences.Preferences | null = ApiConfig.pref;
    if (pref === null) {
      return;
    }
    try {
      await pref.put(PrefKey.host, host);
      await pref.put(PrefKey.port, port);
      await pref.flush();
      Logger.i(`ApiConfig 地址已保存 · ${ApiConfig.baseUrl()}`);
    } catch (err) {
      Logger.e('ApiConfig.saveHost 失败', err as BusinessError);
    }
  }

  /** 写入令牌（同时落盘） */
  public static async saveToken(token: string): Promise<void> {
    ApiConfig.token = token;
    ApiConfig.tokenSavedAt = token.length > 0 ? Date.now() : 0;
    const pref: preferences.Preferences | null = ApiConfig.pref;
    if (pref === null) {
      return;
    }
    try {
      await pref.put(PrefKey.token, token);
      await pref.put(PrefKey.tokenSavedAt, ApiConfig.tokenSavedAt);
      await pref.flush();
    } catch (err) {
      Logger.e('ApiConfig.saveToken 失败', err as BusinessError);
    }
  }

  /**
   * 清空令牌 · **登出就是删本地令牌**（后端没有 logout 接口）
   * 地址配置保留，只清鉴权相关键。
   */
  public static async clearToken(): Promise<void> {
    ApiConfig.token = '';
    ApiConfig.tokenSavedAt = 0;
    const pref: preferences.Preferences | null = ApiConfig.pref;
    if (pref === null) {
      return;
    }
    try {
      await pref.delete(PrefKey.token);
      await pref.delete(PrefKey.tokenSavedAt);
      await pref.flush();
    } catch (err) {
      Logger.e('ApiConfig.clearToken 失败', err as BusinessError);
    }
  }

  /** 本地预判令牌是否可能已过期（后端 JWT 7 天且无 refresh，过期只能重登） */
  public static isTokenExpired(): boolean {
    if (ApiConfig.token.length === 0) {
      return true;
    }
    if (ApiConfig.tokenSavedAt <= 0) {
      return false;
    }
    return Date.now() - ApiConfig.tokenSavedAt > TOKEN_TTL_MS;
  }
}
