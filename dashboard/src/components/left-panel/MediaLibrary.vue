<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  ArrowDown,
  ArrowRight,
  Delete,
  EditPen,
  Picture,
  Search,
  User,
  View,
} from '@element-plus/icons-vue'
import { useDashboardStore } from '@/stores/dashboard'
import type { MediaItem } from '@/api/index'
import { resolveMediaUrl } from '@/api/baseResolver'
import EmptyState from '@/components/common/EmptyState.vue'

const emit = defineEmits<{ 'request-upload': [] }>()

const store = useDashboardStore()
const router = useRouter()
const deletingId = ref<string | null>(null)
const renamingId = ref<string | null>(null)

// P5 T1：本地 backend/media 常为空，坏图会让 alt 铺满卡片。
// 记录加载失败的素材 id，原位换成「图标 + 预览不可用」占位，卡片尺寸不变。
const brokenThumbs = ref<Set<string>>(new Set())

function markThumbBroken(id: string) {
  brokenThumbs.value.add(id)
}

// 列表刷新 / 重新上传后允许重试同一路径。
watch(
  () => store.mediaList.map((item) => `${item.id}:${item.url}`).join('|'),
  () => brokenThumbs.value.clear(),
)

// ── 搜索 / 排序（P4a）───────────────────────────────────────────────
// 后端 `GET /api/media/list` 不接收任何查询参数（backend/routers/media.py:31-36），
// 既没有 `q`/`search` 也没有 `sort`，固定按 created_at DESC 返回。
// 所以搜索与排序都在**客户端已加载列表**上做：搜索不额外发请求，排序不写服务端。
const searchQuery = ref('')

type SortMode = 'time-desc' | 'time-asc' | 'name-asc'

const sortMode = ref<SortMode>('time-desc')
const sortOptions: { value: SortMode; label: string }[] = [
  { value: 'time-desc', label: '时间 · 最新在前' },
  { value: 'time-asc', label: '时间 · 最早在前' },
  { value: 'name-asc', label: '患者姓名' },
]

const UNKNOWN_PATIENT_KEY = '__unknown__'
const UNKNOWN_PATIENT_TITLE = '未标注患者'

interface MediaGroup {
  key: string
  title: string
  isUnknown: boolean
  items: MediaItem[]
  /** 组内最新/最早时间，用于「按时间」决定组间顺序 */
  newest: number
  oldest: number
}

function patientOf(item: MediaItem): string {
  return (item.patient ?? '').trim()
}

function mediaTime(item: MediaItem): number {
  const time = Date.parse(item.created_at ?? '')
  return Number.isNaN(time) ? 0 : time
}

const keyword = computed(() => searchQuery.value.trim().toLowerCase())

/** 关键词匹配素材名称**或**患者名（对齐鸿蒙 MediaLibraryPage.ets:163-204 的搜索语义）。 */
const filtered = computed<MediaItem[]>(() => {
  const q = keyword.value
  if (!q) return store.mediaList
  return store.mediaList.filter((item) => {
    return item.name.toLowerCase().includes(q) || patientOf(item).toLowerCase().includes(q)
  })
})

/**
 * 按患者分组（对齐鸿蒙 `buildGroups()`，但按任务书把「没有患者名」的素材
 * 统一收进「未标注患者」一组；鸿蒙是退回按素材名分组的）。
 */
