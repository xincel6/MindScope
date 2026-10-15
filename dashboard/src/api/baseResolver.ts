/**
 * 后端地址自动解析：同源 → 本地 → 远程兜底
 *
 * 为什么要它：
 *   前端所有请求（/api、/ws、/media）原本都是相对路径，只有「前端由后端同一个
 *   端口托管」（backend/serve_all.py 把 dist 挂到 8000）时才能用。一旦把 dist
 *   单独部署到静态服务器、后端跑在另一个端口或域名，相对路径就会打到静态服务器
 *   上，接口全部 404。
 *
 * 解析优先级（候选地址并发探测，只等一个超时，按优先级取第一个通的）：
 *   0. 手动指定：URL 加 ?api=http://x:8000（会记住）或 localStorage 的
 *      mindscope_api_base —— 排在最前，方便现场排查时临时切换
 *   1. 同源：页面本身由后端托管时最正确（部署到任何服务器都不用改配置，远程
 *      部署的端口天然可用）
 *   2. 本地：http://127.0.0.1:8000 / http://localhost:8000（本机开着后端就用本机）
 *   3. 远程兜底：VITE_REMOTE_BACKEND（构建时可配），默认是已部署好的服务器
 *   4. 都不通：同源页面继续用同源（保持原有报错行为），非 http(s) 页面用远程地址
 *
 * 解析结果会打印到控制台，并挂在 window.__MINDSCOPE_API_BASE__ 上，便于排查。
 */

const STORAGE_KEY = 'mindscope_api_base'

/** 单个候选地址的探测超时（毫秒）。并发探测，所以总等待时间就是一个超时。 */
const PROBE_TIMEOUT_MS = 1500

/** 远程兜底地址；构建时可用 VITE_REMOTE_BACKEND 覆盖。 */
const DEFAULT_REMOTE = 'http://100.122.178.113:8000'

const REMOTE_BACKEND: string =
  (import.meta.env.VITE_REMOTE_BACKEND as string | undefined)?.trim() || DEFAULT_REMOTE

/** 已解析的地址：'' 表示同源（相对路径），null 表示还没解析 */
let resolved: string | null = null
let resolving: Promise<string> | null = null

function stripTrailingSlash(url: string): string {
  return url.replace(/\/+$/, '')
}

function isHttpPage(): boolean {
  return location.protocol === 'http:' || location.protocol === 'https:'
}

/** 探测某个候选地址是否是本项目的后端（用 /health 判断，避免认错服务）。 */
function probe(base: string): Promise<boolean> {
  const url = base === '' ? '/health' : `${base}/health`
  return new Promise<boolean>((done) => {
    const controller = new AbortController()
    const timer = setTimeout(() => {
      controller.abort()
      done(false)
    }, PROBE_TIMEOUT_MS)

    fetch(url, { signal: controller.signal, cache: 'no-store' })
      .then(async (res) => {
        clearTimeout(timer)
        if (!res.ok) return done(false)
        // 必须解析出 {"status":"ok"} 才算命中：静态服务器对未知路径常返回 200+HTML
        const data = await res.json().catch(() => null)
        done(!!data && (data as { status?: string }).status === 'ok')
      })
      .catch(() => {
        clearTimeout(timer)
        done(false)
      })
  })
}

async function decide(): Promise<string> {
  // 0) 手动指定（?api=... 优先，并记住它）
  const fromQuery = new URLSearchParams(location.search).get('api')
  if (fromQuery && fromQuery.trim()) {
    const value = stripTrailingSlash(fromQuery.trim())
    try {
      localStorage.setItem(STORAGE_KEY, value)
    } catch {
      /* 隐私模式忽略 */
    }
    return value
  }
  let stored: string | null = null
  try {
    stored = localStorage.getItem(STORAGE_KEY)
  } catch {
    /* 隐私模式忽略 */
  }
  if (stored && stored.trim()) return stripTrailingSlash(stored.trim())

  // 1~3) 候选列表（按优先级），'' 代表同源
  const candidates: string[] = []
  if (isHttpPage()) candidates.push('')
  candidates.push('http://127.0.0.1:8000', 'http://localhost:8000')
  const remote = stripTrailingSlash(REMOTE_BACKEND)
  if (remote && !candidates.includes(remote)) candidates.push(remote)

  // 立刻全部并发探测（延迟互相重叠），但按优先级顺序取结果：
  //   · 同源可用时（正常部署）几毫秒就返回，不会等远程探测超时
  //   · 高优先级候选要等它自己出结果，避免「本机后端稍慢」被远程抢先命中
  const probes = candidates.map(probe)
  for (let i = 0; i < probes.length; i += 1) {
    if (await probes[i]) return candidates[i]
  }

  // 4) 都不通
  return isHttpPage() ? '' : remote
}

/**
 * 取得后端基址：'' 表示同源（请求直接用相对路径）。
 * 只解析一次，之后走缓存。
 */
export async function getApiBase(): Promise<string> {
  if (resolved !== null) return resolved
  if (!resolving) {
    resolving = decide().then((base) => {
      resolved = base
      const shown = base === '' ? location.origin : base
      const how = base === '' ? '（与页面同源）' : ''
      console.info(`[MindScope] 后端地址：${shown}${how}`)
      try {
        ;(window as unknown as Record<string, unknown>).__MINDSCOPE_API_BASE__ = shown
      } catch {
        /* ignore */
      }
      return base
    })
  }
  return resolving
}

/**
 * 同步取已解析的基址。
 * 还没解析完时返回 ''（等于同源），保证不会把请求打歪。
 * 注意：所有媒体地址都来自后端接口，而接口请求本身会先 await 解析，
 * 所以渲染媒体时解析必然已完成。
 */
export function getApiBaseSync(): string {
  return resolved ?? ''
}

/** 把后端返回的相对媒体地址（形如 /media/xxx.jpg）补成浏览器可访问的地址。 */
export function resolveMediaUrl(url: string | undefined | null): string {
  if (!url) return ''
  // 已经是绝对地址或 data/blob，原样返回
  if (/^(https?:|blob:|data:)/i.test(url)) return url
  // 只处理后端返回的媒体相对路径，其它相对路径（如前端自身静态资源）不动
  if (!url.startsWith('/media/')) return url
  return getApiBaseSync() + url
}

/**
 * 预热解析：应用一启动就在后台探测，用户的第一次点击就不用再等。
 * 同时让 window.__MINDSCOPE_API_BASE__ 尽早可用，便于现场排查。
 */
export function warmUpApiBase(): void {
  void getApiBase()
}
