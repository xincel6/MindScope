<script setup lang="ts">
import { useStatsStore } from '@/stores/stats'
import { severityColors } from '@/stores/dashboard'

const store = useStatsStore()

const labels: Record<string, string> = {
  none: '正常',
  mild: '轻度',
  moderate: '中度',
  severe: '重度',
}
</script>

<template>
  <div class="recent-reports glass-card">
    <div class="section-title">最近分析记录</div>

    <el-empty v-if="!store.data?.recent_reports?.length" description="暂无分析记录" :image-size="60" />

    <el-table
      v-else
      :data="store.data.recent_reports"
      size="small"
      class="reports-table"
      row-class-name="report-row"
    >
      <el-table-column prop="media_name" label="素材名称" min-width="140">
        <template #default="{ row }">
          <div class="media-cell">
            <el-icon :size="14">
              <VideoCamera v-if="row.media_type === 'video'" />
              <Picture v-else />
            </el-icon>
            <span class="media-name-text">{{ row.media_name }}</span>
          </div>
        </template>
      </el-table-column>
      <el-table-column prop="bdi_score" label="BDI评分" width="90" align="center">
        <template #default="{ row }">
          <span class="mono-num score-cell" :style="{ color: severityColors[row.severity] ?? '#94a3b8' }">
            {{ row.bdi_score.toFixed(1) }}
          </span>
        </template>
      </el-table-column>
      <el-table-column prop="severity" label="等级" width="80" align="center">
        <template #default="{ row }">
          <el-tag :color="severityColors[row.severity]" effect="light" size="small" round>
            {{ labels[row.severity] ?? row.severity }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="detected_at" label="时间" width="150">
        <template #default="{ row }">
          <span class="time-cell">{{ row.detected_at }}</span>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<style scoped>
.recent-reports {
  padding: 16px;
}

.reports-table {
  --el-table-bg-color: transparent;
  --el-table-tr-bg-color: transparent;
  --el-table-header-bg-color: rgba(148, 163, 184, 0.06);
  --el-table-border-color: var(--border-color);
  --el-table-header-text-color: var(--text-muted);
  --el-table-text-color: var(--text-secondary);
  --el-table-row-hover-bg-color: rgba(148, 163, 184, 0.04);
  font-size: 12px;
}

.reports-table :deep(.report-row) {
  cursor: default;
}

.media-cell {
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--text-secondary);
}

.media-name-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 120px;
}

.score-cell {
  font-weight: 600;
  font-size: 13px;
}

.time-cell {
  font-size: 11px;
  color: var(--text-muted);
}
</style>
