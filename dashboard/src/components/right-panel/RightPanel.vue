<script setup lang="ts">
import { ref } from 'vue'
import CloudTopology from './CloudTopology.vue'
import DiagnosisReport from './DiagnosisReport.vue'
import HistoryPanel from './HistoryPanel.vue'

const activeTab = ref('report')
</script>

<template>
  <div class="right-panel glass-card glass-card--flat">
    <el-tabs v-model="activeTab" class="right-tabs">
      <el-tab-pane label="诊断报告" name="report">
        <DiagnosisReport />
      </el-tab-pane>
      <el-tab-pane label="云端推理" name="cloud">
        <CloudTopology />
      </el-tab-pane>
      <el-tab-pane label="历史记录" name="history">
        <HistoryPanel />
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<style scoped>
.right-panel {
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: 0;
  overflow: hidden;
}

.right-tabs {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.right-tabs :deep(.el-tabs__header) {
  padding: 0 10px;
  margin-bottom: 0;
  flex-shrink: 0;
}

.right-tabs :deep(.el-tabs__item) {
  height: 40px;
  line-height: 40px;
  padding: 0 12px;
  font-size: 13px;
}

.right-tabs :deep(.el-tabs__content) {
  flex: 1;
  overflow-y: auto;
  min-height: 0;
  padding: 0 12px 12px;
}

.right-tabs :deep(.el-tab-pane) {
  height: 100%;
}
</style>
