<script setup lang="ts">
withDefaults(defineProps<{
  percent: number
  height?: number
}>(), {
  height: 6,
})
</script>

<template>
  <div class="glow-progress" :style="{ height: height + 'px' }">
    <div class="glow-progress__track">
      <div
        class="glow-progress__bar"
        :style="{ width: (percent * 100) + '%' }"
      />
    </div>
  </div>
</template>

<style scoped>
.glow-progress__track {
  width: 100%;
  height: 100%;
  background: var(--bg-muted);
  border-radius: 4px;
  overflow: hidden;
}
.glow-progress__bar {
  height: 100%;
  border-radius: 4px;
  background: linear-gradient(90deg, var(--accent-teal), var(--accent-cyan));
  transition: width 0.4s var(--ease-out-expo);
}
</style>