const groups = computed<MediaGroup[]>(() => {
  const buckets = new Map<string, MediaItem[]>()
  for (const item of filtered.value) {
    const patient = patientOf(item)
    const key = patient ? `p:${patient.toLowerCase()}` : UNKNOWN_PATIENT_KEY
    const bucket = buckets.get(key)
    if (bucket) bucket.push(item)
    else buckets.set(key, [item])
  }

  const direction = sortMode.value === 'time-asc' ? 1 : -1
  const result: MediaGroup[] = []
  buckets.forEach((items, key) => {
    const times = items.map(mediaTime)
    result.push({
      key,
      title: key === UNKNOWN_PATIENT_KEY ? UNKNOWN_PATIENT_TITLE : patientOf(items[0]),
      isUnknown: key === UNKNOWN_PATIENT_KEY,
      // 组内始终按时间排（与鸿蒙一致），方向跟随排序选择。
      items: [...items].sort((a, b) => (mediaTime(a) - mediaTime(b)) * direction),
      newest: Math.max(...times),
      oldest: Math.min(...times),
    })
  })

  result.sort((a, b) => {
    // 「未标注患者」永远压到最后，避免空患者组插在真实患者之间。
    if (a.isUnknown !== b.isUnknown) return a.isUnknown ? 1 : -1
    if (sortMode.value === 'name-asc') return a.title.localeCompare(b.title, 'zh-Hans-CN')
    if (sortMode.value === 'time-asc') return a.oldest - b.oldest
    return b.newest - a.newest
  })
  return result
})

const collapsedGroups = ref<Set<string>>(new Set())

function isCollapsed(key: string): boolean {
  // 搜索时强制展开：否则命中的素材会藏在折叠组里，看起来像「没搜到」。
  if (keyword.value) return false
  return collapsedGroups.value.has(key)
}

function toggleGroup(key: string) {
  const next = new Set(collapsedGroups.value)
  if (next.has(key)) next.delete(key)
  else next.add(key)
  collapsedGroups.value = next
}

function mediaUrl(url: string | undefined | null) {
  return resolveMediaUrl(url)
}

function videoPreview(url: string | undefined | null) {
  const resolved = resolveMediaUrl(url)
  if (!resolved) return ''
  return resolved.includes('#') ? resolved : `${resolved}#t=0.1`
}

function durationLabel(item: MediaItem) {
  if (!item.duration) return ''
  const seconds = Math.round(item.duration)
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
}

function openMedia(item: MediaItem) {
  // 对齐鸿蒙 MainPage.openMedia：只 select + 跳工作台，不在素材库直接发起推理。
  // reset 会结束进行中的分析；useAnalysisSocket 随后断开旧连接。
  store.reset()
  store.selectedMediaId = item.id
  router.push('/workbench')
}

/** 修改所属患者：`PUT /api/media/{id}/patient`，成功后 store 只局部更新列表。 */
async function changePatient(item: MediaItem) {
  let value = ''
  try {
    const result = await ElMessageBox.prompt('留空表示清除所属患者。', '修改所属患者', {
      confirmButtonText: '保存',
      cancelButtonText: '取消',
      inputValue: patientOf(item),
      inputPlaceholder: '例如：张三',
      inputValidator: (input: string) => (input ?? '').trim().length <= 64 || '患者名最长 64 个字符',
    })
    value = result.value
  } catch {
    return
  }
  renamingId.value = item.id
  try {
    await store.renamePatient(item.id, value)
    ElMessage.success('已更新所属患者')
  } catch (e: unknown) {
    ElMessage.error(e instanceof Error ? e.message : '修改所属患者失败')
  } finally {
    renamingId.value = null
  }
}

async function confirmDelete(item: MediaItem) {
  try {
    await ElMessageBox.confirm(`确定删除「${item.name}」吗？删除后不可恢复。`, '删除素材', {
      confirmButtonText: '删除',
      cancelButtonText: '取消',
      type: 'warning',
      confirmButtonClass: 'el-button--danger',
    })
  } catch {
    return
  }
  deletingId.value = item.id
  try {
    await store.removeMedia(item.id)
    ElMessage.success('已删除')
  } catch (e: unknown) {
    ElMessage.error(e instanceof Error ? e.message : '删除失败')
  } finally {
    deletingId.value = null
  }
}

onMounted(() => {
  void store.loadMediaList()
})
</script>

