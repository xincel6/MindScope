<script setup lang="ts">
import { ref, watch, onMounted, computed, nextTick } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'

const store = useDashboardStore()
const canvasRef = ref<HTMLCanvasElement | null>(null)
const legendRef = ref<HTMLCanvasElement | null>(null)

const props = withDefaults(
  defineProps<{
    /** 嵌进工作台卡片时不画自己的白底 / 边框 / 标题 */
    embedded?: boolean
    /** canvas 逻辑分辨率（CSS 宽度随容器收缩，最大到该值） */
    size?: number
  }>(),
  { embedded: false, size: 200 },
)

function drawFace() {
  const canvas = canvasRef.value
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  if (!ctx) return

  ctx.clearRect(0, 0, props.size, props.size)

  if (store.faceImageData) {
    const img = new Image()
    img.onload = () => {
      ctx.drawImage(img, 0, 0, props.size, props.size)

      if (store.heatmapData.length && store.heatmapData[0]?.length) {
        drawHeatmap(ctx, store.heatmapData)
        drawRegionBoxes(ctx)
      }
    }
    img.src = `data:image/png;base64,${store.faceImageData}`
  } else {
    ctx.strokeStyle = 'rgba(148, 163, 184, 0.12)'
    ctx.lineWidth = 0.5
    const step = props.size / 8
    for (let i = 0; i <= props.size; i += step) {
      ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, props.size); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(0, i); ctx.lineTo(props.size, i); ctx.stroke()
    }
    ctx.strokeStyle = 'rgba(148, 163, 184, 0.3)'
    ctx.lineWidth = 1
    ctx.beginPath(); ctx.moveTo(props.size / 2, 0); ctx.lineTo(props.size / 2, props.size); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(0, props.size / 2); ctx.lineTo(props.size, props.size / 2); ctx.stroke()
    ctx.fillStyle = 'rgba(148, 163, 184, 0.5)'
    ctx.font = '11px sans-serif'
    ctx.textAlign = 'center'
    ctx.fillText('等待推理数据...', props.size / 2, props.size / 2 - 6)
  }
}

function drawRegionBoxes(ctx: CanvasRenderingContext2D) {
  // Draw anatomical region annotations on the aligned face
  // Canonical face 128×128: eyes at y≈52 (left x≈38, right x≈90), mouth at y≈90 x≈64
  // Scaled to props.size
  const scale = props.size / 128

  const regions = [
    { label: '眶周', cx: 38, cy: 52, color: 'rgba(0,230,180,0.5)' },
    { label: '眶周', cx: 90, cy: 52, color: 'rgba(0,230,180,0.5)' },
    { label: '口周', cx: 64, cy: 92, color: 'rgba(77,138,240,0.5)' },
    { label: '眉间', cx: 64, cy: 36, color: 'rgba(240,160,40,0.5)' },
  ]

  ctx.lineWidth = 1.5
  ctx.font = `${Math.round(9 * scale)}px sans-serif`
  ctx.textAlign = 'center'

  for (const r of regions) {
    const cx = r.cx * scale
    const cy = r.cy * scale
    const rw = 26 * scale
    const rh = 18 * scale

    ctx.strokeStyle = r.color
    ctx.setLineDash([4, 3])
    ctx.beginPath()
    ctx.roundRect(cx - rw / 2, cy - rh / 2, rw, rh, 4)
    ctx.stroke()
    ctx.setLineDash([])

    ctx.fillStyle = r.color
    ctx.fillText(r.label, cx, cy - rh / 2 - 4)
  }
}

function drawHeatmap(ctx: CanvasRenderingContext2D, data: number[][]) {
  const rows = data.length
  const cols = data[0].length
  const cellW = props.size / cols
  const cellH = props.size / rows

  const offCanvas = document.createElement('canvas')
  offCanvas.width = props.size
  offCanvas.height = props.size
  const offCtx = offCanvas.getContext('2d')
  if (!offCtx) return

  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const v = Math.min(Math.max(data[y][x], 0), 1)
      offCtx.fillStyle = heatColor(v)
      offCtx.fillRect(x * cellW, y * cellH, cellW, cellH)
    }
  }

  ctx.globalAlpha = 0.4
  ctx.drawImage(offCanvas, 0, 0)
  ctx.globalAlpha = 1
}

function heatColor(t: number): string {
  const r = Math.min(Math.max(t < 0.25 ? 0 : t < 0.5 ? (t - 0.25) * 4 : 1, 0), 1)
  const g = Math.min(Math.max(t < 0.25 ? t * 4 : t < 0.75 ? 1 : (1 - t) * 4, 0), 1)
  const b = Math.min(Math.max(t < 0.5 ? (0.5 - t) * 4 : 0, 0), 1)
  return `rgba(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)},0.8)`
}

/**
 * P5 T6c：图例色带改为 canvas 连续插值。
 * 端点色仍取 tokens.css 的 --heat-1..5（与画布 heatColor() 同一条蓝→青→绿→黄→红
 * 路径），createLinearGradient 在端点之间做连续插值；原来 5 个离散色块与热力图
 * 实际的连续着色不一致，会让人误读色带含义。
 * canvas 里无法直接使用 CSS 变量，所以先 getComputedStyle 取真实色值再绘制。
 */
