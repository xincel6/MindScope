<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { fetchReports, type ReportListItem } from '@/api/index'
import { severityTextColorOf } from '@/stores/dashboard'
import ComparisonModal from '@/components/common/ComparisonModal.vue'
import EmptyState from '@/components/common/EmptyState.vue'

const router = useRouter()

const PAGE_SIZE = 10
const reports = ref<ReportListItem[]>([])
const total = ref(0)
const nextPage = ref(1)
const loading = ref(false)
const loadingAll = ref(false)
const error = ref('')
const severity = ref('')
const mediaType = ref('')
const keyword = ref('')
const selectedReports = ref<ReportListItem[]>([])
const comparisonVisible = ref(false)

let reloadToken = 0
let keywordTimer: ReturnType<typeof setTimeout> | null = null

// ── 表格行键盘可达（P5 T3）─────────────────────────────────────────
// el-table 的行是 <tr>，@row-click 只服务鼠标。这里在每次渲染后给行补
// tabindex/role/aria-label，并用事件委托处理 Enter / Space，行内复选框不受影响。
const tableWrap = ref<HTMLElement | null>(null)

function syncTableRows() {
  const rows = tableWrap.value?.querySelectorAll<HTMLElement>('tbody tr.el-table__row')
  if (!rows) return
  rows.forEach((row, index) => {
    const report = filteredReports.value[index]
    if (!report) return
    row.tabIndex = 0
    row.setAttribute('role', 'button')
    row.setAttribute('aria-label', `查看报告：${report.media_name}`)
  })
}

function onTableKeydown(event: KeyboardEvent) {
  if (event.key !== 'Enter' && event.key !== ' ') return
  const target = event.target as HTMLElement | null
  const row = target?.closest<HTMLElement>('tr.el-table__row')
  if (!row || target !== row) return // 焦点在行内复选框/按钮时不抢事件
  event.preventDefault()
  const rows = Array.from(
    tableWrap.value?.querySelectorAll<HTMLElement>('tbody tr.el-table__row') ?? [],
  )
  const report = filteredReports.value[rows.indexOf(row)]
  if (report) openDetail(report)
}

const labels: Record<string, string> = {
  none: '正常',
  mild: '轻度',
  moderate: '中度',
  severe: '重度',
}

const severityOptions = [
  { value: '', label: '全部' },
  { value: 'none', label: '正常' },
  { value: 'mild', label: '轻度' },
  { value: 'moderate', label: '中度' },
  { value: 'severe', label: '重度' },
]

const typeOptions = [
  { value: '', label: '全部' },
  { value: 'video', label: '视频' },
  { value: 'image', label: '图片' },
]

const canCompare = computed(() => selectedReports.value.length === 2)
const filtersActive = computed(
  () => !!severity.value || !!mediaType.value || !!keyword.value.trim(),
)
const searchingAll = computed(
  () => !!keyword.value.trim() && reports.value.length < total.value,
)

const filteredReports = computed(() => {
  const kw = keyword.value.trim().toLowerCase()
  if (!kw) return reports.value
  return reports.value.filter((row) => row.media_name.toLowerCase().includes(kw))
})

// 表格行渲染后补键盘语义（el-table 不提供 row 级 attrs）。
watch(
  filteredReports,
  () => {
    void nextTick(syncTableRows)
  },
  { flush: 'post' },
)

const countText = computed(() => {
  const kw = keyword.value.trim()
  if (kw) {
    const suffix = searchingAll.value ? ' · 正在检索全部记录' : ''
    return `筛选命中 ${filteredReports.value.length} 条 · 关键字「${kw}」${suffix}`
  }
  if (severity.value || mediaType.value) {
    return `筛选命中 ${total.value} 条 · 已加载 ${reports.value.length} 条`
  }
  return `共 ${total.value} 条 · 已加载 ${reports.value.length} 条`
})

