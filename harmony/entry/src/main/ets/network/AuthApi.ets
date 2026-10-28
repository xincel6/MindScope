/**
 * 鉴权接口 · POST /api/auth/login · POST /api/auth/register · POST /api/auth/send-code
 *          POST /api/auth/reset-password · GET /api/auth/me
 *
 * ★ 三个坑（docs/鸿蒙端接口清单与登录注册实现.md 第 1.2、2.2 节）：
 *   1. 注册/登录成功响应里**没有用户信息**，想拿用户名必须再调一次 `/api/auth/me`；
 *   2. 注册自 2026-10-21 起**强制邮箱 + 验证码**，只传 username/password 会收 422；
 *   3. 验证码按用途分桶：注册码不能拿去重置密码，反之亦然（`purpose`）。
 */

import {
  LoginReqDto, MessageOutDto, RegisterReqDto, ResetPasswordReqDto,
  SendCodeReqDto, TokenOutDto, UserOutDto
} from '../types/Index';
import { HttpClient } from './HttpClient';

/** 登录请求体 · ArkTS 不允许对象字面量直接喂带参构造的类，故用带参构造 */
class LoginBody {
  public username: string;
  public password: string;

  constructor(username: string, password: string) {
    this.username = username;
    this.password = password;
  }
}

/** 注册请求体 · 邮箱与验证码均为必填（后端 2026-10-21 起强制） */
class RegisterBody {
  public username: string;
  public password: string;
  public email: string;
  public verification_code: string;

  constructor(username: string, password: string, email: string, verificationCode: string) {
    this.username = username;
    this.password = password;
    this.email = email;
    this.verification_code = verificationCode;
  }
}

/** 发码请求体 · purpose 缺省为 "register" */
class SendCodeBody {
  public email: string;
  public purpose: string;

  constructor(email: string, purpose: string) {
    this.email = email;
    this.purpose = purpose;
  }
}

/** 重置密码请求体 */
class ResetPasswordBody {
  public email: string;
  public verification_code: string;
  public new_password: string;

  constructor(email: string, verificationCode: string, newPassword: string) {
    this.email = email;
    this.verification_code = verificationCode;
    this.new_password = newPassword;
  }
}

/** 本地校验规则 · 与后端 `auth.py` 完全一致，省一次往返 */
export class AuthRule {
  public static readonly usernamePattern: RegExp = new RegExp('^[a-zA-Z0-9_\\u4e00-\\u9fa5]{3,32}$');
  public static readonly passwordMinLength: number = 6;
  public static readonly usernameMinLength: number = 3;
  public static readonly usernameMaxLength: number = 32;

  /** 邮箱格式 · 与服务端正则同源（够用即可，真正判死刑的是验证码） */
  public static readonly emailPattern: RegExp =
    new RegExp('^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$');

  /** 验证码格式 · 后端固定发 6 位数字 */
  public static readonly codePattern: RegExp = new RegExp('^[0-9]{6}$');

  /** 密码规则说明 · 直接给用户看的完整口径（改这里等于改所有提示文案） */
  public static readonly passwordHint: string = '至少 6 位，需同时包含大写字母、小写字母和特殊字符';

  /** 校验用户名 · 返回空串表示通过 */
  public static checkUsername(username: string): string {
    if (!AuthRule.usernamePattern.test(username)) {
      return '用户名需 3–32 位，仅支持字母、数字、下划线或中文';
    }
    return '';
  }

