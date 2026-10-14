<script setup lang="ts">
defineProps<{
  title: string
  subtitle?: string
  value: string | number
  icon: string
  accent?: string
  color?: string
}>()
</script>

<template>
  <div class="stat-card glass-card glass-card--flat" :style="{ '--card-accent': accent ?? color ?? 'var(--accent-primary)' }">
    <div class="stat-top">
      <div class="stat-icon">
        <el-icon :size="20">
          <component :is="icon" />
        </el-icon>
      </div>
      <div class="stat-text">
        <div class="stat-title">{{ title }}</div>
        <div v-if="subtitle" class="stat-subtitle">{{ subtitle }}</div>
      </div>
    </div>
    <div class="stat-value mono-num">{{ value }}</div>
  </div>
</template>

<style scoped>
.stat-card {
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 18px 20px;
  border-left: 3px solid var(--card-accent);
}

.stat-top {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}

.stat-icon {
  flex-shrink: 0;
  width: 36px;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--card-accent) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--card-accent) 25%, transparent);
  border-radius: var(--radius-sm);
  color: var(--card-accent);
}

.stat-text {
  flex: 1;
  min-width: 0;
}

.stat-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary);
  line-height: 1.3;
}

.stat-subtitle {
  font-size: 11px;
  color: var(--text-muted);
  margin-top: 2px;
}

.stat-value {
  font-size: 32px;
  font-weight: 700;
  color: var(--card-accent);
  line-height: 1;
}
</style>
