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
  font-size: 11px;
  color: var(--text-secondary);
  padding: 3px 10px;
  border-radius: 12px;
  background: rgba(148, 163, 184, 0.06);
  border: 1px solid rgba(148, 163, 184, 0.1);
  letter-spacing: 0.5px;
}
</style>
