/**
 * AuthStore · 登录态（`BaseStore` 子类）
 *
 * 契约要点（docs/鸿蒙端接口清单与登录注册实现.md 第二章）：
 *  - 注册**即登录**，成功直接返回 token；
 *  - 登录/注册的响应里**没有用户信息**，必须再调一次 `/api/auth/me`；
 *  - **没有登出接口**，登出 = 客户端删 token；
 *  - JWT 7 天且**无 refresh**，401 只能踢回登录页。
 *
 * 对外暴露的字段：`token` / `user` / `signedIn` / `loading` / `errorMsg`
 * 对外暴露的方法：`login` / `register` / `restore` / `loadMe` / `logout` / `refresh` / `clear`
 */

import { ApiConfig } from '../common/ApiConfig';
import { AuthApi, AuthRule } from '../network/AuthApi';
import { isNetworkFailure, isUnauthorized, toApiError } from '../network/ApiError';
import { ActionResultModel, Mapper, TokenOutDto, UserOutDto, UserModel } from '../types/Index';
import { AuthState } from '../types/storeState';
import { BaseStore } from './BaseStore';

/** 登出时清理其它 store 的回调（由 AppStore 注入，避免 store 之间互相 import） */
export type LogoutCleanup = () => Promise<void>;

/** 登录态 · 集中对外接口在顶部 */
@ObservedV2
export class AuthStore extends BaseStore {
  // ────────────────── 对外字段（UI 直接读）──────────────────

  /** 当前令牌（内存副本，同时由 ApiConfig 持有落盘副本） */
  @Trace token: string = '';

  /** 当前用户（未登录或还没拉到时为 null） */
  @Trace user: UserModel | null = null;

  /** 是否已登录（有非空令牌即视为已登录） */
  @Trace signedIn: boolean = false;

  /** 是否正在请求 */
  @Trace loading: boolean = false;

  /** 错误文案（空串表示无错） */
  @Trace errorMsg: string = '';

  // ────────────────── 单例 ──────────────────

  private static instance: AuthStore | null = null;

  public static get(): AuthStore {
    if (AuthStore.instance === null) {
      AuthStore.instance = new AuthStore();
    }
    return AuthStore.instance;
  }

  /** 由 AppStore 注入「登出后清理其它缓存」的回调 */
  private cleanup: LogoutCleanup | null = null;

  /** 当前用户的展示名（未登录返回空串） */
  public displayName(): string {
    const current: UserModel | null = this.user;
    return current === null ? '' : current.username;
  }

  /** 当前用户注册日期（未登录返回空串） */
  public registeredAt(): string {
    const current: UserModel | null = this.user;
    return current === null ? '' : current.createdAt;
  }

  // ────────────────── 对外方法 ──────────────────

  /** 注入登出清理回调 */
  public setCleanup(cleanup: LogoutCleanup): void {
    this.cleanup = cleanup;
  }

  /**
   * 登录 · 成功后自动拉 `/me`
   * @returns 成功返回 ok=true；失败返回 ok=false 且 message 为后端 detail 文案
   */
  public async login(username: string, password: string): Promise<ActionResultModel> {
    const local: string = this.validate(username, password, false);
    if (local.length > 0) {
      this.errorMsg = local;
      return AuthStore.fail(local);
    }
    this.beginLoad();
    try {
      const token: TokenOutDto = await AuthApi.login(username, password);
      await this.applyToken(token);
      return AuthStore.done(`欢迎回来，${this.displayName()}`);
    } catch (err) {
      return this.handleFailure(err as Object);
    }
  }

  /**
   * 注册 · **注册即登录**，后端直接返回 token
   * @param email 传空串表示不填邮箱（内部会发 null）
   */
  public async register(username: string, password: string, email: string): Promise<ActionResultModel> {
    const local: string = this.validate(username, password, true);
    if (local.length > 0) {
      this.errorMsg = local;
      return AuthStore.fail(local);
    }
    this.beginLoad();
    try {
      const token: TokenOutDto = await AuthApi.register(username, password, email);
      await this.applyToken(token);
      return AuthStore.done(`注册成功，欢迎 ${this.displayName()}`);
    } catch (err) {
      return this.handleFailure(err as Object);
    }
  }

  /**
   * 冷启动恢复登录态（等价于 Web 端的路由守卫）
   * 有令牌就拉一次 `/me` 验证；无效令牌会被服务端 401，此时自动登出。
   * @returns 是否处于已登录状态
   */
  public async restore(): Promise<boolean> {
    this.token = ApiConfig.token;
    this.signedIn = this.token.length > 0;
    if (!this.signedIn) {
      this.log().i('无本地令牌 · 未登录');
      return false;
    }
    if (ApiConfig.isTokenExpired()) {
      // 本地预判已过期：直接登出，省一次必然失败的往返
      this.log().i('本地令牌已超期（>7 天）· 直接登出');
      await this.logout('登录已过期，请重新登录');
      return false;
    }
    const ok: boolean = await this.loadMe();
    return ok;
  }

