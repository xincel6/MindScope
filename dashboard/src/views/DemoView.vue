<script setup lang="ts">
/**
 * /demo —— 演示模式（唯一允许出现编造数据的地方）
 * ================================================================
 * 与主流程（`/`、`/analysis`）的关系：
 *   - 数据来源：`src/demo/demoData.ts`（纯函数，不碰 store）；
 *   - 注入点：本页把演示素材灌进 store、用 store.handleFrame 喂帧，
 *     因此下游组件（诊断报告 / 评分曲线 / 推理指标）**一行都不用改**；
 *   - 生命周期：`onBeforeUnmount` 会把 store 清干净，演示数据不会漏进主流程。
 *
 * 不挂载的组件及原因：
 *   - `MediaLibrary`：会自动拉真实列表、上传/删除会打到真实后端；
 *   - `MainVideoPlayer`：演示素材没有 url，只会渲染无 src 的 <video> 黑框，
 *     而且它是 WebSocket 的连接方（`analysisRunId`），演示不需要连后端；
 *   - `FaceFrameGallery` / `FacePreview`：演示帧不含对齐人脸，只会得到空态；
 *   - `AnalysisStatusBar`：它把 `analyzing` 显示成「连接中」，演示并未连接，会撒谎。
 */
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import PageHeader from '@/components/layout/PageHeader.vue'
import DiagnosisReport from '@/components/right-panel/DiagnosisReport.vue'
import EmotionCurve from '@/components/right-panel/EmotionCurve.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import DemoMediaList from '@/demo/DemoMediaList.vue'
import { useDashboardStore } from '@/stores/dashboard'
import type { MediaItem } from '@/api/index'
import { buildDemoMediaList, createDemoFrameStream } from '@/demo/demoData'
import type { DemoFrameStream } from '@/demo/demoData'

const router = useRouter()
const store = useDashboardStore()

const items = ref<MediaItem[]>([])
const selectedId = ref<string | null>(null)
const playing = ref(false)
let stream: DemoFrameStream | null = null

function stopStream() {
  stream?.stop()
  stream = null
  playing.value = false
}

function play(item: MediaItem) {
  stopStream()
  // 复用主流程的帧摄入路径：/demo 只替换「帧从哪来」，下游组件零改动
  store.reset()
  selectedId.value = item.id
  store.selectedMediaId = item.id
  store.analyzing = true
  playing.value = true
  stream = createDemoFrameStream({
    onFrame: (frame) => store.handleFrame(frame),
    onDone: () => {
      // 流放完就结束：否则诊断报告会一直显示「分析进度 100%」在跑
      playing.value = false
      store.analyzing = false
      stream = null
    },
  })
}

function replay() {
  const target = items.value.find((m) => m.id === selectedId.value) ?? items.value[0]
  if (target) play(target)
}

function exitDemo() {
  router.push('/workbench')
}

/** 演示数据只活在本页生命周期内：离开即清零，主流程拿不到任何假条目 */
function clearDemoState() {
  stopStream()
  store.mediaList = []
  store.selectedMediaId = null
  store.reset()
  items.value = []
  selectedId.value = null
}

onMounted(() => {
  const list = buildDemoMediaList()
  items.value = list
  store.mediaList = list
  store.mediaError = ''
  store.mediaLoading = false
  play(list[0])
})

onBeforeUnmount(clearDemoState)
</script>

