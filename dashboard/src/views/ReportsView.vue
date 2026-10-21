<script setup lang="ts">
import { ref } from 'vue'
import PageHeader from '@/components/layout/PageHeader.vue'
import HistoryPanel from '@/components/right-panel/HistoryPanel.vue'

const panel = ref<{ reload: () => Promise<void> } | null>(null)
const refreshing = ref(false)

async function refreshAll() {
  if (!panel.value || refreshing.value) return
  refreshing.value = true
  try {
    await panel.value.reload()
  } finally {
    refreshing.value = false
  }
}
</script>

<template>
  <div class="app-page reports-page">
    <PageHeader title="历史报告" subtitle="全部辅助评估记录 · 勾选两条可并排对比">
      <template #actions>
        <el-button :loading="refreshing" plain @click="refreshAll">刷新</el-button>
      </template>
    </PageHeader>

    <section class="reports-panel glass-card">
      <HistoryPanel ref="panel" />
    </section>
  </div>
</template>

<style scoped>
.reports-page {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
}

.reports-panel {
  padding: var(--space-4);
  min-width: 0;
}
</style>
