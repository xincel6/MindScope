<script setup lang="ts">
import { ref, watch, onUnmounted } from 'vue'

const props = withDefaults(defineProps<{
  target: number
  duration?: number
  prefix?: string
  suffix?: string
}>(), {
  duration: 800,
  prefix: '',
  suffix: '',
})

const display = ref(0)
let animId: number | null = null

function animate(from: number, to: number, duration: number) {
  const start = performance.now()
  function step(now: number) {
    const elapsed = now - start
    const progress = Math.min(elapsed / duration, 1)
    const eased = 1 - Math.pow(1 - progress, 3)
    display.value = from + (to - from) * eased
    if (progress < 1) {
      animId = requestAnimationFrame(step)
    }
  }
  animId = requestAnimationFrame(step)
}

watch(() => props.target, (val, oldVal) => {
  if (animId) cancelAnimationFrame(animId)
  animate(oldVal ?? 0, val, props.duration)
}, { immediate: true })

onUnmounted(() => {
  if (animId) cancelAnimationFrame(animId)
})
</script>

<template>
  <span class="score-counter mono-num">
    {{ prefix }}{{ display.toFixed(0) }}{{ suffix }}
  </span>
</template>

<style scoped>
.score-counter {
  font-size: inherit;
  font-weight: 700;
  color: var(--accent-primary);
}
</style>
