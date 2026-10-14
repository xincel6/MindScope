/**
 * 日志封装 · 统一 hilog 出口
 *
 * ★ 坑：hilog 的格式串里 `%{public}s` 必须配一个实参，
 *   只传格式串会把 `%{public}s` 原样打进日志。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { LOG_DOMAIN, LOG_TAG } from '../types/Index';

/** 内部把任意错误对象转成可读字符串（ArkTS 没有 any） */
function describe(err: Object | null | undefined): string {
  if (err === undefined || err === null) {
    return 'unknown error';
  }
  if (typeof err === 'string') {
    return err as string;
  }
  const asError: Error = err as Error;
  if (asError.message !== undefined && asError.message !== null && asError.message.length > 0) {
    return `${asError.name}: ${asError.message}`;
  }
  return JSON.stringify(err);
}

/** 全工程唯一的日志出口 · 集中对外接口在顶部 */
export class Logger {
  /** 调试日志（仅 debug 构建输出） */
  public static d(message: string): void {
    hilog.debug(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  /** 普通信息 */
  public static i(message: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  /** 警告 */
  public static w(message: string): void {
    hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  /** 错误（可带异常对象） */
  public static e(message: string, err?: Object): void {
    hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', `${message} | ${describe(err)}`);
  }

  /** 带作用域前缀的信息日志，例如 Logger.scope('MediaStore').i('loaded 12 items') */
  public static scope(name: string): ScopedLogger {
    return new ScopedLogger(name);
  }
}

/** 带前缀的日志器（避免每行都手写模块名） */
export class ScopedLogger {
  private readonly prefix: string;

  constructor(name: string) {
    this.prefix = `[${name}] `;
  }

  public d(message: string): void {
    Logger.d(this.prefix + message);
  }

  public i(message: string): void {
    Logger.i(this.prefix + message);
  }

  public w(message: string): void {
    Logger.w(this.prefix + message);
  }

  public e(message: string, err?: Object): void {
    Logger.e(this.prefix + message, err);
  }
}
