import { apiFetch, parseApiError } from '@/api/http'

export interface AuthUser {
  id: number
  username: string
  email: string | null
  created_at: string
}

export interface TokenResponse {
  access_token: string
  token_type: string
}

export async function loginApi(username: string, password: string): Promise<TokenResponse> {
  const res = await apiFetch('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  })
  if (!res.ok) throw new Error(await parseApiError(res, '登录失败'))
  return res.json()
}

/**
 * 注册 · 邮箱与验证码自 2026-10-21 起为必填
 *
 * 邮箱是账号唯一的找回通道；验证码证明"这个邮箱真的是你的"。
 * 后端少任何一个字段都会回 422。
 */
export async function registerApi(
  username: string,
  password: string,
  email: string,
  verificationCode: string,
): Promise<TokenResponse> {
  const res = await apiFetch('/api/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username,
      password,
      email,
      verification_code: verificationCode,
    }),
  })
  if (!res.ok) throw new Error(await parseApiError(res, '注册失败'))
  return res.json()
}

/**
 * 发送验证码 · purpose: 'register' | 'reset'
 *
 * 常见失败（都会带中文 detail，直接抛给调用方展示）：
 *   409 该邮箱已被注册（register 用途）
 *   429 发送太频繁（60 秒冷却）
 *   503 服务端未配置邮件服务
 */
export async function sendCodeApi(email: string, purpose: 'register' | 'reset'): Promise<string> {
  const res = await apiFetch('/api/auth/send-code', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, purpose }),
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(await parseApiError(res, '验证码发送失败'))
  return data.message ?? '验证码已发送'
}

/** 邮箱找回密码 · 成功后旧密码立即失效（已签发令牌仍有效到自然过期） */
export async function resetPasswordApi(
  email: string,
  verificationCode: string,
  newPassword: string,
): Promise<string> {
  const res = await apiFetch('/api/auth/reset-password', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email,
      verification_code: verificationCode,
      new_password: newPassword,
    }),
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(await parseApiError(res, '重置失败'))
  return data.message ?? '密码已重置'
}

export async function fetchMeApi(): Promise<AuthUser> {
  const res = await apiFetch('/api/auth/me')
  if (!res.ok) throw new Error(await parseApiError(res, '获取用户信息失败'))
  return res.json()
}
