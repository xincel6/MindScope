<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { SwitchButton } from '@element-plus/icons-vue'
import dayjs from 'dayjs'
import PageHeader from '@/components/layout/PageHeader.vue'
import { useAuthStore } from '@/stores/auth'
import { getApiBaseSync } from '@/api/baseResolver'

const auth = useAuthStore()
const router = useRouter()
const loggingOut = ref(false)

const username = computed(() => auth.user?.username ?? '未登录')
const initial = computed(() => username.value.slice(0, 1).toUpperCase())
const email = computed(() => auth.user?.email || '未填写')
const joinedAt = computed(() => {
  const raw = auth.user?.created_at
  return raw && dayjs(raw).isValid() ? dayjs(raw).format('YYYY-MM-DD') : '—'
})
const serverLabel = computed(() => getApiBaseSync() || window.location.origin)

async function handleLogout() {
  if (loggingOut.value) return
  try {
    await ElMessageBox.confirm(
      '退出后需要重新输入用户名和密码才能继续使用 MindScope。',
      '退出登录',
      {
        confirmButtonText: '确认退出',
        cancelButtonText: '取消',
        type: 'warning',
        distinguishCancelAndClose: true,
      },
    )
  } catch {
    return
  }
  loggingOut.value = true
  try {
    auth.logout()
    ElMessage.success('已退出登录')
    await router.push('/login')
  } finally {
    loggingOut.value = false
  }
}
</script>

<template>
  <div class="app-page profile-page">
    <PageHeader title="我的" subtitle="账号信息与登录状态" />

    <section class="profile-card glass-card">
      <div class="profile-head">
        <span class="profile-avatar" aria-hidden="true">{{ initial }}</span>
        <div class="profile-heading">
          <h2 class="profile-name">{{ username }}</h2>
          <p class="profile-mail">{{ email }}</p>
        </div>
        <el-button
          type="danger"
          plain
          :icon="SwitchButton"
          :loading="loggingOut"
          @click="handleLogout"
        >
          {{ loggingOut ? '正在退出…' : '退出登录' }}
        </el-button>
      </div>

      <dl class="profile-fields">
        <div class="profile-field">
          <dt>账号 ID</dt>
          <dd class="mono-num">{{ auth.user?.id ?? '—' }}</dd>
        </div>
        <div class="profile-field">
          <dt>用户名</dt>
          <dd>{{ username }}</dd>
        </div>
        <div class="profile-field">
          <dt>邮箱</dt>
          <dd>{{ email }}</dd>
        </div>
        <div class="profile-field">
          <dt>注册日期</dt>
          <dd class="mono-num">{{ joinedAt }}</dd>
        </div>
        <div class="profile-field">
          <dt>服务端</dt>
          <dd class="profile-server mono-num">{{ serverLabel }}</dd>
        </div>
        <div class="profile-field">
          <dt>登录状态</dt>
          <dd>{{ auth.isAuthenticated ? '已登录' : '未登录' }}</dd>
        </div>
      </dl>

      <p class="profile-note">
        退出后会清除本机的登录状态与业务缓存，需要重新登录才能继续使用。模型输出不构成诊断结论，退出前请确认当前分析已结束。
      </p>
    </section>
  </div>
</template>

<style scoped>
.profile-page {
  display: flex;
  flex-direction: column;
  gap: var(--content-gap);
}

.profile-card {
  width: 100%;
  max-width: 720px;
  padding: var(--space-5);
  display: flex;
  flex-direction: column;
  gap: var(--space-5);
}

.profile-head {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  flex-wrap: wrap;
}

.profile-avatar {
  flex: 0 0 auto;
  width: 56px;
  height: 56px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--radius-pill);
  background: var(--bg-inset);
  color: var(--color-primary-text);
  font-size: var(--font-base);
  font-weight: 600;
}

.profile-heading {
  flex: 1;
  min-width: 0;
}

.profile-name {
  margin: 0;
  font-size: var(--font-title);
  font-weight: 600;
  color: var(--text-primary);
}

.profile-mail {
  margin: var(--space-1) 0 0;
  font-size: var(--font-sm);
  color: var(--text-secondary);
  overflow-wrap: anywhere;
}

.profile-fields {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: var(--space-3);
  margin: 0;
}

.profile-field {
  padding: var(--space-3);
  background: var(--bg-inset);
  border-radius: var(--radius-tag);
  min-width: 0;
}

.profile-field dt {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.profile-field dd {
  margin: var(--space-1) 0 0;
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
  overflow-wrap: anywhere;
}

.profile-server {
  word-break: break-all;
}

.profile-note {
  margin: 0;
  padding: var(--space-3);
  background: var(--bg-inset);
  border-radius: var(--radius-tag);
  font-size: var(--font-xs);
  line-height: 1.6;
  color: var(--text-secondary);
}

@media (max-width: 640px) {
  .profile-fields {
    grid-template-columns: 1fr;
  }
}
</style>
