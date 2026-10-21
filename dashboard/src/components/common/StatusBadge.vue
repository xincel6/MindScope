<script setup lang="ts">
defineProps<{
  status: 'connected' | 'connecting' | 'disconnected'
}>()

const labels = {
  connected: '已连接',
  connecting: '连接中',
  disconnected: '已断开',
}
</script>

<template>
  <span class="status-badge">
    <span class="status-dot" :class="status" />
    <span class="status-text">{{ labels[status] }}</span>
  </span>
</template>

<style scoped>
.status-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  padding: 3px 10px;
  border-radius: var(--radius-pill);
  background: var(--bg-inset);
  border: 1px solid var(--border);
  letter-spacing: 0.5px;
}
</style>
