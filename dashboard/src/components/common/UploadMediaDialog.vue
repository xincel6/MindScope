<script setup lang="ts">
/**
 * 上传素材对话框（P4a 新增）
 * ================================================================
 * 素材库与工作台「开始新的辅助评估」卡的上传入口共用：
 *   · 一个「所属患者（可选）」输入框（留给后端 `POST /api/upload/image?patient=`）；
 *   · 一个文件选择行（图片/视频都接受，真正的类型判断在服务端）；
 *   · 上传成功后只把素材加入列表并选中，**不自动开始分析**（P4a 行为变更）。
 */
import { computed, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { FolderOpened, Upload } from '@element-plus/icons-vue'
import { useDashboardStore } from '@/stores/dashboard'
import type { MediaItem } from '@/api/index'

const props = withDefaults(
  defineProps<{
    modelValue: boolean
    title?: string
  }>(),
  { title: '上传素材' },
)

const emit = defineEmits<{
  'update:modelValue': [value: boolean]
  uploaded: [item: MediaItem]
}>()

const store = useDashboardStore()
const patient = ref('')
const file = ref<File | null>(null)
const fileInputRef = ref<HTMLInputElement | null>(null)

const fileName = computed(() => file.value?.name ?? '还没有选择文件')

// 每次打开都从空白开始，避免把上一次的患者名/文件带进来。
watch(
  () => props.modelValue,
  (open) => {
    if (!open) return
    patient.value = ''
    file.value = null
  },
)

function pickFile() {
  fileInputRef.value?.click()
}

function onFileChange(event: Event) {
  const input = event.target as HTMLInputElement
  file.value = input.files?.[0] ?? null
  input.value = ''
}

function close() {
  emit('update:modelValue', false)
}

function onVisibleChange(value: boolean) {
  emit('update:modelValue', value)
}

async function submit() {
  if (!file.value) {
    ElMessage.warning('请先选择要上传的图片或视频')
    return
  }
  const item = await store.uploadMedia(file.value, patient.value.trim() || undefined)
  if (!item) {
    ElMessage.error(store.mediaError || '上传失败')
    return
  }
  ElMessage.success('已上传并选中，可在工作台点「开始分析」发起评估')
  emit('uploaded', item)
  close()
}
</script>

<template>
  <el-dialog
    :model-value="props.modelValue"
    :title="props.title"
    width="min(480px, 92vw)"
    :close-on-click-modal="false"
    @update:model-value="onVisibleChange"
  >
    <div class="upload-form">
      <label class="upload-field">
        <span class="upload-label">所属患者（可选）</span>
        <el-input
          v-model="patient"
          maxlength="64"
          show-word-limit
          placeholder="例如：张三；留空表示未标注患者"
        />
      </label>

      <div class="upload-file">
        <el-button :icon="FolderOpened" @click="pickFile">选择文件</el-button>
        <span class="upload-file-name" :title="fileName">{{ fileName }}</span>
        <input
          ref="fileInputRef"
          type="file"
          accept="image/*,video/*"
          class="upload-file-input"
          @change="onFileChange"
        />
      </div>

      <p class="upload-note">
        上传后不会自动开始分析：素材会加入素材库并自动选中，由你确认后再点「开始分析」。
        请确保已获得受试者授权。
      </p>
    </div>

    <template #footer>
      <el-button @click="close">取消</el-button>
      <el-button
        type="primary"
        :icon="Upload"
        :loading="store.uploadLoading"
        :disabled="!file"
        @click="submit"
      >
        {{ store.uploadLoading ? '上传中…' : '开始上传' }}
      </el-button>
    </template>
  </el-dialog>
</template>

<style scoped>
.upload-form {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.upload-field {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.upload-label {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.upload-file {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-width: 0;
}

.upload-file-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.upload-file-input {
  display: none;
}

.upload-note {
  margin: 0;
  font-size: var(--font-xs);
  line-height: 1.6;
  color: var(--text-secondary);
}
</style>
