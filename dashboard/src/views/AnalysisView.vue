<script setup lang="ts">
import { ref } from 'vue'
import DashboardHeader from '@/components/layout/DashboardHeader.vue'
import AnalysisStatusBar from '@/components/layout/AnalysisStatusBar.vue'
import MediaLibrary from '@/components/left-panel/MediaLibrary.vue'
import FaceFrameGallery from '@/components/left-panel/FaceFrameGallery.vue'
import MainVideoPlayer from '@/components/center-panel/MainVideoPlayer.vue'
import FacePreview from '@/components/center-panel/FacePreview.vue'
import EmotionCurve from '@/components/right-panel/EmotionCurve.vue'
import RightPanel from '@/components/right-panel/RightPanel.vue'
import PatientInfoDialog from '@/components/common/PatientInfoDialog.vue'
import { useDashboardStore } from '@/stores/dashboard'

const store = useDashboardStore()
const patientDialogVisible = ref(false)

function onPatientConfirm(data: Parameters<typeof store.setPatientInfo>[0]) {
  store.setPatientInfo(data)
}
</script>

<template>
  <div class="page-shell analysis-workbench">
    <DashboardHeader
      show-patient-action
      @open-patient="patientDialogVisible = true"
    />
    <AnalysisStatusBar />

    <main class="workbench-body">
      <!-- 左栏：素材 + 人脸帧 -->
      <aside class="workbench-sidebar">
        <MediaLibrary class="sidebar-media" />
        <FaceFrameGallery layout="compact" />
      </aside>

      <!-- 中栏：监控 + 解释 -->
      <section class="workbench-main">
        <div class="main-viewer">
          <MainVideoPlayer />
        </div>
        <div class="main-insights">
          <FacePreview class="insight-face" />
          <EmotionCurve class="insight-curve" />
        </div>
      </section>

      <!-- 右栏：诊断报告 -->
      <aside class="workbench-report">
        <RightPanel />
      </aside>
    </main>

    <PatientInfoDialog
      v-model:visible="patientDialogVisible"
      @confirm="onPatientConfirm"
    />

    <div class="app-bg" />
  </div>
</template>

<style scoped>
.analysis-workbench {
  --sidebar-width: 248px;
  --report-width: 400px;
}

.workbench-body {
  flex: 1;
  display: grid;
  grid-template-columns: var(--sidebar-width) 1fr var(--report-width);
  gap: var(--content-gap);
  padding: var(--content-gap);
  min-height: 0;
  overflow: hidden;
}

.workbench-sidebar {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
  min-height: 0;
  overflow: hidden;
}

.sidebar-media {
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.workbench-main {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
  min-height: 0;
  min-width: 0;
  overflow: hidden;
}

.main-viewer {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.main-viewer :deep(.main-player) {
  flex: 1;
  min-height: 0;
}

.main-insights {
  flex-shrink: 0;
  height: 260px;
  display: grid;
  grid-template-columns: 280px 1fr;
  gap: var(--content-gap);
  min-height: 0;
}

.insight-face,
.insight-curve {
  min-height: 0;
  overflow: hidden;
}

.workbench-report {
  min-height: 0;
  overflow: hidden;
}

@media (max-width: 1280px) {
  .workbench-body {
    grid-template-columns: 220px 1fr 340px;
  }
  .main-insights {
    grid-template-columns: 240px 1fr;
    height: 240px;
  }
}

@media (max-width: 1024px) {
  .workbench-body {
    grid-template-columns: 1fr;
    grid-template-rows: auto 1fr auto;
    overflow-y: auto;
  }
  .workbench-sidebar {
    flex-direction: row;
    max-height: 200px;
  }
  .main-insights {
    grid-template-columns: 1fr;
    height: auto;
  }
  .workbench-report {
    min-height: 480px;
  }
}
</style>
