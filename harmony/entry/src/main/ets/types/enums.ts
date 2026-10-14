/**
 * 枚举定义 · 同时是合法 TS 与合法 ArkTS
 *
 * 约束说明（docs/鸿蒙端网络层与类型共享方案.md 第 2.3 节 #2/#3）：
 * ArkTS 不支持字符串字面量联合类型（`type X = 'a' | 'b'`），必须用 enum。
 * Web 端可直接 import 本文件，两侧零漂移。
 */

/** 抑郁程度分级 · 与后端 `diagnosis_reports.severity` 取值一一对应 */
export enum SeverityLevel {
  none = 'none',
  mild = 'mild',
  moderate = 'moderate',
  severe = 'severe'
}

/** 媒体类型 · 与后端 `media_assets.type` 取值一一对应 */
export enum MediaType {
  image = 'image',
  video = 'video'
}

/** WebSocket 连接状态 · 不用字符串字面量联合 */
export enum SocketState {
  idle = 0,
  connecting = 1,
  open = 2,
  closed = 3
}

/** 应用启动引导状态 · UI 用它决定显示骨架屏 / 登录页 / 内容页 */
export enum BootPhase {
  /** 尚未开始 */
  idle = 0,
  /** 正在读本地缓存 + 校验令牌 */
  preparing = 1,
  /** 已就绪且有登录态 */
  authenticated = 2,
  /** 已就绪但无登录态 */
  anonymous = 3
}

/** 服务端错误码 · 与 docs/鸿蒙端接口清单与登录注册实现.md 第 2.2 节错误码表对应 */
export enum ApiStatus {
  ok = 200,
  badRequest = 400,
  unauthorized = 401,
  forbidden = 403,
  notFound = 404,
  unprocessable = 422,
  serverError = 500
}
