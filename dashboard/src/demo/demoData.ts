/**
 * 演示数据生成器 —— 只服务于 `/demo` 路由
 * ================================================================
 * 本文件里的每一个数字都是**编造的**，唯一用途是让界面在没有任何真实数据时
 * 也能看出「长什么样」。主流程（`/`、`/analysis`）不 import 本文件。
 *
 * 纪律（P2）：
 *   1. 这里只产出普通数据，不 import store、不改任何状态机；
 *      灌入 / 清空由 `views/DemoView.vue` 负责，页面上的常驻横幅负责标注。
 *   2. 不伪造人脸图（`aligned_face` 一律空串）—— 假的人脸比假的分更危险。
 *   3. 素材名用「示例样本」而非「患者 X」：即使横幅被截图裁掉，也能一眼看出是假数据。
 */

import type { AnalysisFrame, MediaItem } from '@/api/index'

/** 演示素材 id 前缀：与后端真实 id 天然分开，`/demo` 清场时不会误删真数据 */
export const DEMO_ID_PREFIX = 'demo-'

/** 一次演示播放的帧数（与主流程按批次推理的 24 帧量级同观感） */
export const DEMO_TOTAL_FRAMES = 60
/** 每帧间隔（毫秒） */
export const DEMO_FRAME_INTERVAL_MS = 300
/** 演示热力图边长（后端 services/inference.py 输出 16×16，这里对齐） */
export const DEMO_HEATMAP_SIZE = 16

/**
 * 6 条虚构素材。字段结构必须与 `MediaItem` 完全一致，
 * 这样媒体库组件不用为演示模式写任何分支。
 */
export function buildDemoMediaList(): MediaItem[] {
  return [
    {
      id: `${DEMO_ID_PREFIX}1`,
      name: '示例样本 A · 初始访谈.mp4',
      type: 'video',
      thumbnail_url: '',
      url: '',
      duration: 120,
      created_at: '2026-04-10',
    },
    {
      id: `${DEMO_ID_PREFIX}2`,
      name: '示例样本 B · 随访记录.mp4',
      type: 'video',
      thumbnail_url: '',
      url: '',
      duration: 90,
      created_at: '2026-04-12',
    },
    {
      id: `${DEMO_ID_PREFIX}3`,
      name: '示例样本 C · 情绪评估.png',
      type: 'image',
      thumbnail_url: '',
      url: '',
      created_at: '2026-04-15',
    },
    {
      id: `${DEMO_ID_PREFIX}4`,
      name: '示例样本 D · 心理咨询.mp4',
      type: 'video',
      thumbnail_url: '',
      url: '',
      duration: 180,
      created_at: '2026-04-18',
    },
    {
      id: `${DEMO_ID_PREFIX}5`,
      name: '示例样本 A · 复诊.png',
      type: 'image',
      thumbnail_url: '',
      url: '',
      created_at: '2026-04-20',
    },
    {
      id: `${DEMO_ID_PREFIX}6`,
      name: '示例样本 E · 干预前后.mp4',
      type: 'video',
      thumbnail_url: '',
      url: '',
      duration: 60,
      created_at: '2026-04-22',
    },
  ]
}

/** 高斯形状的 16×16「热力图」。纯几何构造，不含任何模型输出 */
export function generateDemoHeatmap(size: number = DEMO_HEATMAP_SIZE): number[][] {
  const data: number[][] = []
  for (let y = 0; y < size; y++) {
    const row: number[] = []
    for (let x = 0; x < size; x++) {
      const dx = (x - size / 2) / (size / 4)
      const dy = (y - size / 2) / (size / 4)
      const v = Math.exp(-(dx * dx + dy * dy) / 1.5)
      row.push(Math.round(v * 100) / 100)
    }
    data.push(row)
  }
  return data
}

export interface DemoFrameStreamOptions {
  totalFrames?: number
  intervalMs?: number
  /** 每产出一帧调用一次（由调用方决定怎么用，本模块不碰 store） */
  onFrame: (frame: AnalysisFrame) => void
  /** 播完（或被 stop 之外的正常结束）时调用一次 */
  onDone?: () => void
}

export interface DemoFrameStream {
  /** 立即停止，不再产出任何帧 */
  stop: () => void
}

/**
 * 按固定节拍产出一段「看起来像分析」的帧序列：
 * 分数从 18–28 起步、正弦+噪声起伏，最终收敛到 progress = 1。
 * 返回句柄由调用方负责 stop（组件卸载时必须调）。
 */
export function createDemoFrameStream(options: DemoFrameStreamOptions): DemoFrameStream {
  const totalFrames = options.totalFrames ?? DEMO_TOTAL_FRAMES
  const intervalMs = options.intervalMs ?? DEMO_FRAME_INTERVAL_MS
  // 起点 18–28 分：落在「轻度 ~ 中度」区间，画面上比 0 分更像一次真实评估
  const baseScore = 18 + Math.random() * 10
  let frameId = 0
  let stopped = false

  const timer = setInterval(() => {
    if (stopped) return
    frameId++
    const progress = frameId / totalFrames
    const noise = Math.sin(frameId * 0.3) * 6 + (Math.random() - 0.5) * 4
    const score = Math.max(0, Math.min(63, baseScore + noise))

    options.onFrame({
      frame_id: frameId,
      timestamp: Date.now() / 1000,
      bdi_score: score,
      // 不伪造人脸：演示页的人脸区应显示空态，而不是一张来源不明的脸
      aligned_face: '',
      heatmap_data: generateDemoHeatmap(),
      inference_time_ms: 24 + Math.random() * 8,
      progress,
    })

    if (frameId >= totalFrames) {
      stop()
      options.onDone?.()
    }
  }, intervalMs)

  function stop() {
    if (stopped) return
    stopped = true
    clearInterval(timer)
  }

  return { stop }
}
