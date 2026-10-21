<script setup lang="ts">
import { inject } from 'vue'
import { Menu, ArrowLeft } from '@element-plus/icons-vue'

withDefaults(
  defineProps<{
    title: string
    subtitle?: string
    back?: boolean
  }>(),
  { subtitle: '', back: false },
)

const emit = defineEmits<{ back: [] }>()
const openSideNav = inject<(() => void) | null>('openSideNav', null)
</script>

<template>
  <header class="page-header">
    <div class="page-header-main">
      <button
        v-if="openSideNav"
        type="button"
        class="page-header-icon-btn page-header-menu"
        aria-label="打开导航"
        @click="openSideNav"
      >
        <el-icon :size="20"><Menu /></el-icon>
      </button>
      <button
        v-if="back"
        type="button"
        class="page-header-icon-btn"
        aria-label="返回"
        @click="emit('back')"
      >
        <el-icon :size="20"><ArrowLeft /></el-icon>
      </button>
      <div class="page-heading">
        <h1 class="page-title">{{ title }}</h1>
        <p v-if="subtitle" class="page-subtitle">{{ subtitle }}</p>
      </div>
    </div>
    <div v-if="$slots.actions" class="page-header-actions">
      <slot name="actions" />
    </div>
  </header>
</template>

<style scoped>
.page-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-3);
}

.page-header-main {
  display: flex;
  align-items: flex-start;
  gap: var(--space-2);
  min-width: 0;
}

.page-heading {
  /* P5 T5：长文件名没有空格，必须允许收缩 + 任意位置换行，
     否则 320/360 视口下副标题会把 .app-main 撑到 381px。 */
  flex: 1 1 auto;
  min-width: 0;
}

.page-title {
  margin: 0;
  font-size: var(--font-title);
  line-height: 1.25;
  font-weight: 600;
  color: var(--text-primary);
}

.page-subtitle {
  margin: var(--space-1) 0 0;
  font-size: var(--font-sm);
  line-height: 1.5;
  color: var(--text-secondary);
  overflow-wrap: anywhere;
}

.page-header-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  flex-wrap: wrap;
  gap: var(--space-2);
  flex-shrink: 0;
}

.page-header-icon-btn {
  flex: 0 0 auto;
  width: 36px;
  height: 36px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  background: var(--bg-card);
  color: var(--text-secondary);
  cursor: pointer;
}

.page-header-icon-btn:hover {
  background: var(--bg-inset);
  color: var(--text-primary);
}

.page-header-icon-btn:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
}

.page-header-menu {
  display: none;
}

@media (max-width: 767px) {
  .page-header {
    flex-wrap: wrap;
  }

  .page-header-menu {
    display: inline-flex;
  }

  /* 触达目标 ≥44×44：只放宽移动端，桌面视觉密度不变 */
  .page-header-icon-btn {
    width: 44px;
    height: 44px;
  }

  .page-header-actions {
    width: 100%;
    justify-content: flex-start;
  }

  .page-header-actions :deep(.el-button) {
    min-width: 44px;
    min-height: 44px;
  }
}
</style>
