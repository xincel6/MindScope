/**
 * HttpClient · 全工程**唯一**的 REST 出口
 *
 * 职责（集中对外接口在顶部）：
 *  1. 统一注入 `Authorization: Bearer <token>`
 *  2. 统一解析后端 `detail`（★ 400/401/403 是字符串，422 是**数组**）
 *  3. 401 全局回调（后端 JWT 7 天且**没有 refresh**，过期只能踢回登录页）
 *  4. 每次请求结束 `destroy()`，否则连接句柄泄漏
 *  5. multipart 上传（`/api/upload/image` 字段名必须是 `file`）
 *
 * 调用方拿到的一定是 `ApiError`，用 `isUnauthorized(err)` / `isNetworkFailure(err)` 分流。
 */

import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../common/ApiConfig';
import { Logger } from '../common/Logger';
import { ApiStatus, ErrorBodyDto, HealthOutDto } from '../types/Index';
import { ApiError, defaultMessage, httpError, normalizeDetail, parseError, toApiError } from './ApiError';

/** 上传文件的描述（相册选择器选完后填这个） */
export interface UploadFileSpec {
  /** 本地沙箱路径或 file:// URI */
  filePath: string;
  /** 原始文件名（后端用它填 media_assets.name） */
  fileName: string;
  /** MIME，如 image/jpeg；不确定时传 application/octet-stream */
  mimeType: string;
}

/** 登录态失效的全局回调签名 */
export type UnauthorizedHandler = (message: string) => void;

/** REST 请求唯一入口 · 集中对外接口在顶部 */
export class HttpClient {
  /** 默认超时（毫秒）· 推理接口较慢，读超时给足 */
  public static readonly connectTimeoutMs: number = 10000;
  public static readonly readTimeoutMs: number = 30000;

  /** 401 全局回调 · 由 AppStore 在启动时注册（决定「踢回登录页」怎么跳） */
  private static unauthorizedHandler: UnauthorizedHandler | null = null;
  /** 只在内网明文 http 下为 true；上线 https 时应调整 */
  private static logging: boolean = true;

  // ────────────────── 对外接口 ──────────────────

  /** 注册 401 全局处理器 */
  public static onUnauthorized(handler: UnauthorizedHandler): void {
    HttpClient.unauthorizedHandler = handler;
  }

  /** GET · 反序列化为 T（T 必须是 interface，不能是 class） */
  public static get<T>(path: string): Promise<T> {
    return HttpClient.send<T>(path, http.RequestMethod.GET, null, null, null);
  }

  /** DELETE */
  public static del<T>(path: string): Promise<T> {
    return HttpClient.send<T>(path, http.RequestMethod.DELETE, null, null, null);
  }

  /** POST JSON · body 为已序列化的字符串（ArkTS 不允许对象字面量喂 Object 字段） */
  public static post<T>(path: string, bodyJson: string): Promise<T> {
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/json';
    return HttpClient.send<T>(path, http.RequestMethod.POST, bodyJson, headers, null);
  }

  /**
   * POST multipart 上传单文件
   * ★ 字段名固定为 `file`（后端 `UploadFile = File(...)` 的形参名）
   */
  public static upload<T>(path: string, fieldName: string, file: UploadFileSpec): Promise<T> {
    const form: http.MultiFormData = {
      name: fieldName,
      contentType: file.mimeType,
      remoteFileName: file.fileName,
      filePath: file.filePath
    };
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'multipart/form-data';
    return HttpClient.send<T>(path, http.RequestMethod.POST, null, headers, [form]);
  }

  /** GET /health · 探活（不需要令牌）· 用于「服务端是否启动」的一键检测 */
  public static health(): Promise<HealthOutDto> {
    return HttpClient.get<HealthOutDto>('/health');
  }

  /** 打开/关闭请求日志 */
  public static setLogging(enabled: boolean): void {
    HttpClient.logging = enabled;
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  private static async send<T>(
    path: string, method: http.RequestMethod, bodyJson: string | null,
    extraHeaders: Record<string, string> | null, form: http.MultiFormData[] | null
  ): Promise<T> {
    const url: string = ApiConfig.baseUrl() + path;
    const req: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {};
      header['Accept'] = 'application/json';
      const token: string = ApiConfig.token;
      if (token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      if (extraHeaders !== null) {
        // ★ 用 if 显式写每个已知键：ArkTS 不支持对 Record 做动态下标写入
        //   （`header[keys[i]] = ...` 会报 "The type of the target of a indexed access is not assignable"）
        const contentType: string | undefined = extraHeaders['Content-Type'];
        if (contentType !== undefined) {
          header['Content-Type'] = contentType;
        }
        const accept: string | undefined = extraHeaders['Accept'];
        if (accept !== undefined) {
          header['Accept'] = accept;
        }
      }

      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: HttpClient.connectTimeoutMs,
        readTimeout: HttpClient.readTimeoutMs
      };
      if (bodyJson !== null) {
        options.extraData = bodyJson;
      }
      if (form !== null) {
        options.multiFormDataList = form;
      }

      if (HttpClient.logging) {
        Logger.d(`→ ${method} ${url}`);
      }
      const resp: http.HttpResponse = await req.request(url, options);
      const code: number = resp.responseCode;
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      if (HttpClient.logging) {
        Logger.d(`← ${code} ${path} · ${text.length} bytes`);
      }

      if (code >= ApiStatus.ok && code < 300) {
        return HttpClient.decode<T>(text, path);
      }

      // ★ 401 全局登出；登录/注册接口自身除外（否则会把「密码错误」也当成登录过期）
      if (code === ApiStatus.unauthorized && !path.startsWith('/api/auth/')) {
        await HttpClient.handleUnauthorized(text, code);
      }
      throw httpError(code, HttpClient.parseDetailText(text, code));
    } catch (err) {
      throw toApiError(err as Object);
    } finally {
      req.destroy();
    }
  }

  /**
   * 成功响应反序列化
   * ★ 后端**没有**返回空体的接口（DELETE 也回 `{ok:true}`），所以空体只在异常情况下出现，
   *   此时返回 `null`；调用方若解引用需自行判空（本工程内所有调用方都已判）。
   */
  private static decode<T>(text: string, path: string): T {
    if (text.length === 0) {
      return null as T;
    }
    try {
      return JSON.parse(text) as T;
    } catch (err) {
      Logger.e(`响应体不是合法 JSON · ${path}`, err as Object);
      throw parseError('返回内容不是 JSON');
    }
  }

  /** 解析错误响应体 · 显式区分 string 与数组（422） */
  private static parseDetailText(text: string, code: number): string {
    if (text.length === 0) {
      return defaultMessage(code);
    }
    try {
      const body: ErrorBodyDto = JSON.parse(text) as ErrorBodyDto;
      const detail: Object | undefined = body.detail;
      const normalized: string = normalizeDetail(detail, code);
      return normalized.length > 0 ? normalized : defaultMessage(code);
    } catch (err) {
      // 后端返回了非 JSON（如 500 的 HTML 页），退化为状态码文案
      Logger.w(`错误响应体非 JSON · HTTP ${code}`);
      return defaultMessage(code);
    }
  }

  /** 触发全局登出回调，并给出与后端错误码表一致的提示文案 */
  private static async handleUnauthorized(text: string, code: number): Promise<void> {
    const detail: string = HttpClient.parseDetailText(text, code);
    const handler: UnauthorizedHandler | null = HttpClient.unauthorizedHandler;
    if (handler !== null) {
      handler(detail);
    }
    // 令牌本地立即清掉；具体 UI 跳转交给回调（store 层负责）
    await ApiConfig.clearToken();
  }
}
