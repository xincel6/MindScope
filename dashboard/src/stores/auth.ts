import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { AuthUser } from '@/api/auth'
import {
  fetchMeApi,
  loginApi,
  registerApi,
  sendCodeApi,
  resetPasswordApi,
} from '@/api/auth'
import { getStoredToken, setStoredToken } from '@/api/http'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string | null>(getStoredToken())
  const user = ref<AuthUser | null>(null)
  const loading = ref(false)

  const isAuthenticated = computed(() => !!token.value)

  function setToken(accessToken: string) {
    token.value = accessToken
    setStoredToken(accessToken)
  }

  function logout() {
    token.value = null
    user.value = null
    setStoredToken(null)
  }

  async function login(username: string, password: string) {
    loading.value = true
    try {
      const data = await loginApi(username, password)
      setToken(data.access_token)
      await loadUser()
    } finally {
      loading.value = false
    }
  }

  /**
   * 注册 · 邮箱与验证码必填（2026-10-21 起后端强制）
   *
   * 失败会原样抛出后端 detail（"用户名已存在" / "邮箱已被注册" /
   * "验证码错误或已过期" / "密码需同时包含大写字母、小写字母和特殊字符…"），
   * 由视图层直接展示，不在这里吞掉。
   */
  async function register(
    username: string,
    password: string,
    email: string,
    verificationCode: string,
  ) {
    loading.value = true
    try {
      const data = await registerApi(username, password, email, verificationCode)
      setToken(data.access_token)
      await loadUser()
    } finally {
      loading.value = false
    }
  }

  /**
   * 发送验证码 · 注册与找回密码共用
   *
   * ★ 不写 `loading`：它是表单里的辅助动作，占用 loading 会让"登录系统"
   *   按钮一起转圈，误导用户以为正在登录。忙碌态由视图层自己管。
   */
  async function sendCode(email: string, purpose: 'register' | 'reset'): Promise<string> {
    return sendCodeApi(email, purpose)
  }

  /** 邮箱找回密码 · 成功后需用户自行用新密码重新登录 */
  async function resetPassword(
    email: string,
    verificationCode: string,
    newPassword: string,
  ): Promise<string> {
    return resetPasswordApi(email, verificationCode, newPassword)
  }

  async function loadUser() {
    if (!token.value) {
      user.value = null
      return
    }
    try {
      user.value = await fetchMeApi()
    } catch {
      logout()
    }
  }

  async function initFromStorage() {
    if (token.value) {
      await loadUser()
    }
  }

  return {
    token,
    user,
    loading,
    isAuthenticated,
    login,
    register,
    sendCode,
    resetPassword,
    logout,
    loadUser,
    initFromStorage,
  }
})
