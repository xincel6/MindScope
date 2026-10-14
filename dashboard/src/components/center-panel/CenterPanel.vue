<script setup lang="ts">
import MainVideoPlayer from './MainVideoPlayer.vue'
import FacePreview from './FacePreview.vue'
</script>

<template>
  <div class="center-panel">
    <MainVideoPlayer />
    <FacePreview />
  </div>
</template>

<style scoped>
.center-panel {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.center-panel > :first-child {
  flex: 1;
  min-height: 0;
}

.center-panel > :last-child {
  flex-shrink: 0;
}
</style>
