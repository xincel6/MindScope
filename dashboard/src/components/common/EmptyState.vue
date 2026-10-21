<script setup lang="ts">
/**
 * EmptyState · 统一空态
 * ================================================================
 * 语义对齐鸿蒙 `harmony/entry/src/main/ets/components/common/PlaceholderView.ets`：
 *   圆形图标底 + 一句主文案 + 一句辅助说明 + （可选）补充提示 + （可选）操作按钮。
 *
 * P2 起所有「无数据」位置一律用它，禁止用假数据填位。
 * P3 的素材库 / 历史报告 / 统计页会复用，所以这里只放通用语义：
 * 不出现任何具体业务文案，图标用 Element Plus 图标组件名（main.ts 已全局注册）。
 */
withDefaults(
  defineProps<{
    /** Element Plus 图标组件名，如 'FolderOpened'、'Document'、'TrendCharts' */
    icon?: string
    /** 一句主文案：这里本来是什么 */
    title: string
    /** 一句辅助说明：为什么是空的 */
    description?: string
    /** 补充提示（更弱的一行，可空） */
    hint?: string
    /** 可选操作按钮文案；空字符串 = 不渲染按钮 */
    actionLabel?: string
    /** 紧凑模式：嵌在卡片 / 图表位等小空间时用 */
    compact?: boolean
  }>(),
  {
    icon: 'Document',
    description: '',
    hint: '',
    actionLabel: '',
    compact: false,
  },
)

const emit = defineEmits<{ action: [] }>()
</script>

<template>
  <div class="empty-state" :class="{ 'empty-state--compact': compact }">
    <div class="empty-icon">
      <el-icon :size="compact ? 22 : 28">
        <component :is="icon" />
      </el-icon>
    </div>

    <p class="empty-title">{{ title }}</p>
    <p v-if="description" class="empty-desc">{{ description }}</p>
    <p v-if="hint" class="empty-hint">{{ hint }}</p>

    <button v-if="actionLabel" type="button" class="empty-action" @click="emit('action')">
      {{ actionLabel }}
    </button>
  </div>
</template>

<style scoped>
.empty-state {
  height: 100%;
  min-height: 140px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  padding: var(--space-5) var(--space-4);
  text-align: center;
  box-sizing: border-box;
}

.empty-icon {
  width: 72px;
  height: 72px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--radius-pill);
  /* skeletonFill 而非 fillSoft：贴灰页底时仍能分辨（见 PlaceholderView.ets:39-40） */
  background: var(--bg-skeleton);
  color: var(--text-secondary);
  margin-bottom: var(--space-1);
}

.empty-title {
  margin: 0;
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.empty-desc,
.empty-hint {
  margin: 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  line-height: 1.6;
  max-width: 340px;
}

.empty-hint {
  opacity: 0.85;
}

.empty-action {
  margin-top: var(--space-2);
  padding: 6px 16px;
  font-size: var(--font-sm);
  color: var(--color-primary-text);
  background: transparent;
  border: 1px solid var(--color-primary);
  border-radius: var(--radius-control);
  cursor: pointer;
  transition: background var(--motion-press) ease;
}

.empty-action:hover {
  background: var(--bg-press);
}

/* 紧凑档：卡片内 / 220px 图表位里用，圆底缩到 56px */
.empty-state--compact {
  min-height: 96px;
  padding: var(--space-4);
  gap: var(--space-1);
}

.empty-state--compact .empty-icon {
  width: 56px;
  height: 56px;
}
</style>
