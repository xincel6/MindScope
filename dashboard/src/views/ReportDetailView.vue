<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import PageHeader from '@/components/layout/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import ComparisonModal from '@/components/common/ComparisonModal.vue'
import {
  fetchMediaList,
  fetchReportDetail,
  fetchReports,
  type MediaItem,
  type ReportDetail,
  type ReportListItem,
} from '@/api/index'
import {
  getSeverity,
  severityLabels,
  severityTextColorOf,
} from '@/stores/dashboard'
import { buildTreatmentPlan, parseVlmSections } from '@/utils/clinicalContent'

const route = useRoute()
const router = useRouter()

const mediaId = computed(() => {
  const raw = route.params.mediaId
  return Array.isArray(raw) ? (raw[0] ?? '') : (raw ?? '')
})
const numericId = computed(() => Number(mediaId.value))
const validId = computed(() => Number.isInteger(numericId.value) && numericId.value > 0)

const reports = ref<ReportDetail[]>([])
const media = ref<MediaItem | null>(null)
const nameFromList = ref('')
const typeFromList = ref('')
const candidates = ref<ReportListItem[]>([])
const loading = ref(false)
const error = ref('')
const compareTargetId = ref<number | null>(null)
const comparisonVisible = ref(false)

const latest = computed<ReportDetail | null>(() => reports.value[0] ?? null)
const severity = computed(() => (latest.value ? getSeverity(latest.value.bdi_score) : 'none'))
const severityLabel = computed(() => severityLabels[severity.value])
const severityColor = computed(() =>
  latest.value ? severityTextColorOf(latest.value.severity) : 'var(--text-secondary)',
)
const mediaName = computed(
  () => media.value?.name || nameFromList.value || `素材 #${numericId.value}`,
)
const mediaType = computed(() => media.value?.type || typeFromList.value || 'image')
const plan = computed(() =>
  latest.value ? buildTreatmentPlan(getSeverity(latest.value.bdi_score)) : null,
)

/**
 * `GET /api/report/{media_id}` 的 ReportOut 只有评分、等级、检测时间和推理耗时；
 * VLM 原文只在分析 WebSocket 会话中发送，从未写入报告表。这里保留
 * parseVlmSections 的解析入口：后端将来若在 ReportOut 增加原文，把字段接进
 * storedVlmRaw 即可，渲染逻辑不用重写。
 */
const storedVlmRaw = computed(() => '')
const vlmSections = computed(() => parseVlmSections(storedVlmRaw.value))

const comparableReports = computed(() =>
  [...candidates.value].sort((a, b) => {
    const aSame = a.media_id === numericId.value ? 1 : 0
    const bSame = b.media_id === numericId.value ? 1 : 0
    return bSame - aSame
  }),
)

const compareTarget = computed(
  () => candidates.value.find((item) => item.id === compareTargetId.value) ?? null,
)

const currentAsListItem = computed<ReportListItem | null>(() => {
  if (!latest.value) return null
  return {
    id: latest.value.id,
    media_id: latest.value.media_id,
    media_name: mediaName.value,
    media_type: mediaType.value,
    bdi_score: latest.value.bdi_score,
    severity: latest.value.severity,
    detected_at: latest.value.detected_at,
    inference_time_ms: latest.value.inference_time_ms,
  }
})

function formatDateTime(raw: string): string {
  return raw.replace('T', ' ').slice(0, 16)
}

function resetState() {
  reports.value = []
  media.value = null
  nameFromList.value = ''
  typeFromList.value = ''
  candidates.value = []
  error.value = ''
  compareTargetId.value = null
  comparisonVisible.value = false
}

async function load() {
  if (!validId.value) {
    resetState()
    loading.value = false
    return
  }
  loading.value = true
  resetState()

  const [detailResult, mediaResult, listResult] = await Promise.allSettled([
    fetchReportDetail(numericId.value),
    fetchMediaList(),
    fetchReports({ limit: 100 }),
  ])

  if (detailResult.status === 'rejected') {
    error.value =
      detailResult.reason instanceof Error ? detailResult.reason.message : '加载报告详情失败'
    loading.value = false
    return
  }

  reports.value = detailResult.value

  if (mediaResult.status === 'fulfilled') {
    media.value =
      mediaResult.value.find((item) => Number(item.id) === numericId.value) ?? null
  }

  if (listResult.status === 'fulfilled') {
    const own = listResult.value.items.find((item) => item.media_id === numericId.value)
    nameFromList.value = own?.media_name ?? ''
    typeFromList.value = own?.media_type ?? ''
    // 只排除当前这一份报告；同一素材的其他评估也可以作为对比对象。
    candidates.value = listResult.value.items.filter(
      (item) => item.id !== latest.value?.id,
    )
    const sameMediaFirst = candidates.value.find(
      (item) => item.media_id === numericId.value,
    )
    compareTargetId.value = (sameMediaFirst ?? candidates.value[0])?.id ?? null
  }

  loading.value = false
}