const emptyTitle = computed(() =>
  filtersActive.value ? '没有匹配的报告' : '暂无分析记录',
)
const emptyDescription = computed(() =>
  filtersActive.value
    ? '当前筛选条件下没有记录，可清除筛选查看全部报告。'
    : '完成第一次分析后，报告会出现在这里，可勾选两条做对比。',
)
const emptyAction = computed(() => (filtersActive.value ? '清除筛选' : ''))

function formatTime(raw: string): string {
  const normalized = raw.replace('T', ' ')
  return normalized.length >= 16 ? normalized.slice(5, 16) : normalized
}

function isSelected(row: ReportListItem): boolean {
  return selectedReports.value.some((item) => item.id === row.id)
}

function selectionDisabled(row: ReportListItem): boolean {
  return !isSelected(row) && selectedReports.value.length >= 2
}

function toggleSelection(row: ReportListItem) {
  const index = selectedReports.value.findIndex((item) => item.id === row.id)
  if (index >= 0) {
    selectedReports.value.splice(index, 1)
  } else if (selectedReports.value.length < 2) {
    selectedReports.value.push(row)
  }
}

function clearSelection() {
  selectedReports.value = []
}

function openComparison() {
  if (selectedReports.value.length !== 2) return
  comparisonVisible.value = true
}

function openDetail(row: ReportListItem) {
  void router.push(`/reports/${row.media_id}`)
}

async function loadPage(reset: boolean): Promise<void> {
  const token = reloadToken
  loading.value = true
  try {
    const result = await fetchReports({
      severity: severity.value || undefined,
      media_type: mediaType.value || undefined,
      page: reset ? 1 : nextPage.value,
      limit: PAGE_SIZE,
    })
    if (token !== reloadToken) return
    reports.value = reset ? result.items : [...reports.value, ...result.items]
    total.value = result.total
    nextPage.value = (reset ? 1 : nextPage.value) + 1
    error.value = ''
  } catch (e: unknown) {
    if (token === reloadToken) {
      error.value = e instanceof Error ? e.message : '加载报告失败'
    }
  } finally {
    if (token === reloadToken) loading.value = false
  }
}

async function reload(): Promise<void> {
  reloadToken += 1
  nextPage.value = 1
  reports.value = []
  total.value = 0
  error.value = ''
  loadingAll.value = false
  clearSelection()
  await loadPage(true)
  if (keyword.value.trim() && reports.value.length < total.value) {
    void ensureAllLoaded()
  }
}

async function loadMore() {
  if (loading.value || searchingAll.value) return
  if (keyword.value.trim()) {
    await ensureAllLoaded()
    return
  }
  await loadPage(false)
}

/**
 * 后端 `/api/reports` 没有关键字参数（只有 severity / media_type / page / limit），
 * 所以关键字只能在已加载的数据里过滤。为保证不漏记录，输入关键字后把剩余分页拉全；
 * 命中数只统计真实拉到的记录，不会用 total 冒充命中数。
 */
async function ensureAllLoaded(): Promise<void> {
  if (!keyword.value.trim()) return
  if (reports.value.length >= total.value) return
  if (loading.value || loadingAll.value) {
    scheduleSearch()
    return
  }
  const token = reloadToken
  loadingAll.value = true
  try {
    // 分页是按 offset 计算的，不能用「先 page=1&limit=10，再 page=2&limit=100」拼接，
    // 那样会跳过第 11–100 条；检索时统一从 page=1、limit=100 重新拉全量。
    const collected: ReportListItem[] = []
    let page = 1
    let fetchedTotal = 0
    while (page <= 50) {
      const result = await fetchReports({
        severity: severity.value || undefined,
        media_type: mediaType.value || undefined,
        page,
        limit: 100,
      })
      if (token !== reloadToken) return
      collected.push(...result.items)
      fetchedTotal = result.total
      if (!result.items.length || collected.length >= fetchedTotal) break
      page += 1
    }
    reports.value = collected
    total.value = fetchedTotal
    nextPage.value = Math.floor(collected.length / PAGE_SIZE) + 1
    error.value = ''
  } catch (e: unknown) {
    if (token === reloadToken) {
      error.value = e instanceof Error ? e.message : '检索报告失败'
    }
  } finally {
    if (token === reloadToken) loadingAll.value = false
  }
}

