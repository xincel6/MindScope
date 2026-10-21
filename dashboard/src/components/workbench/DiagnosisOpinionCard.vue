<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import EmptyState from '@/components/common/EmptyState.vue'
import { useAuthStore } from '@/stores/auth'
import { useDashboardStore, type SeverityLevel } from '@/stores/dashboard'
import {
  OPINION_MAX_LEN,
  OPINION_MIN_LEN,
  buildAiDraft,
  buildEvidence,
  isSameSnapshot,
  type OpinionEvidence,
} from '@/utils/diagnosisOpinion'

interface OpinionSnapshot {
  score: number
  severity: SeverityLevel
  mediaId: string
  patientId: string
}

interface OpinionModel {
  mediaId: string
  status: string
  progress: number
  ready: boolean
  mediaName: string
  scoreText: string
  severityLabel: string
  severityColor: string
  conclusion: string
  evidence: OpinionEvidence[]
  aiDraft: string
  doctorName: string
  timeText: string
  emptyHint: string
}

const store = useDashboardStore()
const auth = useAuthStore()

const labels: Record<SeverityLevel, string> = {
  none: '正常',
  mild: '轻度',
  moderate: '中度',
  severe: '重度',
}

const editorText = ref('')
const baselineText = ref('')
const confirmed = ref(false)
const confirmedText = ref('')
const confirmedAt = ref('')
const confirmedSnapshot = ref<OpinionSnapshot | null>(null)
const analysisTimeText = ref('')
let initializedKey = ''

const ready = computed(() => !!store.currentFrame)
const progress = computed(() => Math.round(store.analysisProgress * 100))
const severity = computed<SeverityLevel>(() => store.severity)
const mediaId = computed(() => store.selectedMedia?.id ?? '')
const mediaName = computed(() => store.selectedMedia?.name ?? '')
const patientId = computed(() => store.patientInfo?.patientId ?? '')
const history = computed(() => store.bdiHistory.map((point) => point.score))
const doctorName = computed(() => auth.user?.username ?? '当前医师')
const sessionKey = computed(() => `${mediaId.value}:${store.analysisRunId}`)

const snapshotKey = computed(
  () =>
    `${store.currentScore}|${severity.value}|${mediaId.value}|${patientId.value}`,
)

const currentSnapshot = computed<OpinionSnapshot>(() => ({
  score: store.currentScore,
  severity: severity.value,
  mediaId: mediaId.value,
  patientId: patientId.value,
}))

const draftInput = computed(() => ({
  score: store.currentScore,
  severityLabel: store.severityLabel,
  severity: severity.value,
  suggestion: store.suggestion,
  heatmap: store.heatmapData,
  history: history.value,
  vlmAnalysis: store.vlmAnalysis,
  patientId: patientId.value,
}))

const draftBase = computed(() => (ready.value ? buildAiDraft(draftInput.value) : ''))

