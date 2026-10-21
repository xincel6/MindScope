<script setup lang="ts">
/**
 * @deprecated P1 起改用纯色 ProgressBar.vue（对齐 harmony ProgressBar.ets）。
 * 本文件已无任何引用，保留薄壳只为避免遗漏的旧 import 直接报错；P2 清理时删除。
 */
import ProgressBar from './ProgressBar.vue'

withDefaults(defineProps<{ percent: number; height?: number }>(), { height: 8 })
</script>

<template>
  <ProgressBar :percent="percent" :height="height" />
</template>