function scheduleSearch() {
  if (keywordTimer) clearTimeout(keywordTimer)
  keywordTimer = setTimeout(() => {
    void ensureAllLoaded()
  }, 300)
}

function onKeywordInput() {
  if (!keyword.value.trim()) return
  scheduleSearch()
}

function setSeverity(value: string) {
  if (severity.value === value) return
  severity.value = value
  void reload()
}

function setMediaType(value: string) {
  if (mediaType.value === value) return
  mediaType.value = value
  void reload()
}

function clearFilters() {
  severity.value = ''
  mediaType.value = ''
  keyword.value = ''
  void reload()
}

function retry() {
  if (reports.value.length) {
    void loadPage(false)
  } else {
    void reload()
  }
}

onMounted(() => {
  void reload()
})

onBeforeUnmount(() => {
  if (keywordTimer) clearTimeout(keywordTimer)
})

defineExpose({ reload })
</script>

<template>
  <div class="history-panel">
    <div class="section-title">历史分析记录</div>

    <div class="history-filters">
      <div class="filter-row">
        <span class="filter-label">严重度</span>
        <div class="chip-group" role="group" aria-label="按严重度筛选">
          <button
            v-for="option in severityOptions"
            :key="option.value || 'all'"
            type="button"
            class="filter-chip"
            :class="{ active: severity === option.value }"
            :aria-pressed="severity === option.value"
            @click="setSeverity(option.value)"
          >
            {{ option.label }}
          </button>
        </div>
      </div>
      <div class="filter-row">
        <span class="filter-label">素材</span>
        <div class="chip-group" role="group" aria-label="按素材类型筛选">
          <button
            v-for="option in typeOptions"
            :key="option.value || 'all'"
            type="button"
            class="filter-chip"
            :class="{ active: mediaType === option.value }"
            :aria-pressed="mediaType === option.value"
            @click="setMediaType(option.value)"
          >
            {{ option.label }}
          </button>
        </div>
      </div>
      <div class="search-row">
        <el-input
          v-model="keyword"
          class="history-search"
          placeholder="搜索图片或视频名称"
          maxlength="64"
          clearable
          aria-label="搜索报告素材名称"
          @input="onKeywordInput"
          @clear="onKeywordInput"
        >
          <template #prefix>
            <el-icon><Search /></el-icon>
          </template>
        </el-input>
        <el-button v-if="filtersActive" text type="primary" @click="clearFilters">
          清除筛选
        </el-button>
      </div>
    </div>

    <el-skeleton v-if="loading && !reports.length" :rows="6" animated />

    <EmptyState
      v-else-if="error && !reports.length"
      icon="WarningFilled"
      title="报告加载失败"
      :description="error"
      hint="请检查后端服务是否可达后重试"
      action-label="重新加载"
      @action="retry"
    />

    <EmptyState
      v-else-if="!filteredReports.length && !searchingAll"
      icon="FolderOpened"
      :title="emptyTitle"
      :description="emptyDescription"
      :action-label="emptyAction || undefined"
      @action="clearFilters"
    />

    <template v-else>
      <div v-if="error" class="history-error" role="alert">
        {{ error }}
        <el-button text type="primary" size="small" @click="retry">重试</el-button>
      </div>

      <div class="history-toolbar">
        <span class="history-count">{{ countText }}</span>
        <div class="toolbar-actions">
          <span v-if="selectedReports.length" class="selected-hint">
            已选 {{ selectedReports.length }}/2
          </span>
          <el-button
            size="small"
            round
            :disabled="!canCompare"
            class="compare-btn"
            @click="openComparison"
          >
            <el-icon><Switch /></el-icon>
            对比分析
          </el-button>
        </div>
      </div>

      <div ref="tableWrap" class="table-wrap" @keydown="onTableKeydown">
        <el-table
          :data="filteredReports"
          size="small"
          class="history-table"
          row-class-name="history-row"
          @row-click="openDetail"
        >
          <el-table-column width="36" align="center">
            <template #default="{ row }">
              <el-checkbox
                :model-value="isSelected(row)"
                :disabled="selectionDisabled(row)"
                :aria-label="`选择 ${row.media_name} 用于对比`"
                @click.stop
                @change="toggleSelection(row)"
              />
            </template>
          </el-table-column>
          <el-table-column prop="media_name" label="素材" min-width="120">
            <template #default="{ row }">
              <span class="media-cell">
                <el-icon class="media-type-icon">
                  <VideoCamera v-if="row.media_type === 'video'" />
                  <Picture v-else />
                </el-icon>
                <span class="media-name-cell" :title="row.media_name">{{ row.media_name }}</span>
              </span>
            </template>
          </el-table-column>
          <el-table-column prop="bdi_score" label="BDI" width="60" align="center">
            <template #default="{ row }">
              <span class="mono-num" :style="{ color: severityTextColorOf(row.severity) }">
                {{ row.bdi_score.toFixed(0) }}
              </span>
            </template>
          </el-table-column>
          <el-table-column prop="severity" label="等级" width="68" align="center">
            <template #default="{ row }">
              <el-tag effect="light" size="small" round :class="`sev-${row.severity}`">
                {{ labels[row.severity] ?? row.severity }}
              </el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="detected_at" label="时间" width="110">
            <template #default="{ row }">
              <span class="time-cell">{{ formatTime(row.detected_at) }}</span>
            </template>
          </el-table-column>
          <el-table-column width="28" align="center">
            <template #default>
              <el-icon class="row-arrow"><ArrowRight /></el-icon>
            </template>
          </el-table-column>
        </el-table>
      </div>

      <ul class="report-cards" aria-label="历史报告列表">
        <li v-for="row in filteredReports" :key="row.id" class="report-card">
          <el-checkbox
            class="card-check"
            :model-value="isSelected(row)"
            :disabled="selectionDisabled(row)"
            :aria-label="`选择 ${row.media_name} 用于对比`"
            @change="toggleSelection(row)"
          />
          <button type="button" class="card-main" @click="openDetail(row)">
            <span class="card-name-line">
              <el-icon class="media-type-icon">
                <VideoCamera v-if="row.media_type === 'video'" />
                <Picture v-else />
              </el-icon>
              <span class="card-name" :title="row.media_name">{{ row.media_name }}</span>
            </span>
            <span class="card-meta">
              <span
                class="card-score mono-num"
                :style="{ color: severityTextColorOf(row.severity) }"
              >
                {{ row.bdi_score.toFixed(0) }}
              </span>
              <el-tag effect="light" size="small" round :class="`sev-${row.severity}`">
                {{ labels[row.severity] ?? row.severity }}
              </el-tag>
              <span class="card-time">{{ formatTime(row.detected_at) }}</span>
            </span>
          </button>
          <el-icon class="card-arrow"><ArrowRight /></el-icon>
        </li>
      </ul>

      <div v-if="searchingAll || loadingAll" class="history-loading">
        <el-skeleton :rows="2" animated />
      </div>

      <div v-if="!searchingAll && reports.length < total" class="load-more">
        <el-button :loading="loading" plain @click="loadMore">
          加载更多（{{ reports.length }}/{{ total }}）
        </el-button>
      </div>
    </template>

    <ComparisonModal
      v-model:visible="comparisonVisible"
      :report-a="selectedReports[0] ?? null"
      :report-b="selectedReports[1] ?? null"
    />
  </div>
