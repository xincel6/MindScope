import { useAuthStore } from '@/stores/auth'
import { getApiBase } from '@/api/baseResolver'

const TOKEN_KEY = 'depression_auth_token'

export function getStoredToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setStoredToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token)
  else localStorage.removeItem(TOKEN_KEY)
}

export async function apiFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const auth = useAuthStore()
  const token = auth.token || getStoredToken()
  const headers = new Headers(init?.headers)
  if (token && !headers.has('Authorization')) {
    headers.set('Authorization', `Bearer ${token}`)
  }
  // 相对路径（/api/...）按解析出的后端地址补全：
  // 同源时基址为 ''，等价于原来的相对路径写法；前后端分离部署时则指向真正的后端。
  const target: RequestInfo | URL =
    typeof input === 'string' && input.startsWith('/') ? (await getApiBase()) + input : input
  const res = await fetch(target, { ...init, headers })
  if (res.status === 401 && !String(input).includes('/api/auth/')) {
    auth.logout()
    const path = window.location.pathname
    if (!path.startsWith('/login')) {
      const redirect = encodeURIComponent(window.location.pathname + window.location.search)
      window.location.assign(`/login?redirect=${redirect}`)
    }
  }
  return res
}

export async function parseApiError(res: Response, fallback = '请求失败'): Promise<string> {
  try {
    const body = await res.json()
    if (body?.detail) {
      return typeof body.detail === 'string' ? body.detail : JSON.stringify(body.detail)
    }
  } catch {
    /* ignore */
  }
  return fallback || `HTTP ${res.status}`
}
