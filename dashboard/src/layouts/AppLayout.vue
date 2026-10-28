<script setup lang="ts">
import { provide, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import SideNav from '@/components/layout/SideNav.vue'
import SiteFooter from '@/components/layout/SiteFooter.vue'
import { useAnalysisSocket } from '@/composables/useAnalysisSocket'

const route = useRoute()
const drawerVisible = ref(false)
const mainRef = ref<HTMLElement | null>(null)

// 分析 WebSocket 挂在布局层：在五个一级页之间切换时连接不中断
useAnalysisSocket()

provide('openSideNav', () => {
  drawerVisible.value = true
})
provide('closeSideNav', () => {
  drawerVisible.value = false
})

watch(
  () => route.fullPath,
  () => {
    drawerVisible.value = false
    mainRef.value?.scrollTo({ top: 0 })
  },
)
</script>

<template>
  <div class="app-layout">
    <SideNav class="app-sidenav" />

    <!-- <768px：侧栏收进抽屉，由 PageHeader 的汉堡按钮唤起 -->
    <el-drawer
      v-model="drawerVisible"
      direction="ltr"
      size="240px"
      :with-header="false"
      class="app-nav-drawer"
    >
      <SideNav variant="drawer" />
    </el-drawer>

    <main ref="mainRef" class="app-main">
      <router-view />
      <SiteFooter />
    </main>
  </div>
</template>

<style scoped>
.app-layout {
  display: flex;
  width: 100%;
  height: 100vh;
  overflow: hidden;
  background: var(--bg-page);
}

.app-main {
  flex: 1;
  min-width: 0;
  height: 100vh;
  overflow-x: hidden;
  overflow-y: auto;
}

@media (max-width: 767px) {
  .app-sidenav {
    display: none;
  }
}

:global(.app-nav-drawer .el-drawer__body) {
  padding: 0;
}
</style>