<template>
  <div class="media-library">
    <el-alert
      v-if="store.mediaError"
      :title="store.mediaError"
      type="error"
      show-icon
      :closable="false"
      class="media-error"
    >
      <template #default>
        <el-button size="small" text @click="store.loadMediaList">重试</el-button>
      </template>
    </el-alert>

    <el-skeleton v-if="store.mediaLoading && !store.mediaList.length" :rows="6" animated />

    <div v-else-if="!store.mediaList.length" class="media-empty">
      <EmptyState
        icon="FolderOpened"
        title="素材库还是空的"
        description="上传一段视频或一张图片，开始第一次辅助评估。"
        hint="视频会按固定间隔抽帧推理；图片只做单次推理"
        action-label="上传素材"
        @action="emit('request-upload')"
      />
    </div>

    <template v-else>
      <div class="media-toolbar">
        <el-input
          v-model="searchQuery"
          class="media-search"
          placeholder="搜索素材名称或患者姓名"
          maxlength="64"
          clearable
          :prefix-icon="Search"
        />
        <span class="media-sort-label">排序</span>
        <el-select v-model="sortMode" class="media-sort">
          <el-option
            v-for="option in sortOptions"
            :key="option.value"
            :label="option.label"
            :value="option.value"
          />
        </el-select>
      </div>

      <p class="media-count">
        共 {{ groups.length }} 组素材 · {{ filtered.length }} 个文件
        <template v-if="keyword"> · 匹配「{{ searchQuery.trim() }}」</template>
      </p>

      <div v-if="!groups.length" class="media-empty media-empty--search">
        <EmptyState
          compact
          icon="Search"
          title="没有匹配的素材"
          description="换个素材名称或患者姓名试试，也可以清空搜索条件。"
          action-label="清空搜索"
          @action="searchQuery = ''"
        />
      </div>

      <section v-for="group in groups" :key="group.key" class="media-group">
        <button
          type="button"
          class="media-group-head"
          :aria-expanded="!isCollapsed(group.key)"
          @click="toggleGroup(group.key)"
        >
          <span class="media-group-arrow" aria-hidden="true">
            <el-icon :size="14">
              <ArrowDown v-if="!isCollapsed(group.key)" />
              <ArrowRight v-else />
            </el-icon>
          </span>
          <span class="media-group-icon" aria-hidden="true">
            <el-icon :size="16"><User /></el-icon>
          </span>
          <span class="media-group-title">{{ group.title }}</span>
          <span class="media-section-count mono-num">{{ group.items.length }}</span>
        </button>

        <div v-if="!isCollapsed(group.key)" class="media-grid">
          <article
            v-for="item in group.items"
            :key="item.id"
            class="media-item"
            :class="{ active: store.selectedMediaId === item.id }"
          >
            <button type="button" class="media-open" @click="openMedia(item)">
              <span class="media-thumb">
                <img
                  v-if="item.type === 'image' && !brokenThumbs.has(item.id)"
                  :src="mediaUrl(item.url)"
                  :alt="item.name"
                  loading="lazy"
                  @error="markThumbBroken(item.id)"
                />
                <span
                  v-else-if="item.type === 'image'"
                  class="thumb-fallback"
                  role="img"
                  :aria-label="`${item.name}：预览不可用`"
                >
                  <el-icon :size="22"><Picture /></el-icon>
                  <span class="thumb-fallback__text">预览不可用</span>
                </span>
                <video v-else :src="videoPreview(item.url)" muted playsinline preload="metadata" />
                <span class="media-open-mask">
                  <el-icon :size="16"><View /></el-icon>
                  打开
                </span>
              </span>
            </button>

            <div class="media-meta">
              <span class="media-name" :title="item.name">{{ item.name }}</span>
              <span class="media-sub">
                {{ item.type === 'video' ? '视频' : '图片' }}
                <template v-if="durationLabel(item)"> · {{ durationLabel(item) }}</template>
              </span>
            </div>

            <div class="media-item-actions">
              <button
                type="button"
                class="media-icon-btn"
                title="修改所属患者"
                aria-label="修改所属患者"
                :disabled="renamingId === item.id"
                @click="changePatient(item)"
              >
                <el-icon :size="14"><EditPen /></el-icon>
              </button>
              <button
                type="button"
                class="media-icon-btn media-icon-btn--danger"
                title="删除素材"
                aria-label="删除素材"
                :disabled="deletingId === item.id"
                @click="confirmDelete(item)"
              >
                <el-icon :size="14"><Delete /></el-icon>
              </button>
            </div>
          </article>
        </div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.media-library {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  min-width: 0;
}

