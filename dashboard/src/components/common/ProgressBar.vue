<script setup lang="ts">
/**
 * 纯色进度条 —— 对齐 harmony/entry/src/main/ets/components/common/ProgressBar.ets
 *  • ratio 语义 0–1（与鸿蒙 ProgressBar.ets 的 @Param ratio 一致），越界夹紧
 *  • 轨道 progressTrack → --bg-inset；填充默认主色；圆角 = 高度/2，全条裁剪
 *  • 无渐变、无光晕、无阴影（§2.6 / §2.7）
 */
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    /** 0–1 的完成比例（0.42 = 42%） */
    percent: number
    /** 条高：默认 8（UiTheme.progressHeight）；微型量表条传 4 */
    height?: number
    /** 填充色：默认主色；语义色（如严重度色）由调用方传入 */
    color?: string
  }>(),
  { height: 8, color: 'var(--color-primary)' }
)

const ratio = computed(() => {
  const v = props.percent
  if (!Number.isFinite(v) || v <= 0) return 0
  return v >= 1 ? 1 : v
})
</script>

<template>
  <div
    class="progress"
    role="progressbar"
    :aria-valuenow="Math.round(ratio * 100)"
    aria-valuemin="0"
    aria-valuemax="100"
    :style="{ height: `${height}px`, borderRadius: `${height / 2}px` }"
  >
    <div class="progress__fill" :style="{ width: `${ratio * 100}%`, background: color }" />
  </div>
</template>

<style scoped>
.progress {
  width: 100%;
  background: var(--bg-inset);
  overflow: hidden;
}
.progress__fill {
  height: 100%;
  transition: width 0.35s var(--ease-out-expo);
}
</style>