function formatAnalysisTime(timestamp?: number): string {
  const date = timestamp ? new Date(timestamp * 1000) : new Date()
  return date.toLocaleString('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function resetForSession() {
  editorText.value = draftBase.value
  baselineText.value = editorText.value
  confirmed.value = false
  confirmedText.value = ''
  confirmedAt.value = ''
  confirmedSnapshot.value = null
  analysisTimeText.value = formatAnalysisTime(store.currentFrame?.timestamp)
  initializedKey = sessionKey.value
}

watch(
  [ready, sessionKey],
  ([isReady]) => {
    if (!isReady) {
      editorText.value = ''
      baselineText.value = ''
      confirmed.value = false
      confirmedText.value = ''
      confirmedAt.value = ''
      confirmedSnapshot.value = null
      analysisTimeText.value = ''
      initializedKey = ''
      return
    }
    if (initializedKey !== sessionKey.value) {
      resetForSession()
    }
  },
  { immediate: true },
)

watch(snapshotKey, () => {
  if (!confirmed.value || !confirmedSnapshot.value) return
  if (!isSameSnapshot(confirmedSnapshot.value, currentSnapshot.value)) {
    confirmed.value = false
    confirmedText.value = ''
    confirmedAt.value = ''
  }
})

const status = computed(() => {
  if (!ready.value) return store.analyzing ? '生成中' : '待分析'
  if (store.analyzing) return `生成中 ${progress.value}%`
  if (
    confirmed.value &&
    confirmedSnapshot.value &&
    isSameSnapshot(confirmedSnapshot.value, currentSnapshot.value) &&
    editorText.value === confirmedText.value
  ) {
    return '已确认'
  }
  if (editorText.value !== baselineText.value) return '已修改 · 待确认'
  return '待确认'
})

const model = computed<OpinionModel>(() => ({
  mediaId: mediaId.value,
  status: status.value,
  progress: progress.value,
  ready: ready.value,
  mediaName: mediaName.value,
  scoreText: String(store.currentScore),
  severityLabel: labels[severity.value],
  severityColor: store.severityTextColor,
  conclusion: ready.value
    ? `本次评估 BDI-II 为 ${store.currentScore} 分，处于${labels[severity.value]}区间。${store.suggestion}`
    : '',
  evidence: ready.value
    ? buildEvidence({
        heatmap: store.heatmapData,
        history: history.value,
        score: store.currentScore,
        hasPatient: !!store.patientInfo,
      })
    : [],
  aiDraft: draftBase.value,
  doctorName: doctorName.value,
  timeText: analysisTimeText.value,
  emptyHint: '等待分析数据',
}))

function regenerate() {
  if (!ready.value) return
  editorText.value = buildAiDraft(draftInput.value)
  baselineText.value = editorText.value
  confirmed.value = false
  confirmedText.value = ''
  confirmedAt.value = ''
  confirmedSnapshot.value = null
  ElMessage.info('已重新生成意见草稿')
}

function cancelEdit() {
  editorText.value = confirmed.value ? confirmedText.value : baselineText.value
}

function validateOpinion(): boolean {
  const length = editorText.value.trim().length
  if (length < OPINION_MIN_LEN) {
    ElMessage.warning(`医师意见至少 ${OPINION_MIN_LEN} 字`)
    return false
  }
  if (length > OPINION_MAX_LEN) {
    ElMessage.warning(`医师意见最多 ${OPINION_MAX_LEN} 字`)
    return false
  }
  return true
}

function saveOpinion() {
  if (!validateOpinion()) return
  baselineText.value = editorText.value
  confirmed.value = false
  confirmedText.value = ''
  confirmedAt.value = ''
  confirmedSnapshot.value = null
  ElMessage.success('意见已保存（仅本次会话）')
}

function confirmOpinion() {
  if (!validateOpinion()) return
  confirmed.value = true
  confirmedText.value = editorText.value
  confirmedAt.value = new Date().toLocaleString('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
  confirmedSnapshot.value = { ...currentSnapshot.value }
  baselineText.value = editorText.value
  ElMessage.success('意见已确认（仅本次会话）')
}
</script>

<template>
  <section class="opinion-card glass-card" :data-media-id="model.mediaId || undefined">
    <header class="opinion-head">
      <div class="opinion-heading">
        <h2 class="section-title">诊断意见</h2>
        <p class="opinion-sub">模型辅助生成 · 需医师复核后生效</p>
      </div>
      <span class="opinion-state" :class="{ 'is-confirmed': status === '已确认' }">
        {{ model.status }}
      </span>
    </header>

    <div v-if="!model.ready" class="opinion-empty">
      <EmptyState
        compact
        icon="EditPen"
        :title="model.emptyHint"
        description="分析完成后，这里会显示模型初判、判断依据与可编辑的医师意见。"
        hint="意见仅保存在本次会话，不写入报告"
      />
    </div>

    <template v-else>
      <div class="opinion-score-row">
        <div class="opinion-score">
          <strong class="opinion-score-value mono-num" :style="{ color: model.severityColor }">
            {{ model.scoreText }}
          </strong>
          <span class="opinion-score-unit">分 · {{ model.severityLabel }}</span>
        </div>
        <span v-if="model.mediaId" class="opinion-media">素材 #{{ model.mediaId }}</span>
        <span v-if="model.timeText" class="opinion-time">{{ model.timeText }}</span>
      </div>

      <div class="opinion-block">
        <h3 class="opinion-block-title">综合判断</h3>
        <p class="opinion-text">{{ model.conclusion }}</p>
      </div>

      <div class="opinion-block">
        <h3 class="opinion-block-title">
          AI 初判
          <span class="opinion-tag">模型草稿</span>
        </h3>
        <p class="opinion-text opinion-draft">{{ model.aiDraft }}</p>
      </div>

      <div class="opinion-block">
        <h3 class="opinion-block-title">判断依据</h3>
        <ul class="evidence-list">
          <li
            v-for="item in model.evidence"
            :key="item.key"
            class="evidence-item"
            :class="{ 'is-unavailable': !item.available }"
          >
            <span class="evidence-index mono-num">{{ item.index }}</span>
            <span class="evidence-label">{{ item.label }}</span>
            <span class="evidence-value">{{ item.value }}</span>
            <span class="evidence-hint">{{ item.hint }}</span>
          </li>
        </ul>
      </div>

      <div class="opinion-editor">
        <div class="editor-head">
          <h3 class="opinion-block-title">医师意见</h3>
          <span class="editor-doctor">{{ model.doctorName }}</span>
        </div>
        <el-input
          v-model="editorText"
          type="textarea"
          :rows="5"
          :maxlength="OPINION_MAX_LEN"
          show-word-limit
          placeholder="请结合问诊与量表复核，填写本次诊断意见"
          aria-label="医师诊断意见"
        />
        <p class="editor-footnote">仅本次会话有效，未写入报告</p>
        <div class="editor-actions">
          <el-button text type="primary" :disabled="store.analyzing" @click="regenerate">
            重新生成
          </el-button>
          <div class="editor-actions-right">
            <el-button @click="cancelEdit">取消</el-button>
            <el-button @click="saveOpinion">保存意见</el-button>
            <el-button type="primary" @click="confirmOpinion">确认意见</el-button>
          </div>
        </div>
        <p v-if="confirmed" class="confirmed-line">
          已确认 · {{ model.doctorName }} · {{ confirmedAt }}
        </p>
      </div>

      <p class="opinion-disclaimer">
        本意见由模型辅助生成，仅作临床参考，不能替代精神科医师面诊、量表复核与影像学检查。
      </p>
    </template>
  </section>
</template>

<style scoped>
.opinion-card {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  min-width: 0;
}

.opinion-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-2);
}

