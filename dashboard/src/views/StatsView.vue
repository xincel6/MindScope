<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { Refresh } from '@element-plus/icons-vue'
import PageHeader from '@/components/layout/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import SeverityPieChart from '@/components/stats/SeverityPieChart.vue'
import BdiTrendChart from '@/components/stats/BdiTrendChart.vue'
import ModelMetricsCard from '@/components/stats/ModelMetricsCard.vue'
import { useStatsStore } from '@/stores/stats'

const store = useStatsStore()
const router = useRouter()

onMounted(() => {
  void store.load()
})

const today = new Date().toLocaleDateString('zh-CN', {
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  weekday: 'long',
})

/** 一条分析、一个素材都没有：整页空态，而不是一排 '--' 卡片 */
const isEmpty = computed(() => {
  const data = store.data
  return !!data && data.total_analyses === 0 && data.total_media === 0
})

const severePct = computed(() => {
  const data = store.data
  if (!data?.total_analyses) return '--'
  const severe = data.severity_distribution.severe ?? 0
  return `${((severe / data.total_analyses) * 100).toFixed(1)}%`
})

const avgInference = computed(() => {
  const value = store.data?.avg_inference_time_ms
  return value ? `${value.toFixed(1)} ms` : '--'
})
</script>

<template>
  <div class="app-page stats-page">
    <PageHeader title="统计" :subtitle="today">
      <template #actions>
        <el-button :icon="Refresh" :loading="store.loading" plain @click="store.load">刷新</el-button>
      </template>
    </PageHeader>

    <el-skeleton v-if="!store.data && !store.error" :rows="8" animated />

    <EmptyState
      v-else-if="store.error"
      icon="WarningFilled"
      title="统计数据加载失败"
      description="没有拿到 /api/stats 的响应，请确认后端服务是否已启动。"
      :hint="store.error"
      action-label="重试"
      @action="store.load()"
    />

    <EmptyState
      v-else-if="isEmpty"
      icon="DataAnalysis"
      title="暂无统计数据"
      description="完成第一次辅助评估后，这里会显示累计次数、严重等级分布与 BDI 趋势。"
      hint="数据来源：/api/stats"
      action-label="去工作台"
      @action="router.push('/workbench')"
    />

    <template v-else-if="store.data">
      <!-- 1 张渐变 hero（106px）+ 3 张中性小卡（78px），对齐鸿蒙统计页的信息层级 -->
      <section class="stats-hero">
        <div class="stats-hero-main">
          <span class="stats-hero-label">累计辅助评估</span>
          <strong class="stats-hero-value mono-num">{{ store.data.total_analyses }}</strong>
          <span class="stats-hero-sub">完成评估次数 · 素材累计 {{ store.data.total_media }} 个</span>
        </div>
        <div class="stats-hero-side">
          <span class="stats-hero-chip">平均推理 {{ avgInference }}</span>
          <span class="stats-hero-chip">重度占比 {{ severePct }}</span>
        </div>
      </section>

      <div class="stats-kpis">
        <section class="stats-kpi">
          <span class="stats-kpi-label">平均推理耗时</span>
          <strong class="stats-kpi-value mono-num">{{ avgInference }}</strong>
          <span class="stats-kpi-note">MSSTformer 单次推理</span>
        </section>
        <section class="stats-kpi">
          <span class="stats-kpi-label">素材总数</span>
          <strong class="stats-kpi-value mono-num">{{ store.data.total_media }}</strong>
          <span class="stats-kpi-note">视频与图片资源</span>
        </section>
        <section class="stats-kpi">
          <span class="stats-kpi-label">重度抑郁占比</span>
          <strong class="stats-kpi-value mono-num">{{ severePct }}</strong>
          <span class="stats-kpi-note">BDI-II ≥ 29 分</span>
        </section>
      </div>

      <div class="stats-charts">
        <SeverityPieChart class="stats-chart" />
        <BdiTrendChart class="stats-chart" />
      </div>

      <ModelMetricsCard />
    </template>
  </div>
</template>

<style scoped>
.stats-page {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
}

.stats-hero {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-4);
  flex-wrap: wrap;
  min-height: 106px;
  padding: var(--space-3) var(--space-5);
  background: var(--gradient-kpi);
  border: 1px solid var(--border);
  border-radius: var(--radius-card);
}

.stats-hero-main {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.stats-hero-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.stats-hero-value {
  font-size: var(--font-metric);
  line-height: 1.1;
  color: var(--text-primary);
}

.stats-hero-sub {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.stats-hero-side {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: var(--space-2);
}

.stats-hero-chip {
  padding: 4px 10px;
  border-radius: var(--radius-pill);
  background: var(--bg-card);
  border: 1px solid var(--border);
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.stats-kpis {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: var(--content-gap);
}

.stats-kpi {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 2px;
  min-height: 78px;
  padding: var(--space-2) var(--space-4);
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-card);
}

.stats-kpi-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.stats-kpi-value {
  font-size: var(--font-metric-sm);
  line-height: 1.2;
  color: var(--text-primary);
}

.stats-kpi-note {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.stats-charts {
  display: grid;
  grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
  gap: var(--content-gap);
  align-items: stretch;
}

.stats-chart {
  min-width: 0;
}

@media (max-width: 1023px) {
  .stats-kpis {
    grid-template-columns: 1fr;
  }

  .stats-charts {
    grid-template-columns: 1fr;
  }
}
</style>