function drawLegend() {
  const canvas = legendRef.value
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  if (!ctx) return

  const dpr = window.devicePixelRatio || 1
  const width = 280
  const height = 12
  canvas.width = Math.round(width * dpr)
  canvas.height = Math.round(height * dpr)
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

  const styles = getComputedStyle(document.documentElement)
  const stops = ['--heat-1', '--heat-2', '--heat-3', '--heat-4', '--heat-5']
    .map((name) => styles.getPropertyValue(name).trim())
    .filter(Boolean)
  if (stops.length < 2) return

  const gradient = ctx.createLinearGradient(0, 0, width, 0)
  stops.forEach((color, index) => gradient.addColorStop(index / (stops.length - 1), color))
  ctx.fillStyle = gradient
  ctx.fillRect(0, 0, width, height)
}

watch(() => [store.faceImageData, store.heatmapData, props.size], drawFace, { deep: true })
watch(
  () => store.heatmapData.length,
  async () => {
    await nextTick()
    drawLegend()
  },
)
onMounted(() => {
  drawFace()
  drawLegend()
})

// Compute top-3 attention hotspots for medical interpretation
const hotspots = computed(() => {
  if (!store.heatmapData.length) return []
  const data = store.heatmapData
  const h = data.length
  const w = data[0]?.length ?? 0
  const points: { x: number; y: number; v: number }[] = []
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      points.push({ x, y, v: data[y][x] })
    }
  }
  points.sort((a, b) => b.v - a.v)
  return points.slice(0, 3).map((p) => {
    const regionX = p.x / w // 0..1
    const regionY = p.y / h
    let region = '面部中央区域'
    if (regionY < 0.3 && regionX > 0.3 && regionX < 0.7) region = '眉间/前额区域'
    else if (regionY > 0.25 && regionY < 0.45 && (regionX < 0.35 || regionX > 0.65)) region = '眶周区域（眼轮匝肌）'
    else if (regionY > 0.5 && regionX > 0.3 && regionX < 0.7) region = '口周区域（降口角肌）'
    else if (regionY > 0.4 && regionY < 0.55 && regionX > 0.35 && regionX < 0.65) region = '鼻唇沟区域'
    return { region, value: (p.v * 100).toFixed(1) }
  })
})
</script>

<template>
  <div class="face-preview" :class="{ 'face-preview--embedded': embedded }">
    <div v-if="!embedded" class="section-title section-title--bordered">
      注意力热力图
      <span class="section-subtitle">MSSTformer</span>
    </div>

    <div class="face-body">
      <div class="face-canvas-wrapper">
        <canvas ref="canvasRef" :width="props.size" :height="props.size" class="face-canvas" />
        <div v-if="store.heatmapData.length" class="colormap-bar">
          <span class="cm-label">低</span>
          <div class="cm-gradient">
            <canvas
              ref="legendRef"
              class="cm-gradient-canvas"
              role="img"
              aria-label="注意力热力色带：低到高"
            />
          </div>
          <span class="cm-label">高</span>
        </div>
      </div>

      <div v-if="store.heatmapData.length && hotspots.length" class="medical-notes">
        <p class="notes-text">
          重点关注
          <span class="highlight">{{ hotspots[0]?.region }}</span>
          （{{ hotspots[0]?.value }}%）
          <template v-if="hotspots[1]">
            ，其次 {{ hotspots[1]?.region }}（{{ hotspots[1]?.value }}%）
          </template>
        </p>
      </div>

      <div v-else-if="!store.faceImageData" class="face-placeholder">
        <span>等待模型推理...</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.face-preview {
  display: flex;
  flex-direction: column;
  padding: 12px 14px;
  height: 100%;
  overflow-y: auto;
}

.face-preview:not(.face-preview--embedded) {
  background: var(--bg-card);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-card);
}

.face-preview--embedded {
  padding: 0;
  height: auto;
  overflow: visible;
}

.face-preview--embedded .face-canvas {
  width: 100%;
  max-width: 280px;
  height: auto;
}

.face-preview--embedded .colormap-bar {
  width: 100%;
  max-width: 280px;
}

.face-canvas-wrapper {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.face-canvas {
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  width: 140px;
  height: 140px;
}

.colormap-bar {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 140px;
}

.cm-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  flex-shrink: 0;
}

/* 热力图色带图例：canvas 连续插值（端点色 --heat-1..5，与 heatColor() 同一路径）。 */
.cm-gradient {
  flex: 1;
  height: 6px;
  overflow: hidden;
  border-radius: var(--radius-pill);
}

.cm-gradient-canvas {
  display: block;
  width: 100%;
  height: 100%;
}

.face-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-height: 0;
}

.medical-notes {
  padding: 8px 10px;
  background: var(--bg-inset);
  border: 1px solid var(--border);
  border-radius: var(--radius-tag);
  flex: 1;
  overflow-y: auto;
}

.notes-text {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  line-height: 1.6;
  margin: 0;
}

.highlight {
  color: var(--color-primary-text);
  font-weight: 600;
}

.face-placeholder {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-secondary);
  font-size: var(--font-xs);
}
</style>
