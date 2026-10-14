<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { fetchReports, type ReportListItem } from '@/api/index'
import { severityColors } from '@/stores/dashboard'
import ComparisonModal from '@/components/common/ComparisonModal.vue'

const reports = ref<ReportListItem[]>([])
const loading = ref(false)
const total = ref(0)
const selectedIds = ref<number[]>([])
const comparisonVisible = ref(false)
const comparingA = ref<ReportListItem | null>(null)
const comparingB = ref<ReportListItem | null>(null)

const labels: Record<string, string> = {
  none: '正常',
  mild: '轻度',
  moderate: '中度',
  severe: '重度',
}

const canCompare = computed(() => selectedIds.value.length === 2)

function toggleSelection(id: number) {
  const idx = selectedIds.value.indexOf(id)
  if (idx >= 0) {
    selectedIds.value.splice(idx, 1)
  } else if (selectedIds.value.length < 2) {
    selectedIds.value.push(id)
  }
}

function openComparison() {
  if (selectedIds.value.length !== 2) return
  comparingA.value = reports.value.find((r) => r.id === selectedIds.value[0]) ?? null
  comparingB.value = reports.value.find((r) => r.id === selectedIds.value[1]) ?? null
  comparisonVisible.value = true
}

async function load() {
  loading.value = true
  try {
    const result = await fetchReports({ limit: 100 })
    reports.value = result.items
    total.value = result.total
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="history-panel">
    <div class="section-title">历史分析记录</div>

    <el-skeleton v-if="loading" :rows="6" animated />

    <el-empty v-else-if="!reports.length" description="暂无分析记录" :image-size="60" />

    <template v-else>
      <div class="history-toolbar">
        <span class="history-count">共 {{ total }} 条</span>
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

      <el-table
        :data="reports"
        size="small"
        class="history-table"
        row-class-name="history-row"
        @row-click="({ id }: ReportListItem) => toggleSelection(id)"
      >
        <el-table-column width="36" align="center">
          <template #default="{ row }">
            <el-checkbox
              :model-value="selectedIds.includes(row.id)"
              :disabled="!selectedIds.includes(row.id) && selectedIds.length >= 2"
              @click.stop
              @change="toggleSelection(row.id)"
            />
          </template>
        </el-table-column>
        <el-table-column prop="media_name" label="素材" min-width="100">
          <template #default="{ row }">
            <span class="media-name-cell">{{ row.media_name }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="bdi_score" label="BDI" width="60" align="center">
          <template #default="{ row }">
            <span class="mono-num" :style="{ color: severityColors[row.severity] ?? '#94a3b8' }">
              {{ row.bdi_score.toFixed(0) }}
            </span>
          </template>
        </el-table-column>
        <el-table-column prop="severity" label="等级" width="68" align="center">
          <template #default="{ row }">
            <el-tag :color="severityColors[row.severity]" effect="light" size="small" round>
              {{ labels[row.severity] ?? row.severity }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="detected_at" label="时间" width="110">
          <template #default="{ row }">
            <span class="time-cell">{{ row.detected_at.slice(5) }}</span>
          </template>
        </el-table-column>
      </el-table>
    </template>

    <ComparisonModal
      v-model:visible="comparisonVisible"
      :report-a="comparingA"
      :report-b="comparingB"
    />
  </div>
</template>

<style scoped>
.history-panel {
  display: flex;
  flex-direction: column;
}

.history-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}

.history-count {
  font-size: 11px;
  color: var(--text-muted);
}

.compare-btn {
  font-size: 11px;
}

.history-table {
  --el-table-bg-color: transparent;
  --el-table-tr-bg-color: transparent;
  --el-table-header-bg-color: rgba(148, 163, 184, 0.06);
  --el-table-border-color: var(--border-color);
  --el-table-header-text-color: var(--text-muted);
  --el-table-text-color: var(--text-secondary);
  --el-table-row-hover-bg-color: rgba(148, 163, 184, 0.04);
  font-size: 11px;
}

.history-table :deep(.history-row) {
  cursor: pointer;
}

.media-name-cell {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100px;
  display: inline-block;
}

.time-cell {
  font-size: 10px;
  color: var(--text-muted);
  font-family: var(--font-mono);
}
</style>
