<script setup lang="ts">
import { ref, watch, onMounted, computed } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'

const store = useDashboardStore()
const canvasRef = ref<HTMLCanvasElement | null>(null)

const SIZE = 200

function drawFace() {
  const canvas = canvasRef.value
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  if (!ctx) return

  ctx.clearRect(0, 0, SIZE, SIZE)

  if (store.faceImageData) {
    const img = new Image()
    img.onload = () => {
      ctx.drawImage(img, 0, 0, SIZE, SIZE)

      if (store.heatmapData.length && store.heatmapData[0]?.length) {
        drawHeatmap(ctx, store.heatmapData)
        drawRegionBoxes(ctx)
      }
    }
    img.src = `data:image/png;base64,${store.faceImageData}`
  } else {
    ctx.strokeStyle = 'rgba(148, 163, 184, 0.12)'
    ctx.lineWidth = 0.5
    const step = SIZE / 8
    for (let i = 0; i <= SIZE; i += step) {
      ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, SIZE); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(0, i); ctx.lineTo(SIZE, i); ctx.stroke()
    }
    ctx.strokeStyle = 'rgba(148, 163, 184, 0.3)'
    ctx.lineWidth = 1
    ctx.beginPath(); ctx.moveTo(SIZE / 2, 0); ctx.lineTo(SIZE / 2, SIZE); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(0, SIZE / 2); ctx.lineTo(SIZE, SIZE / 2); ctx.stroke()
    ctx.fillStyle = 'rgba(148, 163, 184, 0.5)'
    ctx.font = '11px sans-serif'
    ctx.textAlign = 'center'
    ctx.fillText('等待推理数据...', SIZE / 2, SIZE / 2 - 6)
  }
}

function drawRegionBoxes(ctx: CanvasRenderingContext2D) {
  // Draw anatomical region annotations on the aligned face
  // Canonical face 128×128: eyes at y≈52 (left x≈38, right x≈90), mouth at y≈90 x≈64
  // Scaled to SIZE
  const scale = SIZE / 128

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
  const cellW = SIZE / cols
  const cellH = SIZE / rows

  const offCanvas = document.createElement('canvas')
  offCanvas.width = SIZE
  offCanvas.height = SIZE
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

watch(() => [store.faceImageData, store.heatmapData], drawFace, { deep: true })
onMounted(drawFace)

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
  <div class="face-preview">
    <div class="section-title section-title--bordered">
      注意力热力图
      <span class="section-subtitle">MSSTformer</span>
    </div>

    <div class="face-body">
      <div class="face-canvas-wrapper">
        <canvas ref="canvasRef" :width="SIZE" :height="SIZE" class="face-canvas" />
        <div v-if="store.heatmapData.length" class="colormap-bar">
          <span class="cm-label">低</span>
          <div class="cm-gradient" />
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
  background: var(--bg-card);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-card);
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
  font-size: 9px;
  color: var(--text-muted);
  flex-shrink: 0;
}

.cm-gradient {
  flex: 1;
  height: 6px;
  border-radius: 3px;
  background: linear-gradient(to right, #0000ff, #00ffff, #00ff00, #ffff00, #ff0000);
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
  background: var(--bg-muted);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  flex: 1;
  overflow-y: auto;
}

.notes-text {
  font-size: 11px;
  color: var(--text-secondary);
  line-height: 1.6;
  margin: 0;
}

.highlight {
  color: var(--accent-primary);
  font-weight: 600;
}

.face-placeholder {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  font-size: 12px;
}
</style>
