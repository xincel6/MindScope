import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { AuthUser } from '@/api/auth'
import { fetchMeApi, loginApi, registerApi } from '@/api/auth'
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
    logout,
    loadUser,
    initFromStorage,
  }
})
