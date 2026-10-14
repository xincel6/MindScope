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

export async function registerApi(
  username: string,
  password: string,
  email?: string,
): Promise<TokenResponse> {
  const res = await apiFetch('/api/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password, email: email || null }),
  })
  if (!res.ok) throw new Error(await parseApiError(res, '注册失败'))
  return res.json()
}

export async function fetchMeApi(): Promise<AuthUser> {
  const res = await apiFetch('/api/auth/me')
  if (!res.ok) throw new Error(await parseApiError(res, '获取用户信息失败'))
  return res.json()
}
