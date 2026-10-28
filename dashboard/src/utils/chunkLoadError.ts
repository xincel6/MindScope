/** 懒加载 chunk 失败：旧 index 缓存、发布切换或隧道短断都会触发。 */
const CHUNK_ERROR_RE =
  /Failed to fetch dynamically imported module|Importing a module script failed|error loading dynamically imported module|ChunkLoadError/i
const RELOAD_KEY = 'mindscope:chunk-reload-at'
const RELOAD_COOLDOWN_MS = 15000

export function isChunkLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error)
  return CHUNK_ERROR_RE.test(message)
}

/**
 * 遇到 chunk 加载失败时整页重载一次，拿到最新的 index 与资源清单。
 * 用 sessionStorage 做冷却，避免隧道持续故障时无限刷新。
 */
export function recoverFromChunkLoadError(fullPath?: string): boolean {
  let last = 0
  try {
    last = Number(sessionStorage.getItem(RELOAD_KEY) || 0)
  } catch {
    return false
  }
  const now = Date.now()
  if (now - last < RELOAD_COOLDOWN_MS) return false
  try {
    sessionStorage.setItem(RELOAD_KEY, String(now))
  } catch {
    return false
  }
  window.location.replace(fullPath || window.location.pathname + window.location.search)
  return true
}
