<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { Upload, Refresh } from '@element-plus/icons-vue'
import PageHeader from '@/components/layout/PageHeader.vue'
import MediaLibrary from '@/components/left-panel/MediaLibrary.vue'
import UploadMediaDialog from '@/components/common/UploadMediaDialog.vue'
import { useDashboardStore } from '@/stores/dashboard'

const store = useDashboardStore()
const router = useRouter()
const uploadVisible = ref(false)

/** 「上传素材」按钮与空态里的操作按钮都走这里：先开对话框（可填患者名），再选文件。 */
function openUpload() {
  uploadVisible.value = true
}

/**
 * 上传成功后由 store 选中新素材（`uploadMedia` 只 select、不分析），
 * 这里把用户带到工作台：AssessmentHeroCard 会显示「素材已就绪，尚未开始评估」，
 * 用户点「开始分析」才真正发起推理。
 */
function onUploaded() {
  router.push('/workbench')
}
</script>

<template>
  <div class="app-page media-page">
    <PageHeader title="素材库" subtitle="视频逐帧采样 · 图片单次推理 · 打开即带到工作台">
      <template #actions>
        <el-button :icon="Refresh" :loading="store.mediaLoading" plain @click="store.loadMediaList">
          刷新
        </el-button>
        <el-button type="primary" :icon="Upload" :loading="store.uploadLoading" @click="openUpload">
          {{ store.uploadLoading ? '上传中…' : '上传素材' }}
        </el-button>
      </template>
    </PageHeader>

    <MediaLibrary @request-upload="openUpload" />

    <UploadMediaDialog v-model="uploadVisible" title="上传素材" @uploaded="onUploaded" />
  </div>
</template>

<style scoped>
.media-page {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
}
</style>