  /**
   * 校验密码强度 · 返回空串表示通过
   *
   * ★ 与后端 `_validate_password` 逐条对齐：至少 6 位 + 大写 + 小写 + 特殊字符。
   *   "特殊字符"指非字母数字的符号（`!@#$%…`），数字不算。
   * ★ 只用于**注册**与**重置密码**。登录不要套用本规则（见 `checkLoginPassword`）：
   *   否则老账密改不动的用户会被端上直接拦死，连服务端都到不了。
   */
  public static checkPassword(password: string): string {
    if (password.length < AuthRule.passwordMinLength) {
      return `密码至少 ${AuthRule.passwordMinLength} 位`;
    }
    const missing: string[] = [];
    let hasUpper: boolean = false;
    let hasLower: boolean = false;
    let hasSymbol: boolean = false;
    // ★ 用 charCodeAt 而不是 `password[i]` 取字符：ArkTS 对字符串下标取字符的
    //   支持不如 charCodeAt 稳妥，而这里只需要判断 ASCII 区间，码点就够用。
    for (let i: number = 0; i < password.length; i++) {
      const code: number = password.charCodeAt(i);
      if (code >= 0x41 && code <= 0x5A) {            // A-Z
        hasUpper = true;
      } else if (code >= 0x61 && code <= 0x7A) {     // a-z
        hasLower = true;
      } else if (!(code >= 0x30 && code <= 0x39)) {  // 非 0-9：符号、中文、空格都算
        hasSymbol = true;
      }
    }
    if (!hasUpper) {
      missing.push('大写字母');
    }
    if (!hasLower) {
      missing.push('小写字母');
    }
    if (!hasSymbol) {
      missing.push('特殊字符（如 ! @ #）');
    }
    if (missing.length > 0) {
      return '密码需同时包含大写字母、小写字母和特殊字符，当前缺少：' + missing.join('、');
    }
    return '';
  }

  /**
   * 登录时的密码校验 · **只查长度，不查强度**
   *
   * ★ 与后端严格对齐：服务端同样只在 register / reset-password 两条路上做强校验，
   *   登录永远只验哈希。历史上注册过弱密码的老账户必须还能登录，
   *   端上若提前按新规则拦一次，用户看到的是"密码需包含大写字母"——
   *   而他明明一直用这个密码，只会更困惑。
   */
  public static checkLoginPassword(password: string): string {
    if (password.length < AuthRule.passwordMinLength) {
      return `密码至少 ${AuthRule.passwordMinLength} 位`;
    }
    return '';
  }

  /** 校验邮箱 · 返回空串表示通过 */
  public static checkEmail(email: string): string {
    const e: string = email.trim();
    if (e.length === 0) {
      return '请输入邮箱（注册与找回密码都要用）';
    }
    if (e.length > 128 || !AuthRule.emailPattern.test(e)) {
      return '邮箱格式不正确';
    }
    return '';
  }

  /** 校验验证码 · 返回空串表示通过 */
  public static checkCode(code: string): string {
    const c: string = code.trim();
    if (c.length === 0) {
      return '请输入邮箱收到的验证码';
    }
    if (!AuthRule.codePattern.test(c)) {
      return '验证码是 6 位数字';
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

  /** 注册（★ 注册即登录，直接返回 token）· 邮箱与验证码必填 */
  public static register(
    username: string,
    password: string,
    email: string,
    verificationCode: string
  ): Promise<TokenOutDto> {
    const body: RegisterBody = new RegisterBody(username, password, email, verificationCode);
    return HttpClient.post<TokenOutDto>('/api/auth/register', JSON.stringify(body));
  }

  /**
   * 发送验证码 · purpose: 'register' 注册 / 'reset' 找回密码
   *
   * ★ 202/409/429/503 都走正常返回，只有网络类错误才 reject：
   *   调用方要把 detail 直接展示给用户（"该邮箱已被注册""发送太频繁"等）。
   */
  public static sendCode(email: string, purpose: string): Promise<MessageOutDto> {
    const body: SendCodeBody = new SendCodeBody(email.trim(), purpose);
    return HttpClient.post<MessageOutDto>('/api/auth/send-code', JSON.stringify(body));
  }

  /** 邮箱找回密码 · 成功后可不用重新登录（旧令牌仍有效，直到自然过期） */
  public static resetPassword(
    email: string,
    verificationCode: string,
    newPassword: string
  ): Promise<MessageOutDto> {
    const body: ResetPasswordBody = new ResetPasswordBody(email.trim(), verificationCode.trim(), newPassword);
    return HttpClient.post<MessageOutDto>('/api/auth/reset-password', JSON.stringify(body));
  }

  /** 取当前用户 · created_at 形如 "2026-06-17" */
  public static me(): Promise<UserOutDto> {
    return HttpClient.get<UserOutDto>('/api/auth/me');
  }
}