.media-error {
  margin-bottom: var(--space-2);
}

.media-empty {
  min-height: 360px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-card);
}

.media-empty--search {
  min-height: 240px;
}

.media-toolbar {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  flex-wrap: wrap;
}

.media-search {
  flex: 1 1 260px;
  min-width: 0;
}

.media-sort-label {
  flex: 0 0 auto;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.media-sort {
  flex: 0 0 auto;
  width: 148px;
}

.media-count {
  margin: 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.media-group {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  min-width: 0;
}

.media-group-head {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  width: 100%;
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  background: var(--bg-card);
  color: var(--text-primary);
  cursor: pointer;
  text-align: left;
  transition: border-color var(--motion-press) ease, background var(--motion-press) ease;
}

.media-group-head:hover {
  border-color: var(--color-primary);
  background: var(--bg-press);
}

.media-group-head:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
}

.media-group-arrow,
.media-group-icon {
  display: inline-flex;
  align-items: center;
  flex: 0 0 auto;
  color: var(--text-secondary);
}

.media-group-title {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--font-base);
  font-weight: 600;
}

.media-section-count {
  flex: 0 0 auto;
  padding: 1px 8px;
  border-radius: var(--radius-pill);
  background: var(--bg-inset);
  color: var(--text-secondary);
  font-size: var(--font-xs);
}

.media-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: var(--content-gap);
}

.media-item {
  position: relative;
  display: flex;
  flex-direction: column;
  min-width: 0;
  overflow: hidden;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-card);
  transition: border-color var(--motion-press) ease;
}

.media-item:hover {
  border-color: var(--color-primary);
}

.media-item.active {
  border-color: var(--color-primary);
  box-shadow: var(--focus-ring);
}

.media-open {
  display: block;
  width: 100%;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;
}

.media-open:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
}

.media-thumb {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  aspect-ratio: 16 / 10;
  overflow: hidden;
  background: var(--bg-inset);
}

.media-thumb img,
.media-thumb video {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.media-open-mask {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-1);
  background: color-mix(in srgb, var(--text-primary) 45%, transparent);
  color: var(--bg-card);
  font-size: var(--font-sm);
  opacity: 0;
  transition: opacity var(--motion-press) ease;
}

.media-item:hover .media-open-mask,
.media-open:focus-visible .media-open-mask {
  opacity: 1;
}

.media-meta {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: var(--space-2) var(--space-3);
  min-width: 0;
}

.media-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.media-sub {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.media-item-actions {
  position: absolute;
  top: var(--space-2);
  right: var(--space-2);
  display: flex;
  gap: var(--space-1);
}

.media-icon-btn {
  width: 26px;
  height: 26px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--border);
  border-radius: var(--radius-pill);
  background: color-mix(in srgb, var(--bg-card) 88%, transparent);
  color: var(--text-secondary);
  cursor: pointer;
  transition: background var(--motion-press) ease, color var(--motion-press) ease;
}

.media-icon-btn:hover {
  background: var(--bg-press);
  color: var(--color-primary-text);
}

.media-icon-btn--danger:hover {
  background: var(--color-danger-soft);
  color: var(--color-danger);
}

.media-icon-btn:disabled {
  cursor: wait;
  opacity: 0.6;
}

@media (max-width: 480px) {
  .media-grid {
    grid-template-columns: 1fr;
  }

  .media-sort {
    width: 100%;
  }
}
</style>
