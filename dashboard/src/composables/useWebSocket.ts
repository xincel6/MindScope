import { ref, onUnmounted } from 'vue'
import { getStoredToken } from '@/api/http'

export interface WsCallbacks {
  onMessage: (data: any) => void
  onOpen?: () => void
  onClose?: () => void
  onError?: (e: Event) => void
}

export function useWebSocket(callbacks: WsCallbacks) {
  const wsStatus = ref<'connecting' | 'connected' | 'disconnected'>('disconnected')
  const reconnectCount = ref(0)
  const maxReconnect = 5

  let ws: WebSocket | null = null
  let heartbeatTimer: ReturnType<typeof setInterval> | null = null
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null

  function connect() {
    if (ws?.readyState === WebSocket.OPEN || ws?.readyState === WebSocket.CONNECTING) return

    wsStatus.value = 'connecting'
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:'
    const token = getStoredToken()
    const qs = token ? `?token=${encodeURIComponent(token)}` : ''
    const url = `${protocol}//${location.host}/ws/analysis${qs}`

    try {
      ws = new WebSocket(url)

      ws.onopen = () => {
        wsStatus.value = 'connected'
        reconnectCount.value = 0
        callbacks.onOpen?.()
        startHeartbeat()
      }

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)
          callbacks.onMessage(data)
        } catch {
          // ignore malformed messages
        }
      }

      ws.onclose = () => {
        wsStatus.value = 'disconnected'
        stopHeartbeat()
        callbacks.onClose?.()
        tryReconnect()
      }

      ws.onerror = (e) => {
        callbacks.onError?.(e)
        ws?.close()
      }
    } catch {
      wsStatus.value = 'disconnected'
      tryReconnect()
    }
  }

  function send(data: unknown) {
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(data))
    }
  }

  function disconnect() {
    stopHeartbeat()
    clearReconnectTimer()
    if (ws) {
      ws.onclose = null
      ws.close()
      ws = null
    }
    wsStatus.value = 'disconnected'
  }

  function startHeartbeat() {
    stopHeartbeat()
    heartbeatTimer = setInterval(() => {
      if (ws?.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'ping' }))
      }
    }, 30000)
  }

  function stopHeartbeat() {
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer)
      heartbeatTimer = null
    }
  }

  function clearReconnectTimer() {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
  }

  function tryReconnect() {
    if (reconnectCount.value >= maxReconnect) return
    const delay = Math.min(1000 * Math.pow(2, reconnectCount.value), 16000)
    reconnectCount.value++
    reconnectTimer = setTimeout(connect, delay)
  }

  onUnmounted(disconnect)

  return { wsStatus, connect, disconnect, send }
}