</template>

<style scoped>
.history-panel {
  display: flex;
  flex-direction: column;
}

.history-filters {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  padding: var(--space-3);
  margin-bottom: var(--space-3);
  background: var(--bg-inset);
  border-radius: var(--radius-control);
}

.filter-row {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  flex-wrap: wrap;
}

.filter-label {
  flex: 0 0 auto;
  min-width: 42px;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.chip-group {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  flex-wrap: wrap;
}

.filter-chip {
  min-height: 32px;
  padding: 4px 12px;
  border: 1px solid var(--border);
  border-radius: var(--radius-pill);
  background: var(--bg-card);
  color: var(--text-secondary);
  font-size: var(--font-xs);
  line-height: 1.2;
  cursor: pointer;
}

.filter-chip:hover {
  color: var(--text-primary);
}

.filter-chip.active {
  border-color: var(--color-primary);
  background: var(--bg-press);
  color: var(--color-primary-text);
  font-weight: 600;
}

.filter-chip:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
}

.search-row {
  display: flex;
  align-items: center;
  gap: var(--space-2);
}

.history-search {
  flex: 1;
  min-width: 0;
  max-width: 420px;
}

.history-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  margin-bottom: 8px;
  flex-wrap: wrap;
}

.history-count {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.toolbar-actions {
  display: flex;
  align-items: center;
  gap: var(--space-2);
}

.selected-hint {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.compare-btn {
  font-size: var(--font-xs);
}

.history-error {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-3);
  margin-bottom: var(--space-2);
  background: var(--color-danger-soft);
  color: var(--color-danger);
  border-radius: var(--radius-tag);
  font-size: var(--font-xs);
}

.history-table {
  --el-table-bg-color: transparent;
  --el-table-tr-bg-color: transparent;
  --el-table-header-bg-color: var(--bg-inset);
  --el-table-border-color: var(--border);
  --el-table-header-text-color: var(--text-secondary);
  --el-table-text-color: var(--text-secondary);
  --el-table-row-hover-bg-color: var(--bg-press);
  font-size: var(--font-xs);
  width: 100%;
}

.history-table :deep(.history-row) {
  cursor: pointer;
}

/* 表格行用内偏移焦点环，避免被表格 overflow 裁掉 */
.history-table :deep(.history-row:focus-visible) {
  outline: 2px solid var(--color-primary-text);
  outline-offset: -2px;
}

.media-cell {
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  max-width: 100%;
  min-width: 0;
}

.media-type-icon {
  flex: 0 0 auto;
  color: var(--text-secondary);
}

.media-name-cell {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  min-width: 0;
}

.time-cell {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.row-arrow {
  color: var(--text-secondary);
}

.report-cards {
  display: none;
  list-style: none;
  margin: 0;
  padding: 0;
  flex-direction: column;
  gap: var(--space-2);
}

.report-card {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-height: 64px;
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--border);
  border-radius: var(--radius-tag);
  background: var(--bg-card);
}

.card-check {
  flex: 0 0 auto;
}

.card-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  align-items: flex-start;
  padding: 0;
  border: none;
  background: transparent;
  text-align: left;
  color: inherit;
  cursor: pointer;
}

.card-main:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
  border-radius: var(--radius-tag);
}

.card-name-line {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  max-width: 100%;
  min-width: 0;
}

.card-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.card-meta {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  flex-wrap: wrap;
}

.card-score {
  font-size: var(--font-sm);
  font-weight: 700;
}

.card-time {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.card-arrow {
  flex: 0 0 auto;
  color: var(--text-secondary);
}

.history-loading {
  padding: var(--space-2) 0;
}

.load-more {
  display: flex;
  justify-content: center;
  padding-top: var(--space-3);
}

@media (max-width: 767px) {
  .history-filters {
    padding: var(--space-2);
  }

  .filter-label {
    min-width: 100%;
  }

  .filter-chip {
    min-height: 36px;
    padding: 6px 14px;
  }

  .search-row {
    flex-wrap: wrap;
  }

  .history-search {
    max-width: none;
  }

  .table-wrap {
    display: none;
  }

  .report-cards {
    display: flex;
  }

  .history-toolbar {
    align-items: flex-start;
  }
}
</style>