function openComparison() {
  if (!currentAsListItem.value || !compareTarget.value) return
  comparisonVisible.value = true
}

watch(
  numericId,
  () => {
    void load()
  },
  { immediate: true },
)
</script>

<template>
  <div class="app-page report-detail-page">
    <PageHeader
      title="报告详情"
      :subtitle="validId ? `${mediaName} · ${reports.length || '—'} 次评估` : '素材编号无效'"
      back
      @back="router.push('/reports')"
    >
      <template #actions>
        <el-button v-if="validId" :loading="loading" plain @click="load">刷新</el-button>
      </template>
    </PageHeader>

    <EmptyState
      v-if="!validId"
      icon="WarningFilled"
      title="报告不存在"
      description="URL 中的素材编号必须是正整数，例如 /reports/42。"
      hint="未向服务端发送请求"
      action-label="返回历史报告"
      @action="router.push('/reports')"
    />

    <div v-else-if="loading" class="report-loading glass-card">
      <el-skeleton :rows="8" animated />
    </div>

    <EmptyState
      v-else-if="error"
      icon="WarningFilled"
      title="报告加载失败"
      :description="error"
      hint="请确认后端服务可达后重试"
      action-label="重新加载"
      @action="load"
    />

    <EmptyState
      v-else-if="!latest"
      icon="Document"
      title="暂无该素材的报告"
      description="该素材尚未完成评估，或分析结果没有落库。"
      hint="报告接口返回空数组"
      action-label="返回历史报告"
      @action="router.push('/reports')"
    />

    <template v-else>
      <section class="report-summary glass-card">
        <div class="summary-main">
          <div class="summary-heading">
            <span class="summary-type" aria-hidden="true">
              <el-icon>
                <VideoCamera v-if="mediaType === 'video'" />
                <Picture v-else />
              </el-icon>
            </span>
            <div class="summary-title-group">
              <h2 class="summary-name">{{ mediaName }}</h2>
              <p class="summary-meta">
                {{ formatDateTime(latest.detected_at) }} · 推理耗时
                {{ latest.inference_time_ms.toFixed(1) }} ms
              </p>
            </div>
          </div>
          <div class="summary-score">
            <strong class="summary-score-value mono-num" :style="{ color: severityColor }">
              {{ latest.bdi_score.toFixed(1) }}
            </strong>
            <span class="summary-score-max">/ 63</span>
            <el-tag effect="light" round :class="`sev-${latest.severity}`">
              {{ severityLabel }}
            </el-tag>
          </div>
        </div>
        <p v-if="reports.length > 1" class="summary-note">
          该素材共有 {{ reports.length }} 次评估，本页展示最近一次（报告 #{{ latest.id }}）。
        </p>
        <p v-if="latest.notes" class="summary-note">报告备注：{{ latest.notes }}</p>
      </section>

      <div class="detail-grid">
        <section class="detail-section glass-card">
          <header class="detail-head">
            <h2 class="section-title">逐帧热力图</h2>
            <span class="detail-sub">注意力分布</span>
          </header>
          <div class="detail-empty">
            <EmptyState
              compact
              icon="Picture"
              title="暂无逐帧热力图"
              description="报告存储只保留 BDI 评分、严重度与推理耗时，没有保存逐帧热力图。单次分析的热力图可在工作台查看。"
              hint="GET /api/report/{media_id} 不返回帧数据"
            />
          </div>
        </section>

        <section class="detail-section glass-card">
          <header class="detail-head">
            <h2 class="section-title">智能解读</h2>
            <span class="detail-sub">模型文本 · 需医师复核</span>
          </header>
          <div v-if="vlmSections.length" class="detail-body">
            <section
              v-for="section in vlmSections"
              :key="section.title"
              class="vlm-section"
            >
              <h3 class="detail-item-title">{{ section.title }}</h3>
              <p class="detail-text">{{ section.content }}</p>
            </section>
          </div>
          <div v-else class="detail-empty">
            <EmptyState
              compact
              icon="ChatLineSquare"
              title="报告未保存智能解读"
              description="智能解读只在分析会话中生成，没有写入报告存储，因此历史报告无法回放当时的模型原文。"
              hint="分析会话中的文本不落库"
            />
          </div>
        </section>
      </div>

      <section v-if="plan" class="detail-section glass-card">
        <header class="detail-head">
          <h2 class="section-title">处置建议</h2>
          <span class="detail-sub">按 BDI-II 严重度分档生成</span>
        </header>
        <div class="plan-grid">
          <div class="plan-block">
            <h3 class="detail-item-title">干预方向</h3>
            <ul class="plan-list">
              <li v-for="item in plan.interventions" :key="item">{{ item }}</li>
            </ul>
          </div>
          <div class="plan-block">
            <h3 class="detail-item-title">随访监测</h3>
            <p class="detail-text">{{ plan.monitoring }}</p>
            <h3 class="detail-item-title plan-guideline-title">指南依据</h3>
            <p class="detail-text">{{ plan.guidelines }}</p>
          </div>
        </div>
        <p class="plan-note">
          以上内容依据 BDI-II 严重度分档生成，仅供参考，不构成诊断结论，也不能替代医师面诊。
        </p>
      </section>

      <section class="detail-section glass-card">
        <header class="detail-head">
          <h2 class="section-title">与另一次评估对比</h2>
          <span class="detail-sub">当前报告作为报告 A</span>
        </header>
        <div v-if="comparableReports.length" class="compare-row">
          <el-select
            v-model="compareTargetId"
            class="compare-select"
            placeholder="选择另一条报告"
            aria-label="选择用于对比的报告"
          >
            <el-option
              v-for="item in comparableReports"
              :key="item.id"
              :value="item.id"
              :label="`${item.media_name} · ${formatDateTime(item.detected_at)} · ${item.bdi_score.toFixed(0)} 分`"
            />
          </el-select>
          <el-button type="primary" :disabled="!compareTarget" @click="openComparison">
            开始对比
          </el-button>
        </div>
        <p v-else class="compare-hint">
          暂无可对比的其他评估记录。完成第二次分析后，这里会出现对比入口。
        </p>
      </section>

      <ComparisonModal
        v-model:visible="comparisonVisible"
        :report-a="currentAsListItem"
        :report-b="compareTarget"
      />
    </template>
  </div>
