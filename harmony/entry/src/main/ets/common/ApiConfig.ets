/**
 * 服务端地址与运行期配置 · 全工程**唯一**的地址拼装处
 *
 * ★ 默认走已备案的公网域名，不再依赖 Tailscale：
 *     REST：https://xincell1013.xyz
 *     WS： wss://xincell1013.xyz/ws/analysis
 *   TLS 在 SakuraFrp 侧终止，后端仍只监听服务器本机 8000。
 *   换地址二选一：
 *     ① 代码：改下面的 `host` / `port`
 *     ② 运行期：`AppStore.changeServer(host, port)` → 落到 `saveHost`（已持久化，重装才会丢）
 *   端口 443 自动使用 HTTPS/WSS；其它端口保留 HTTP/WS，便于局域网调试。
 *   旧版本保存的 Tailscale 地址会在 `load()` 时一次性迁移到公网域名。
 *
 * ★ 令牌在内存里留一份副本：WebSocket 的 token 通过**子协议头**携带
 *   （`Sec-WebSocket-Protocol: auth.<jwt>`，见 `wsSubprotocol()`），
 *   而拼装是同步调用，不能每次去 await preferences。
 */

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { TOKEN_TTL_MS } from '../types/Index';
import { Logger } from './Logger';
import { SecureTokenStore } from './SecureTokenStore';

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
  /** 形如 https://xincell1013.xyz */
  baseUrl: string;
  /** 形如 wss://xincell1013.xyz */
  wsBase: string;
}

/** 地址与令牌的唯一出口 · 集中对外接口在顶部 */
export class ApiConfig {
  // ────────────────── 对外只读状态 ──────────────────

  /** 默认公网服务端 · 网站与 App 共用同一后端 */
  private static readonly defaultHost: string = 'xincell1013.xyz';
  private static readonly defaultPort: number = 443;
  private static readonly legacyTailscaleHost: string = '100.122.178.113';
  private static readonly legacyTailscalePort: number = 8000;

  /** 服务端主机 · 默认指向已备案域名 */
  public static host: string = ApiConfig.defaultHost;

  /** 服务端端口 · 443 自动启用 HTTPS/WSS */
  public static port: number = ApiConfig.defaultPort;

  /** 令牌内存副本 · 供 WS 同步拼 query 使用 */
  public static token: string = '';

  /** 令牌落盘时间（毫秒），用于本地预判是否过期 */
  public static tokenSavedAt: number = 0;

  /** preferences 实例（StorageManager 启动时注入，这里只做缓存） */
  private static pref: preferences.Preferences | null = null;

  // ────────────────── 地址拼装 ──────────────────

  /** 是否使用 TLS · 公网默认 443；其它端口保留明文以便局域网调试 */
  private static useTls(): boolean {
    return ApiConfig.port === 443;
  }

  /** 标准端口不进 URL，避免生成 https://域名:443 这类多余形式 */
  private static portSuffix(): string {
    return ApiConfig.port === 443 || ApiConfig.port === 80 ? '' : `:${ApiConfig.port}`;
  }