  /** 单独拉取用户信息（`/api/auth/me`）· 失败即视为未登录 */
  public async loadMe(): Promise<boolean> {
    try {
      const dto: UserOutDto = await AuthApi.me();
      this.user = Mapper.toUser(dto);
      this.token = ApiConfig.token;
      this.signedIn = this.token.length > 0;
      this.errorMsg = '';
      return true;
    } catch (err) {
      const error: Object = err as Object;
      if (isNetworkFailure(error)) {
        // 网络不通不代表令牌失效：保留登录态，离线可用
        this.log().w('拉取用户信息失败（网络不可达）· 保留本地登录态');
        return this.signedIn;
      }
      this.log().w('拉取用户信息失败 · 按未登录处理');
      await this.logout(isUnauthorized(error) ? '登录已过期，请重新登录' : '');
      return false;
    }
  }

  /**
   * 登出 · 后端没有该接口，纯客户端行为：清令牌 + 清业务缓存 + 清内存
   * @param message 需要展示给用户的提示（如「登录已过期」），可为空串
   */
  public async logout(message: string): Promise<void> {
    this.token = '';
    this.user = null;
    this.signedIn = false;
    this.errorMsg = message;
    await ApiConfig.clearToken();
    const cleanup: LogoutCleanup | null = this.cleanup;
    if (cleanup !== null) {
      await cleanup();
    }
    this.log().i(`已登出${message.length > 0 ? ` · ${message}` : ''}`);
  }

  /** 401 全局回调落地 · 与 `HttpClient.onUnauthorized` 对接 */
  public async onUnauthorized(message: string): Promise<void> {
    if (!this.signedIn && this.errorMsg === message) {
      return;
    }
    await this.logout(message.length > 0 ? message : '登录已过期，请重新登录');
  }

  /** 实现 BaseStore：刷新 = 重新校验令牌并拉用户信息 */
  public async refresh(): Promise<void> {
    if (!this.signedIn) {
      return;
    }
    this.beginLoad();
    const ok: boolean = await this.loadMe();
    if (ok) {
      this.endLoadOk();
    } else {
      this.endLoadErr('登录态已失效');
    }
  }

  /** 实现 BaseStore：清空内存状态（不碰磁盘，磁盘由 logout 负责） */
  public clear(): void {
    this.token = '';
    this.user = null;
    this.signedIn = false;
    this.loading = false;
    this.errorMsg = '';
    this.lastSyncAt = 0;
  }

  /** 实现 BaseStore */
  protected storeName(): string {
    return 'AuthStore';
  }

  /** 当前登录态快照 · 供不支持 @Trace 的场景（如日志、非 UI 代码）读取 */
  public snapshot(): AuthState {
    const state: AuthState = new AuthState();
    state.token = this.token;
    state.user = this.user;
    state.signedIn = this.signedIn;
    state.loading = this.loading;
    state.errorMsg = this.errorMsg;
    return state;
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  /** 本地校验 · 规则与后端 auth.py 完全一致，省一次往返 */
  private validate(username: string, password: string, needEmailCheck: boolean): string {
    const nameErr: string = AuthRule.checkUsername(username);
    if (nameErr.length > 0) {
      return nameErr;
    }
    const pwdErr: string = AuthRule.checkPassword(password);
    if (pwdErr.length > 0) {
      return pwdErr;
    }
    return '';
  }

  /** 落地令牌 + 立刻拉用户信息（登录/注册共用） */
  private async applyToken(token: TokenOutDto): Promise<void> {
    await ApiConfig.saveToken(token.access_token);
    this.token = token.access_token;
    this.signedIn = token.access_token.length > 0;
    // ★ 注册/登录响应不含用户信息，必须再调一次 /me
    const ok: boolean = await this.loadMe();
    if (!ok) {
      throw new Error('已取得令牌但读取用户信息失败，请重试');
    }
    this.endLoadOk();
  }

  /** 统一失败处理 · 把 ApiError 转成用户可读文案 */
  private handleFailure(err: Object): ActionResultModel {
    const apiErr = toApiError(err);
    this.endLoadErr(apiErr.message);
    this.log().w(`鉴权失败 · ${apiErr.message}`);
    return AuthStore.fail(apiErr.message);
  }

  private static done(message: string): ActionResultModel {
    const result: ActionResultModel = { ok: true, message: message };
    return result;
  }

  private static fail(message: string): ActionResultModel {
    const result: ActionResultModel = { ok: false, message: message };
    return result;
  }
}
