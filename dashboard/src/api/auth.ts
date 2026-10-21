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
 * 后端签名：`POST /api/auth/register`，body 必须带 `verification_code`
 * （`backend/schemas.py` 的 `UserRegister`，6 位邮箱验证码，5 分钟有效）。
 * 邮箱因此是必填项，不再是「选填」。
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
 * 后端签名：`POST /api/auth/send-code`，body `{ email }`，202 返回 `{ message }`。
 * 同一邮箱 60 秒内不能重发（429）；服务端未配置 SMTP 时返回 503。
 */
export async function sendCodeApi(email: string): Promise<string> {
  const res = await apiFetch('/api/auth/send-code', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email }),
  })
  if (!res.ok) throw new Error(await parseApiError(res, '发送验证码失败'))
  const data = await res.json().catch(() => ({}))
  return typeof data?.message === 'string' ? data.message : '验证码已发送'
}

export async function fetchMeApi(): Promise<AuthUser> {
  const res = await apiFetch('/api/auth/me')
  if (!res.ok) throw new Error(await parseApiError(res, '获取用户信息失败'))
  return res.json()
}