  /** 归一化主机名：去掉协议前缀、尾部斜杠与空白；空值回退默认域名 */
  private static normalizeHost(raw: preferences.ValueType): string {
    if (typeof raw !== 'string') {
      return ApiConfig.defaultHost;
    }
    let host: string = raw.trim();
    host = host.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, '');
    host = host.replace(/\/+$/, '');
    return host.length > 0 ? host : ApiConfig.defaultHost;
  }

  /** 归一化端口：兼容旧版本存成字符串的端口；非法值回退 443 */
  private static normalizePort(raw: preferences.ValueType): number {
    let port: number = -1;
    if (typeof raw === 'number') {
      port = raw;
    } else if (typeof raw === 'string' && raw.trim().length > 0) {
      port = parseInt(raw.trim(), 10);
    }
    if (!Number.isFinite(port) || port < 1 || port > 65535) {
      return ApiConfig.defaultPort;
    }
    return Math.floor(port);
  }

  /** REST 基地址 */
  public static baseUrl(): string {
    const scheme: string = ApiConfig.useTls() ? 'https' : 'http';
    return `${scheme}://${ApiConfig.host}${ApiConfig.portSuffix()}`;
  }

  /** WS 基地址 · 与 REST 使用同一套 TLS 判定 */
  public static wsBase(): string {
    const scheme: string = ApiConfig.useTls() ? 'wss' : 'ws';
    return `${scheme}://${ApiConfig.host}${ApiConfig.portSuffix()}`;
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
      const rawHost: preferences.ValueType = await pref.get(PrefKey.host, ApiConfig.defaultHost);
      const rawPort: preferences.ValueType = await pref.get(PrefKey.port, ApiConfig.defaultPort);
      const savedHost: string = ApiConfig.normalizeHost(rawHost);
      const savedPort: number = ApiConfig.normalizePort(rawPort);
      // 旧安装无论端口被手工改成多少，只要主机还是 Tailscale 地址就迁回公网域名
      const migrateTailscale: boolean = savedHost === ApiConfig.legacyTailscaleHost;
      ApiConfig.host = migrateTailscale ? ApiConfig.defaultHost : savedHost;
      ApiConfig.port = migrateTailscale ? ApiConfig.defaultPort : savedPort;

      if (migrateTailscale) {
        await pref.put(PrefKey.host, ApiConfig.defaultHost);
        await pref.put(PrefKey.port, ApiConfig.defaultPort);
        await pref.flush();
        Logger.i(`旧 Tailscale 地址已迁移 · ${ApiConfig.baseUrl()}`);
      }
    } catch (err) {
      // 地址损坏不能连坐令牌恢复：失败时保留默认域名，继续读令牌
      Logger.e('ApiConfig.load 读取地址失败，保留默认地址', err as BusinessError);
    }

    // ── 令牌：优先安全存储（Asset Store Kit）──
    try {
      const savedAt: preferences.ValueType = await pref.get(PrefKey.tokenSavedAt, 0);
      let token: string = await SecureTokenStore.get();

      if (token.length === 0) {
        // 兼容升级前的旧数据：明文 token 可能还躺在 preferences 里。
        // 读到就立刻搬到安全存储，并删掉明文副本（一次性迁移，之后不再回写）。
        const legacy: preferences.ValueType = await pref.get(PrefKey.token, '');
        if (typeof legacy === 'string' && legacy.length > 0) {
          token = legacy as string;
          const moved: boolean = await SecureTokenStore.put(token);
          if (moved) {
            await pref.delete(PrefKey.token);
            await pref.flush();
            Logger.i('旧令牌已迁移至安全存储，明文副本已清除');
          }
        }
      }

      ApiConfig.token = token;
      ApiConfig.tokenSavedAt = typeof savedAt === 'number' ? savedAt : 0;
      Logger.i(`ApiConfig 已加载 · ${ApiConfig.baseUrl()} · token=${ApiConfig.token.length > 0 ? '已就绪' : '空'}`
        + ` · 存储=${SecureTokenStore.isAvailable() ? '安全存储' : 'preferences(降级)'}`);
    } catch (err) {
      Logger.e('ApiConfig.load 读取令牌失败', err as BusinessError);
    }
  }

  /** 运行期切换服务端地址（443 自动 HTTPS/WSS，其它端口用于局域网调试） */
  public static async saveHost(host: string, port: number): Promise<void> {
    const normalizedHost: string = ApiConfig.normalizeHost(host);
    const normalizedPort: number = ApiConfig.normalizePort(port);
    ApiConfig.host = normalizedHost;
    ApiConfig.port = normalizedPort;
    const pref: preferences.Preferences | null = ApiConfig.pref;
    if (pref === null) {
      return;
    }
    try {
      await pref.put(PrefKey.host, normalizedHost);
      await pref.put(PrefKey.port, normalizedPort);
      await pref.flush();
      Logger.i(`ApiConfig 地址已保存 · ${ApiConfig.baseUrl()}`);
    } catch (err) {
      Logger.e('ApiConfig.saveHost 失败', err as BusinessError);
    }
  }

  /** 写入令牌 · **优先落安全存储**，不可用时才降级到 preferences */
  public static async saveToken(token: string): Promise<void> {
    ApiConfig.token = token;
    ApiConfig.tokenSavedAt = token.length > 0 ? Date.now() : 0;

    if (token.length === 0) {
      await ApiConfig.clearToken();
      return;
    }

    const stored: boolean = await SecureTokenStore.put(token);
    const pref: preferences.Preferences | null = ApiConfig.pref;
    if (pref === null) {
      Logger.w('ApiConfig.saveToken：preferences 未注入，令牌仅存在于内存');
      return;
    }
    try {
      if (stored) {
        // 安全存储成功 → 确保 preferences 里不留明文副本（可能来自旧版本的降级写入）
        await pref.delete(PrefKey.token);
      } else {
        await pref.put(PrefKey.token, token);
      }
      await pref.put(PrefKey.tokenSavedAt, ApiConfig.tokenSavedAt);
      await pref.flush();
    } catch (err) {
      Logger.e('ApiConfig.saveToken 失败', err as BusinessError);
    }
  }

  /**
   * 清空令牌 · **登出就是删本地令牌**（后端没有 logout 接口）
   * 地址配置保留，只清鉴权相关键；安全存储与 preferences 两处都要清，
   * 否则降级期间写下的明文副本会留下来。
   */
  public static async clearToken(): Promise<void> {
    ApiConfig.token = '';
    ApiConfig.tokenSavedAt = 0;

    await SecureTokenStore.remove();

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
