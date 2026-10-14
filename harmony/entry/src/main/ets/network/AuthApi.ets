/**
 * 鉴权接口 · POST /api/auth/login · POST /api/auth/register · GET /api/auth/me
 *
 * ★ 两个坑（docs/鸿蒙端接口清单与登录注册实现.md 第 1.2、2.2 节）：
 *   1. 注册/登录成功响应里**没有用户信息**，想拿用户名必须再调一次 `/api/auth/me`；
 *   2. `email` 为 Optional，空串要发 `null`（发 "" 会写进库）。
 */

import { LoginReqDto, RegisterReqDto, TokenOutDto, UserOutDto } from '../types/Index';
import { HttpClient } from './HttpClient';

/** 登录/注册请求体 · ArkTS 不允许对象字面量直接喂带参构造的类，故用带参构造 */
class LoginBody {
  public username: string;
  public password: string;

  constructor(username: string, password: string) {
    this.username = username;
    this.password = password;
  }
}

class RegisterBody {
  public username: string;
  public password: string;
  public email: string | null;

  constructor(username: string, password: string, email: string | null) {
    this.username = username;
    this.password = password;
    this.email = email;
  }
}

/** 本地校验规则 · 与后端 `auth.py` 完全一致，省一次往返 */
export class AuthRule {
  public static readonly usernamePattern: RegExp = new RegExp('^[a-zA-Z0-9_\\u4e00-\\u9fa5]{3,32}$');
  public static readonly passwordMinLength: number = 6;
  public static readonly usernameMinLength: number = 3;
  public static readonly usernameMaxLength: number = 32;

  /** 校验用户名 · 返回空串表示通过 */
  public static checkUsername(username: string): string {
    if (!AuthRule.usernamePattern.test(username)) {
      return '用户名需 3–32 位，仅支持字母、数字、下划线或中文';
    }
    return '';
  }

  /** 校验密码 · 返回空串表示通过 */
  public static checkPassword(password: string): string {
    if (password.length < AuthRule.passwordMinLength) {
      return '密码至少 6 位';
    }
    return '';
  }
}

/** 鉴权接口 · 集中对外接口在顶部 */
export class AuthApi {
  /**
   * 登录
   * @throws ApiError 400 detail=用户名或密码错误 / 403 detail=账号已禁用 / 网络错误
   */
  public static login(username: string, password: string): Promise<TokenOutDto> {
    const body: LoginBody = new LoginBody(username, password);
    return HttpClient.post<TokenOutDto>('/api/auth/login', JSON.stringify(body));
  }

  /** 注册（★ 注册即登录，直接返回 token） */
  public static register(username: string, password: string, email: string): Promise<TokenOutDto> {
    const normalizedEmail: string | null = email.trim().length > 0 ? email.trim() : null;
    const body: RegisterBody = new RegisterBody(username, password, normalizedEmail);
    return HttpClient.post<TokenOutDto>('/api/auth/register', JSON.stringify(body));
  }

  /** 取当前用户 · created_at 形如 "2026-06-17" */
  public static me(): Promise<UserOutDto> {
    return HttpClient.get<UserOutDto>('/api/auth/me');
  }
}
