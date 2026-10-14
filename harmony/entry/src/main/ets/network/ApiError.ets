/**
 * 网络错误类型 · 全工程唯一的错误载体
 *
 * 分类（UI 只需按 `kind` 分支，不必解析字符串）：
 *  - `http`    服务端返回了非 2xx，`code` 是 HTTP 状态码，`message` 是后端 `detail` 文案
 *  - `network` 请求根本没到服务端（DNS/连接超时/明文被拦截/后端未启动）
 *  - `parse`   响应体不是合法 JSON（服务端返回了 HTML 错误页等）
 */

import { ApiStatus } from '../types/Index';

/** 错误大类 */
export enum ApiErrorKind {
  http = 'http',
  network = 'network',
  parse = 'parse'
}

/** 网络层统一错误 */
export class ApiError extends Error {
  /** HTTP 状态码；网络类错误为 0 */
  public code: number = 0;
  /** 错误大类 */
  public kind: ApiErrorKind = ApiErrorKind.http;
  /** 后端原始 detail（可能是 JSON 字符串化的数组） */
  public detail: string = '';

  constructor(kind: ApiErrorKind, code: number, message: string) {
    super(message);
    this.name = 'ApiError';
    this.kind = kind;
    this.code = code;
    this.detail = message;
  }
}

/** 构造 HTTP 错误 */
export function httpError(code: number, detail: string): ApiError {
  const message: string = detail.length > 0 ? detail : `请求失败（HTTP ${code}）`;
  return new ApiError(ApiErrorKind.http, code, message);
}

/** 构造网络错误（附带常见成因提示，答辩现场好排查） */
export function networkError(reason: string): ApiError {
  return new ApiError(ApiErrorKind.network, 0, `网络不可达：${reason}。请确认服务端已启动且手机与电脑同一局域网。`);
}

/** 构造解析错误 */
export function parseError(reason: string): ApiError {
  return new ApiError(ApiErrorKind.parse, 0, `服务端响应解析失败：${reason}`);
}

/** 是否为「登录态失效」· 401 必须全局踢回登录页（JWT 7 天且无 refresh） */
export function isUnauthorized(err: Object): boolean {
  const apiErr: ApiError = err as ApiError;
  return apiErr.kind === ApiErrorKind.http && apiErr.code === ApiStatus.unauthorized;
}

/** 是否为「账号被禁用」 */
export function isForbidden(err: Object): boolean {
  const apiErr: ApiError = err as ApiError;
  return apiErr.kind === ApiErrorKind.http && apiErr.code === ApiStatus.forbidden;
}

/** 是否为网络类错误（用于切到离线兜底，而不是弹报错） */
export function isNetworkFailure(err: Object): boolean {
  const apiErr: ApiError = err as ApiError;
  return apiErr.kind === ApiErrorKind.network;
}

/**
 * ArkTS 系统调用抛出的 BusinessError → ApiError
 * 已知码见 @ohos.net.http / @ohos.net.webSocket：
 *  201 权限缺失（module.json5 未声明 INTERNET）
 *  2300006 无法解析主机名 · 2300007 无法连接 · 2300028 超时
 */
export function toApiError(err: Object): ApiError {
  const apiErr: ApiError | null = tryCastApiError(err);
  if (apiErr !== null) {
    return apiErr;
  }
  const be: BusinessErrorLike = err as BusinessErrorLike;
  const code: number = be.code === undefined ? 0 : be.code;
  let reason: string = be.message === undefined ? '未知错误' : be.message;
  if (code === 201) {
    reason = '缺少 INTERNET 权限（检查 module.json5）';
  } else if (code === 2300006) {
    reason = '无法解析主机名（检查服务端地址）';
  } else if (code === 2300007) {
    reason = '无法连接到服务端（检查后端是否已启动、是否监听 0.0.0.0）';
  } else if (code === 2300028) {
    reason = '连接超时（检查是否同一局域网、明文 http 是否被拦截）';
  }
  return networkError(reason);
}

/** 鸭子类型判定：避免对 ApiError 再做一次包装 */
function tryCastApiError(err: Object): ApiError | null {
  const candidate: ApiError = err as ApiError;
  if (candidate !== null && candidate !== undefined && candidate.kind !== undefined
    && candidate.name === 'ApiError') {
    return candidate;
  }
  return null;
}

/** BusinessError 的最小结构（不直接引类型，避免与 ArkTS 环境耦合） */
interface BusinessErrorLike {
  code?: number;
  message?: string;
  name?: string;
}

/**
 * 把后端 `detail` 归一化成给用户看的一行文案。
 * ★ 422 时 detail 是**数组**（Pydantic 校验错误），必须显式判断，不能直接当字符串用。
 */
export function normalizeDetail(detail: Object | undefined, code: number): string {
  if (detail === undefined || detail === null) {
    return defaultMessage(code);
  }
  if (typeof detail === 'string') {
    return detail as string;
  }
  // 数组形态：抽出每条 msg 拼起来，避免把 [object Object] 弹给用户
  const items: Object[] = detail as Object[];
  if (Array.isArray(items)) {
    const parts: string[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: Record<string, Object> = items[i] as Record<string, Object>;
      const msg: Object | undefined = item['msg'];
      const loc: Object | undefined = item['loc'];
      if (typeof msg === 'string') {
        const where: string = loc === undefined ? '' : `(${JSON.stringify(loc)})`;
        parts.push(`${msg as string}${where}`);
      }
    }
    if (parts.length > 0) {
      return parts.join('；');
    }
    return JSON.stringify(detail);
  }
  return JSON.stringify(detail);
}

/** 按状态码给兜底文案 · 与后端错误码表对应 */
export function defaultMessage(code: number): string {
  if (code === ApiStatus.unauthorized) {
    return '登录已过期，请重新登录';
  }
  if (code === ApiStatus.forbidden) {
    return '账号已禁用';
  }
  if (code === ApiStatus.unprocessable) {
    return '请求参数不合法';
  }
  if (code >= 500) {
    return '服务端内部错误';
  }
  return `请求失败（HTTP ${code}）`;
}
