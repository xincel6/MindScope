<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useDashboardStore } from '@/stores/dashboard'
import StatusBadge from '@/components/common/StatusBadge.vue'

const props = withDefaults(defineProps<{
  showPatientAction?: boolean
}>(), {
  showPatientAction: false,
})

const emit = defineEmits<{
  openPatient: []
}>()

const store = useDashboardStore()
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const clock = ref('')
let timer: ReturnType<typeof setInterval> | null = null

const isAnalysis = computed(() => route.path === '/analysis')

function logout() {
  auth.logout()
  router.push('/login')
}

function updateClock() {
  clock.value = new Date().toLocaleTimeString('zh-CN', { hour12: false })
}

onMounted(() => {
  updateClock()
  timer = setInterval(updateClock, 1000)
})
onUnmounted(() => {
  if (timer) clearInterval(timer)
})
</script>

<template>
  <header class="dashboard-header">
    <div class="header-brand">
      <div class="logo-mark">
        <svg viewBox="0 0 32 32" width="26" height="26" fill="none">
          <rect x="3" y="3" width="26" height="26" rx="7" fill="rgba(13,148,136,0.12)" stroke="var(--accent-primary)" stroke-width="1.5"/>
          <path d="M11 16h10M16 11v10" stroke="var(--accent-primary)" stroke-width="1.5" stroke-linecap="round"/>
        </svg>
      </div>
      <div class="brand-text">
        <h1 class="header-title">抑郁症智能辅助诊断系统</h1>
        <span class="header-sub">基于 BDI-II · MSSTformer 多模态分析</span>
      </div>
    </div>

    <nav class="header-nav">
      <router-link to="/" class="nav-item" active-class="nav-active">
        <el-icon :size="15"><DataAnalysis /></el-icon>
        统计概览
      </router-link>
      <router-link to="/analysis" class="nav-item" active-class="nav-active">
        <el-icon :size="15"><Monitor /></el-icon>
        智能分析
      </router-link>
    </nav>

    <div class="header-actions">
      <template v-if="showPatientAction && isAnalysis">
        <button
          type="button"
          class="patient-btn"
          :class="{ filled: store.patientInfo }"
          @click="emit('openPatient')"
        >
          <el-icon :size="14"><UserFilled /></el-icon>
          <span v-if="store.patientInfo" class="patient-id mono-num">{{ store.patientInfo.patientId }}</span>
          <span v-else>录入受试者</span>
        </button>
      </template>

      <el-button
        v-if="isAnalysis && store.mediaList.length === 0"
        size="small"
        text
        class="demo-btn"
        @click="store.loadDemoData()"
      >
        加载演示数据
      </el-button>

      <StatusBadge v-if="isAnalysis" :status="store.wsConnected ? 'connected' : 'disconnected'" />

      <div v-if="auth.user" class="user-menu">
        <el-icon :size="14"><User /></el-icon>
        <span class="user-name">{{ auth.user.username }}</span>
      </div>

      <span class="clock mono-num">{{ clock }}</span>

      <el-button size="small" text class="logout-btn" @click="logout">
        退出
      </el-button>
    </div>
  </header>
</template>

<style scoped>
.dashboard-header {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 0 16px;
  height: var(--header-height);
  background: rgba(255, 255, 255, 0.85);
  backdrop-filter: blur(12px);
  border-bottom: 1px solid var(--border-color);
  flex-shrink: 0;
  z-index: 10;
  box-shadow: var(--shadow-sm);
}

.header-brand {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
}

.logo-mark {
  display: flex;
}

.brand-text {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.header-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  line-height: 1.2;
  white-space: nowrap;
}

.header-sub {
  font-size: 10px;
  color: var(--text-muted);
  white-space: nowrap;
}

.header-nav {
  display: flex;
  gap: 4px;
  flex: 1;
  justify-content: center;
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 7px 16px;
  font-size: 13px;
  color: var(--text-secondary);
  text-decoration: none;
  border-radius: var(--radius-sm);
  border: 1px solid transparent;
  transition: all 0.18s;
  font-weight: 500;
}

.nav-item:hover {
  color: var(--text-primary);
  background: var(--bg-muted);
}

.nav-active {
  color: var(--accent-primary);
  background: rgba(13, 148, 136, 0.08);
  border-color: rgba(13, 148, 136, 0.22);
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
}

.patient-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 12px;
  font-size: 12px;
  color: var(--accent-primary);
  background: rgba(13, 148, 136, 0.06);
  border: 1px dashed rgba(13, 148, 136, 0.35);
  border-radius: var(--radius-sm);
  cursor: pointer;
  transition: all 0.18s;
  white-space: nowrap;
}

.patient-btn:hover {
  background: rgba(13, 148, 136, 0.12);
  border-style: solid;
}

.patient-btn.filled {
  border-style: solid;
  color: var(--text-primary);
  background: var(--bg-muted);
  border-color: var(--border-color);
}

.patient-id {
  font-size: 11px;
  color: var(--accent-primary);
}

.demo-btn {
  font-size: 12px;
  color: var(--text-muted) !important;
}

.user-menu {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  color: var(--text-secondary);
  padding: 4px 8px;
  border-radius: var(--radius-sm);
  background: var(--bg-muted);
  max-width: 100px;
}

.user-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.clock {
  font-size: 13px;
  color: var(--text-muted);
}

.logout-btn {
  font-size: 12px;
  color: var(--text-muted) !important;
}

@media (max-width: 1100px) {
  .header-sub { display: none; }
  .clock { display: none; }
}
</style>