<template>
  <div class="page-shell demo-page">
    <div class="demo-header">
      <PageHeader title="演示模式" subtitle="演示数据 · 非真实患者 · 仅用于展示界面" back @back="exitDemo" />
    </div>

    <!-- 常驻警示横幅：warning 底 / warning 描边 / 左侧 3px 条，正文用 AA 合规的 warning-text -->
    <div class="demo-banner" role="status">
      <span class="demo-banner-mark" aria-hidden="true">!</span>
      <div class="demo-banner-body">
        <p class="demo-banner-title">演示数据 · 非真实患者 · 仅用于展示界面</p>
        <p class="demo-banner-desc">
          本页的 BDI-II 分数、评分曲线与推理耗时全部由浏览器端随机生成，不经过模型推理，
          不可用于任何临床判断；离开本页后数据立即清空。
        </p>
      </div>
      <div class="demo-banner-actions">
        <button type="button" class="demo-action" @click="replay">重播演示</button>
        <button type="button" class="demo-action demo-action--primary" @click="exitDemo">
          退出演示
        </button>
      </div>
    </div>

    <main class="demo-body">
      <aside class="demo-side">
        <DemoMediaList
          :items="items"
          :selected-id="selectedId"
          :playing="playing"
          @select="play"
        />
      </aside>

      <section class="demo-center">
        <EmotionCurve class="demo-curve" />
        <div class="glass-card demo-note-card">
          <EmptyState
            icon="Aim"
            title="本页不展示人脸热力图"
            description="演示模式没有真实人脸帧，不合成假的注意力热力图。"
            hint="查看真实热力图：到「工作台」上传素材并连接后端。"
            compact
          />
        </div>
      </section>

      <aside class="demo-report">
        <div class="glass-card demo-report-card">
          <DiagnosisReport />
        </div>
      </aside>
    </main>
  </div>
</template>

<style scoped>
.demo-header {
  padding: var(--space-3) var(--page-padding) 0;
}

.demo-banner {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  flex-shrink: 0;
  margin: var(--content-gap) var(--content-gap) 0;
  padding: 10px 14px;
  background: var(--color-warning-soft);
  border: 1px solid var(--color-warning);
  border-left: 3px solid var(--color-warning);
  border-radius: var(--radius-control);
}

.demo-banner-mark {
  flex-shrink: 0;
  width: 18px;
  height: 18px;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-top: 1px;
  border-radius: var(--radius-pill);
  background: var(--color-warning-text);
  color: var(--bg-card);
  font-size: var(--font-xs);
  font-weight: 700;
  line-height: 1;
}

.demo-banner-body {
  flex: 1;
  min-width: 0;
}

.demo-banner-title {
  margin: 0;
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--color-warning-text);
}

.demo-banner-desc {
  margin: 2px 0 0;
  font-size: var(--font-xs);
  line-height: 1.55;
  color: var(--color-warning-text);
}

.demo-banner-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}

.demo-action {
  padding: 5px 12px;
  font-size: var(--font-xs);
  white-space: nowrap;
  background: transparent;
  color: var(--color-warning-text);
  border: 1px solid var(--color-warning);
  border-radius: var(--radius-control);
  cursor: pointer;
  transition: background var(--motion-press) ease;
}

.demo-action:hover {
  background: color-mix(in srgb, var(--color-warning) 12%, transparent);
}

.demo-action--primary {
  background: var(--color-warning-text);
  border-color: var(--color-warning-text);
  color: var(--bg-card);
}

.demo-action--primary:hover {
  background: var(--color-warning);
  border-color: var(--color-warning);
}

.demo-body {
  flex: 1;
  display: grid;
  grid-template-columns: 280px 1fr 400px;
  gap: var(--content-gap);
  padding: var(--content-gap);
  min-height: 0;
  overflow: hidden;
}

.demo-side,
.demo-report {
  min-height: 0;
  overflow: hidden;
}

.demo-report-card {
  height: 100%;
  padding: var(--space-3);
  overflow-y: auto;
}

.demo-center {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
  min-height: 0;
  min-width: 0;
  overflow: hidden;
}

.demo-curve {
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.demo-note-card {
  flex-shrink: 0;
  padding: 0;
  overflow: hidden;
}

@media (max-width: 1280px) {
  .demo-body {
    grid-template-columns: 230px 1fr 340px;
  }
}

@media (max-width: 1024px) {
  .demo-body {
    grid-template-columns: 1fr;
    grid-template-rows: auto 1fr auto;
    overflow-y: auto;
  }

  .demo-side {
    max-height: 220px;
  }

  .demo-center {
    min-height: 380px;
  }

  .demo-report {
    min-height: 480px;
  }
}
</style>