</template>

<style scoped>
.report-detail-page {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
}

.report-loading {
  padding: var(--space-4);
}

.report-summary {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  padding: var(--space-4);
}

.summary-main {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-3);
  flex-wrap: wrap;
}

.summary-heading {
  display: flex;
  align-items: flex-start;
  gap: var(--space-2);
  min-width: 0;
}

.summary-type {
  flex: 0 0 auto;
  width: 40px;
  height: 40px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--radius-control);
  background: var(--bg-inset);
  color: var(--text-secondary);
}

.summary-title-group {
  min-width: 0;
}

.summary-name {
  margin: 0;
  font-size: var(--font-base);
  font-weight: 600;
  color: var(--text-primary);
  overflow-wrap: anywhere;
}

.summary-meta {
  margin: var(--space-1) 0 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.summary-score {
  display: flex;
  align-items: baseline;
  gap: var(--space-1);
  flex-wrap: wrap;
}

.summary-score-value {
  font-size: var(--font-metric);
  line-height: 1;
}

.summary-score-max {
  font-size: var(--font-sm);
  color: var(--text-secondary);
}

.summary-note {
  margin: 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.detail-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: var(--content-gap);
}

.detail-section {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  min-width: 0;
}

.detail-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-2);
}

.detail-head .section-title {
  margin-bottom: 0;
}

.detail-sub {
  flex-shrink: 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.detail-empty {
  min-height: 180px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.detail-body {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.detail-item-title {
  margin: 0 0 var(--space-1);
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.detail-text {
  margin: 0;
  font-size: var(--font-xs);
  line-height: 1.7;
  color: var(--text-secondary);
}

.plan-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: var(--space-4);
}

.plan-block {
  min-width: 0;
}

.plan-list {
  margin: 0;
  padding-left: var(--space-4);
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  font-size: var(--font-xs);
  line-height: 1.7;
  color: var(--text-secondary);
}

.plan-guideline-title {
  margin-top: var(--space-3);
}

.plan-note {
  margin: 0;
  padding: var(--space-2) var(--space-3);
  background: var(--bg-inset);
  border-radius: var(--radius-tag);
  font-size: var(--font-xs);
  line-height: 1.6;
  color: var(--text-secondary);
}

.compare-row {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  flex-wrap: wrap;
}

.compare-select {
  flex: 1;
  min-width: 0;
  max-width: 100%;
}

/* 长素材名不能撑破下拉框：Element Plus 的选中项默认不省略，这里补上。 */
.compare-select :deep(.el-select__selection),
.compare-select :deep(.el-select__selected-item),
.compare-select :deep(.el-select__placeholder) {
  min-width: 0;
}

.compare-select :deep(.el-select__selected-item) {
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Element Plus 的选中文本是 placeholder 里的裸 span，需单独限宽才能真正省略 */
.compare-select :deep(.el-select__placeholder > span) {
  display: block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.compare-hint {
  margin: 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

@media (max-width: 1023px) {
  .detail-grid,
  .plan-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .summary-main {
    flex-direction: column;
  }

  .compare-select {
    width: 100%;
    min-width: 0;
  }
}
</style>
