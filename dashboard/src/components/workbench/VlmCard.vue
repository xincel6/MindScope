<script setup lang="ts">
import { computed } from 'vue'
import { useDashboardStore } from '@/stores/dashboard'
import EmptyState from '@/components/common/EmptyState.vue'
import { parseVlmSections } from '@/utils/clinicalContent'

const store = useDashboardStore()
const sections = computed(() => parseVlmSections(store.vlmAnalysis))
</script>

<template>
  <section class="vlm-card glass-card">
    <header class="vlm-head">
      <div>
        <h2 class="section-title">智能解读</h2>
        <p class="vlm-sub">多模态面部分析 · 模型辅助生成</p>
      </div>
      <span v-if="sections.length" class="vlm-state">需医师复核</span>
    </header>

    <div v-if="!store.vlmAnalysis" class="vlm-empty">
      <EmptyState
        compact
        icon="ChatLineSquare"
        title="尚无智能解读"
        description="分析完成后，模型会基于面部行为生成情绪状态与行为线索的解读。"
        hint="模型文本不构成诊断结论"
      />
    </div>

    <div v-else class="vlm-body">
      <template v-if="sections.length">
        <section v-for="section in sections" :key="section.title" class="vlm-section">
          <h3 class="vlm-section-title">{{ section.title }}</h3>
          <p class="vlm-section-text">{{ section.content }}</p>
        </section>
      </template>
      <p v-else class="vlm-raw">{{ store.vlmAnalysis }}</p>
    </div>
  </section>
</template>

<style scoped>
.vlm-card {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  min-width: 0;
}

.vlm-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-2);
}

.vlm-head .section-title {
  margin-bottom: 0;
}

.vlm-sub {
  margin: var(--space-1) 0 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.vlm-state {
  flex-shrink: 0;
  padding: 2px 8px;
  border-radius: var(--radius-pill);
  background: var(--color-warning-soft);
  color: var(--color-warning-text);
  font-size: var(--font-xs);
}

.vlm-empty {
  flex: 1;
  min-height: 180px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.vlm-body {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  max-height: 320px;
  overflow-y: auto;
  padding-right: var(--space-1);
}

.vlm-section-title {
  margin: 0 0 var(--space-1);
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.vlm-section-text,
.vlm-raw {
  margin: 0;
  font-size: var(--font-xs);
  line-height: 1.7;
  color: var(--text-secondary);
  white-space: pre-wrap;
}
</style>