.opinion-heading {
  min-width: 0;
}

.opinion-head .section-title {
  margin-bottom: 0;
}

.opinion-sub {
  margin: var(--space-1) 0 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.opinion-state {
  flex-shrink: 0;
  padding: 2px 8px;
  border-radius: var(--radius-pill);
  background: var(--color-warning-soft);
  color: var(--color-warning-text);
  font-size: var(--font-xs);
  line-height: 1.6;
}

.opinion-state.is-confirmed {
  background: var(--bg-press);
  color: var(--color-primary-text);
}

.opinion-empty {
  flex: 1;
  min-height: 180px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.opinion-score-row {
  display: flex;
  align-items: baseline;
  gap: var(--space-2);
  flex-wrap: wrap;
}

.opinion-score {
  display: flex;
  align-items: baseline;
  gap: var(--space-1);
}

.opinion-score-value {
  font-size: var(--font-metric-sm);
  line-height: 1;
}

.opinion-score-unit {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.opinion-media,
.opinion-time {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.opinion-block {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.opinion-block-title {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  margin: 0;
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.opinion-tag {
  padding: 1px 6px;
  border-radius: var(--radius-pill);
  background: var(--bg-inset);
  color: var(--text-secondary);
  font-size: var(--font-xs);
  font-weight: 400;
}

.opinion-text {
  margin: 0;
  font-size: var(--font-xs);
  line-height: 1.7;
  color: var(--text-secondary);
  white-space: pre-wrap;
}

.opinion-draft {
  padding: var(--space-2);
  border-radius: var(--radius-tag);
  background: var(--bg-inset);
}

.evidence-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.evidence-item {
  display: grid;
  grid-template-columns: 24px minmax(64px, auto) 1fr minmax(80px, auto);
  align-items: baseline;
  gap: var(--space-1);
  padding: var(--space-1) var(--space-2);
  border-radius: var(--radius-tag);
  background: var(--bg-inset);
  font-size: var(--font-xs);
}

.evidence-item.is-unavailable {
  opacity: 0.65;
}

.evidence-index {
  color: var(--text-secondary);
}

.evidence-label {
  color: var(--text-primary);
  font-weight: 600;
}

.evidence-value {
  color: var(--text-secondary);
  overflow-wrap: anywhere;
}

.evidence-hint {
  color: var(--text-secondary);
  text-align: right;
}

.opinion-editor {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  padding-top: var(--space-2);
  border-top: 1px solid var(--border);
}

.editor-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
}

.editor-doctor {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.editor-footnote {
  margin: 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.editor-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  flex-wrap: wrap;
  margin-top: var(--space-1);
}

.editor-actions-right {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  flex-wrap: wrap;
}

.confirmed-line {
  margin: 0;
  font-size: var(--font-xs);
  color: var(--color-primary-text);
}

.opinion-disclaimer {
  margin: 0;
  padding: var(--space-2);
  border-radius: var(--radius-tag);
  background: var(--bg-inset);
  font-size: var(--font-xs);
  line-height: 1.6;
  color: var(--text-secondary);
}

@media (max-width: 640px) {
  .evidence-item {
    grid-template-columns: 24px 1fr;
  }

  .evidence-value,
  .evidence-hint {
    grid-column: 2;
    text-align: left;
  }

  .editor-actions {
    align-items: stretch;
    flex-direction: column;
  }

  .editor-actions-right {
    justify-content: flex-end;
  }
}
</style>
