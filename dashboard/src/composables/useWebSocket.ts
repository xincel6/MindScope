import { ref, onUnmounted } from 'vue'
import { getStoredToken } from '@/api/http'
import { getApiBase } from '@/api/baseResolver'

export interface WsCallbacks {
  onMessage: (data: any) => void
  onOpen?: () => void
  onClose?: () => void
  onError?: (e: Event) => void
  /**
   * 连接"意外"断开时是否值得自动重连。
   * 默认 false：本项目的 WS 只在分析期间需要，分析结束或用户返回后由调用方主动
   * disconnect，不做无谓重连（否则会形成「连上 → 15 秒后服务端超时关掉 → 再连」的循环）。
   */
  shouldReconnect?: () => boolean
}

export function useWebSocket(callbacks: WsCallbacks) {
  const wsStatus = ref<'connecting' | 'connected' | 'disconnected'>('disconnected')
  const reconnectCount = ref(0)
  const maxReconnect = 5
  const connectTimeoutMs = 8000

  let ws: WebSocket | null = null
  let heartbeatTimer: ReturnType<typeof setInterval> | null = null
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null
  /** 正在建立的连接：并发调用 ensureConnected 时复用同一次握手 */
  let opening: Promise<boolean> | null = null
  /** 主动 disconnect 之后不再自动重连 */
  let intentionalClose = false

  /**
   * 建立连接并等待握手完成；已连接时立即返回 true。
   * 按需连接的入口——不分析就不要连。
   */
  async function ensureConnected(): Promise<boolean> {
    if (ws?.readyState === WebSocket.OPEN) return true
    if (opening) return opening

    intentionalClose = false
    wsStatus.value = 'connecting'

    opening = (async (): Promise<boolean> => {
      try {
        // 与 http 走同一套后端地址解析：同源时基址为 ''，就用页面自身的主机
        const base = await getApiBase()
        const wsOrigin =
          base === ''
            ? `${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}`
            : base.replace(/^http/i, 'ws')
        const token = getStoredToken()
        const qs = token ? `?token=${encodeURIComponent(token)}` : ''

        const socket = new WebSocket(`${wsOrigin}/ws/analysis${qs}`)
        ws = socket

        return await new Promise<boolean>((resolve) => {
          let settled = false
          const finish = (ok: boolean) => {
            if (settled) return
            settled = true
            clearTimeout(timer)
            resolve(ok)
          }
          const timer = setTimeout(() => {
            finish(false)
            // CONNECTING 卡住的 socket 要作废，否则下一次 ensureConnected 会复用它
            try {
              socket.close()
            } catch {
              /* ignore */
            }
          }, connectTimeoutMs)

          socket.onopen = () => {
            wsStatus.value = 'connected'
            reconnectCount.value = 0
            callbacks.onOpen?.()
            startHeartbeat()
            finish(true)
          }

          socket.onmessage = (event) => {
            try {
              callbacks.onMessage(JSON.parse(event.data))
            } catch {
              // ignore malformed messages
            }
          }

          socket.onclose = () => {
            wsStatus.value = 'disconnected'
            stopHeartbeat()
            callbacks.onClose?.()
            finish(false)
            tryReconnect()
          }

          socket.onerror = (e) => {
            callbacks.onError?.(e)
            finish(false)
            try {
              socket.close()
            } catch {
              /* ignore */
            }
          }
        })
      } catch {
        wsStatus.value = 'disconnected'
        tryReconnect()
        return false
      } finally {
        opening = null
      }
    })()

    return opening
  }

  function send(data: unknown): boolean {
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(data))
      return true
    }
    return false
  }

  /** 主动收工：关连接且不再重连 */
  function disconnect() {
    intentionalClose = true
    stopHeartbeat()
    clearReconnectTimer()
    reconnectCount.value = 0
    if (ws) {
      ws.onopen = null
      ws.onmessage = null
      ws.onclose = null
      ws.onerror = null
      try {
        ws.close()
      } catch {
        /* ignore */
      }
      ws = null
    }
    wsStatus.value = 'disconnected'
  }

  function startHeartbeat() {
    stopHeartbeat()
    // 握手后分析可能还要等一会儿才开始，心跳顺带保活；
    // 后端在等待首条 media id 时会忽略心跳，不会因此判成非法请求。
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
    if (intentionalClose) return
    if (!callbacks.shouldReconnect?.()) return
    if (reconnectCount.value >= maxReconnect) return
    const delay = Math.min(1000 * Math.pow(2, reconnectCount.value), 16000)
    reconnectCount.value++
    clearReconnectTimer()
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      void ensureConnected()
    }, delay)
  }

  onUnmounted(disconnect)

  return { wsStatus, ensureConnected, disconnect, send }
}
