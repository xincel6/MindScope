import { watch } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'
import { useWebSocket } from '@/composables/useWebSocket'

/**
 * 全应用唯一的分析 WebSocket 连接。
 * 挂在 AppLayout 上而不是工作台页面上：切到素材库 / 历史报告时分析不能断。
 * 逻辑从旧 MainVideoPlayer.vue 原样迁移，额外加两处守卫：
 *   1. 只有 analyzing 为 true 才建连，避免「素材库只 select」时把旧 run 发给新素材；
 *   2. 显式断开时立刻清 initSent，重连后必须重新发 init。
 */
let initSent = false

export function useAnalysisSocket() {
  const store = useDashboardStore()

  const { wsStatus, ensureConnected, disconnect, send } = useWebSocket({
    onMessage(data: any) {
      store.handleWsMessage(data)
      if (data?.type === 'done' || data?.type === 'error') {
        disconnect()
      }
    },
    onOpen() {
      store.setWsConnected(true)
    },
    onClose() {
      store.setWsConnected(false)
    },
    onError() {
      store.setWsConnected(false)
    },
    shouldReconnect: () => store.analyzing,
  })

  function sendInitIfNeeded(): boolean {
    if (initSent || !store.selectedMediaId) return false
    if (!send({ id: store.selectedMediaId })) return false
    initSent = true
    return true
  }

  watch(wsStatus, (v) => {
    store.setWsConnected(v === 'connected')
    if (v === 'connected') {
      if (store.analyzing) sendInitIfNeeded()
    } else {
      initSent = false
    }
  })

  watch(
    () => store.analysisRunId,
    async (runId) => {
      if (!runId || !store.analyzing) return
      const mediaId = store.selectedMediaId
      if (!mediaId) return
      if (initSent) {
        disconnect()
        initSent = false
      }
      const ok = await ensureConnected()
      // 建连期间用户可能已切换素材 / 取消分析：旧 run 不再发送 init
      if (!ok || store.analysisRunId !== runId || store.selectedMediaId !== mediaId) return
      sendInitIfNeeded()
    },
    { immediate: true },
  )

  watch(
    () => store.analyzing,
    (analyzing) => {
      // 分析结束或用户在素材库切换素材（reset 会把 analyzing 置 false）后主动断开，
      // 避免旧 run 的帧落到新素材上。
      if (!analyzing) {
        disconnect()
        initSent = false
      }
    },
  )
}
