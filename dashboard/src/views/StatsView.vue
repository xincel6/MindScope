<script setup lang="ts">
import { onMounted, computed } from 'vue'
import DashboardHeader from '@/components/layout/DashboardHeader.vue'
import StatCard from '@/components/stats/StatCard.vue'
import ModelMetricsCard from '@/components/stats/ModelMetricsCard.vue'
import SeverityPieChart from '@/components/stats/SeverityPieChart.vue'
import BdiTrendChart from '@/components/stats/BdiTrendChart.vue'
import RecentReportsTable from '@/components/stats/RecentReportsTable.vue'
import { useStatsStore } from '@/stores/stats'
import { severityColors } from '@/stores/dashboard'

const store = useStatsStore()

onMounted(() => { store.load() })

const today = computed(() =>
  new Date().toLocaleDateString('zh-CN', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'long' }),
)

function severePct(): string {
  if (!store.data?.total_analyses) return '--'
  const sev = store.data.severity_distribution.severe ?? 0
  return ((sev / store.data.total_analyses) * 100).toFixed(1) + '%'
}
</script>

<template>
  <div class="page-shell">
    <DashboardHeader />

    <div class="page-content page-content--wide stats-page">
      <!-- 页头 -->
      <header class="stats-header">
        <div>
          <h2 class="stats-title">数据统计概览</h2>
          <p class="stats-date">{{ today }}</p>
        </div>
        <div class="stats-summary">
          <span class="summary-chip">
            累计分析 <strong class="mono-num">{{ store.data?.total_analyses ?? '--' }}</strong> 次
          </span>
          <span class="summary-chip">
            素材库 <strong class="mono-num">{{ store.data?.total_media ?? '--' }}</strong> 个
          </span>
        </div>
      </header>

      <!-- KPI 卡片 -->
      <div class="stat-grid">
        <StatCard
          title="总分析次数"
          subtitle="累计完成评估"
          :value="store.data?.total_analyses ?? '--'"
          icon="TrendCharts"
          accent="var(--accent-primary)"
        />
        <StatCard
          title="平均推理耗时"
          subtitle="MSSTformer 单次推理"
          :value="store.data?.avg_inference_time_ms ? `${store.data.avg_inference_time_ms.toFixed(1)} ms` : '--'"
          icon="Timer"
          accent="var(--accent-blue)"
        />
        <StatCard
          title="素材总数"
          subtitle="视频与图片资源"
          :value="store.data?.total_media ?? '--'"
          icon="Folder"
          accent="var(--accent-yellow)"
        />
        <StatCard
          title="重度抑郁占比"
          subtitle="BDI-II ≥ 29 分"
          :value="severePct()"
          icon="Warning"
          :accent="severityColors.severe"
        />
      </div>

      <!-- 图表区 -->
      <div class="charts-section">
        <div class="charts-row">
          <SeverityPieChart class="chart-card" />
          <BdiTrendChart class="chart-card" />
        </div>
      </div>

      <!-- 模型信息（折叠展示） -->
      <ModelMetricsCard />

      <!-- 最近报告 -->
      <RecentReportsTable />
    </div>

    <div class="app-bg" />
  </div>
</template>

<style scoped>
.stats-page {
  display: flex;
  flex-direction: column;
  gap: 20px;
  padding-top: 20px;
  padding-bottom: 32px;
}

.stats-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}

.stats-title {
  font-size: 22px;
  font-weight: 700;
  color: var(--text-primary);
  margin-bottom: 4px;
}

.stats-date {
  font-size: 13px;
  color: var(--text-muted);
}

.stats-summary {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.summary-chip {
  font-size: 12px;
  color: var(--text-secondary);
  padding: 6px 14px;
  background: rgba(148, 163, 184, 0.06);
  border: 1px solid var(--border-color);
  border-radius: 20px;
}

.summary-chip strong {
  color: var(--accent-primary);
  margin: 0 2px;
}

.stat-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 14px;
}

.charts-section {
  margin-top: 4px;
}

.charts-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
}

.chart-card {
  min-height: 320px;
}

@media (max-width: 1100px) {
  .stat-grid { grid-template-columns: repeat(2, 1fr); }
}

@media (max-width: 768px) {
  .charts-row { grid-template-columns: 1fr; }
  .stat-grid { grid-template-columns: 1fr; }
}
</style>
