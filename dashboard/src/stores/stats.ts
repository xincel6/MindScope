import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { StatsData } from '@/api/index'
import { fetchStats } from '@/api/index'

export const useStatsStore = defineStore('stats', () => {
  const loading = ref(false)
  const error = ref('')
  const data = ref<StatsData | null>(null)

  async function load() {
    loading.value = true
    error.value = ''
    try {
      data.value = await fetchStats()
    } catch (e: any) {
      error.value = e.message ?? '加载失败'
    } finally {
      loading.value = false
    }
  }

  return { loading, error, data, load }
})
