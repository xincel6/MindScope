<script setup lang="ts">
import { reactive, watch } from 'vue'
import dayjs from 'dayjs'

const props = defineProps<{
  visible: boolean
}>()

const emit = defineEmits<{
  'update:visible': [value: boolean]
  confirm: [data: { patientId: string; gender: string; ageRange: string; assessmentDate: string }]
}>()

const form = reactive({
  patientId: '',
  gender: '',
  ageRange: '',
  assessmentDate: dayjs().format('YYYY-MM-DD'),
})

function resetForm() {
  form.patientId = ''
  form.gender = ''
  form.ageRange = ''
  form.assessmentDate = dayjs().format('YYYY-MM-DD')
}

const canConfirm = () => form.patientId && form.gender && form.ageRange

function handleConfirm() {
  if (!canConfirm()) return
  emit('confirm', { ...form })
  emit('update:visible', false)
  resetForm()
}

function handleClose() {
  emit('update:visible', false)
  resetForm()
}

function fillDemoData() {
  form.patientId = `DEMO-${String(Math.floor(Math.random() * 9000) + 1000)}`
  form.gender = Math.random() > 0.5 ? '男' : '女'
  const ages = ['18–25', '26–35', '36–45', '46–55', '56–65']
  form.ageRange = ages[Math.floor(Math.random() * ages.length)]
  form.assessmentDate = dayjs().format('YYYY-MM-DD')
}

watch(() => props.visible, (v) => {
  if (v) resetForm()
})
</script>

<template>
  <el-dialog
    :model-value="visible"
    @update:model-value="emit('update:visible', $event)"
    title="受试者信息录入"
    width="460px"
    :close-on-click-modal="false"
    class="patient-dialog"
  >
    <div class="patient-form">
      <div class="form-item">
        <label>受试者编号 <span class="required">*</span></label>
        <el-input v-model="form.patientId" placeholder="如 PT-001" maxlength="20" />
      </div>
      <div class="form-item">
        <label>性别 <span class="required">*</span></label>
        <el-select v-model="form.gender" placeholder="请选择" style="width:100%">
          <el-option label="男" value="男" />
          <el-option label="女" value="女" />
        </el-select>
      </div>
      <div class="form-item">
        <label>年龄段 <span class="required">*</span></label>
        <el-select v-model="form.ageRange" placeholder="请选择" style="width:100%">
          <el-option label="18–25 岁" value="18–25" />
          <el-option label="26–35 岁" value="26–35" />
          <el-option label="36–45 岁" value="36–45" />
          <el-option label="46–55 岁" value="46–55" />
          <el-option label="56–65 岁" value="56–65" />
          <el-option label="65 岁以上" value="65+" />
        </el-select>
      </div>
      <div class="form-item">
        <label>评估日期</label>
        <el-input v-model="form.assessmentDate" type="date" />
      </div>
    </div>

    <template #footer>
      <div class="dialog-footer">
        <el-button size="small" text @click="fillDemoData">
          <el-icon><MagicStick /></el-icon>
          随机填充
        </el-button>
        <div class="footer-right">
          <el-button size="small" @click="handleClose">取消</el-button>
          <el-button size="small" type="primary" :disabled="!canConfirm()" @click="handleConfirm">
            开始分析
          </el-button>
        </div>
      </div>
    </template>
  </el-dialog>
</template>

<style scoped>
.patient-dialog :deep(.el-dialog) {
  --el-dialog-bg-color: var(--bg-card);
}

.patient-dialog :deep(.el-dialog__title) {
  color: var(--text-primary);
  font-size: var(--font-base);
}

.patient-form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.form-item label {
  display: block;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  margin-bottom: 4px;
}

.required {
  color: var(--color-danger);
}

.dialog-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.footer-right {
  display: flex;
  gap: 8px;
}
</style>
