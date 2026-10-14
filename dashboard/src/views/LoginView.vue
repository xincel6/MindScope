<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const mode = ref<'login' | 'register'>('login')

const loginForm = reactive({ username: '', password: '' })
const registerForm = reactive({ username: '', email: '', password: '', confirm: '' })

async function submitLogin() {
  if (!loginForm.username.trim() || !loginForm.password) {
    ElMessage.warning('请输入用户名和密码')
    return
  }
  try {
    await auth.login(loginForm.username.trim(), loginForm.password)
    ElMessage.success('登录成功')
    await router.replace((route.query.redirect as string) || '/')
  } catch (e: unknown) {
    ElMessage.error(e instanceof Error ? e.message : '登录失败')
  }
}

async function submitRegister() {
  const u = registerForm.username.trim()
  if (!u || !registerForm.password) {
    ElMessage.warning('请填写用户名和密码')
    return
  }
  if (registerForm.password.length < 6) {
    ElMessage.warning('密码至少 6 位')
    return
  }
  if (registerForm.password !== registerForm.confirm) {
    ElMessage.warning('两次输入的密码不一致')
    return
  }
  try {
    await auth.register(u, registerForm.password, registerForm.email.trim() || undefined)
    ElMessage.success('注册成功，已自动登录')
    await router.replace((route.query.redirect as string) || '/')
  } catch (e: unknown) {
    ElMessage.error(e instanceof Error ? e.message : '注册失败')
  }
}

const features = [
  { icon: 'TrendCharts', title: 'BDI-II 量化评估', desc: '基于 Beck 抑郁量表第二版，输出 0–63 标准化评分' },
  { icon: 'Monitor', title: '多模态面部分析', desc: 'MSSTformer 深度学习模型，捕获微表情与面部运动特征' },
  { icon: 'Document', title: '临床报告导出', desc: '自动生成诊断报告，支持 PDF 导出与历史对比' },
  { icon: 'Connection', title: '端云协同推理', desc: 'WebSocket 实时流式分析，毫秒级推理响应' },
]
</script>

<template>
  <div class="login-page">
    <div class="login-layout">
      <!-- 左侧品牌区 -->
      <aside class="login-brand-panel">
        <div class="brand-content">
          <div class="brand-logo">
            <svg viewBox="0 0 40 40" width="48" height="48" fill="none">
            <rect x="4" y="4" width="32" height="32" rx="9" fill="rgba(13,148,136,0.15)" stroke="var(--accent-primary)" stroke-width="1.5"/>
            <path d="M13 20h14M20 13v14" stroke="var(--accent-primary)" stroke-width="1.5" stroke-linecap="round"/>
            </svg>
          </div>
          <h1 class="brand-title">抑郁症智能辅助诊断系统</h1>
          <p class="brand-desc">
            面向临床与研究场景的抑郁障碍辅助评估平台，融合计算机视觉与心理测量学方法，为医师提供客观、可量化的决策参考。
          </p>

          <ul class="feature-list">
            <li v-for="f in features" :key="f.title" class="feature-item">
              <div class="feature-icon">
                <el-icon :size="18"><component :is="f.icon" /></el-icon>
              </div>
              <div class="feature-text">
                <strong>{{ f.title }}</strong>
                <span>{{ f.desc }}</span>
              </div>
            </li>
          </ul>
        </div>
        <p class="brand-footer">遵循 APA / NICE / 中国抑郁障碍防治指南</p>
      </aside>

      <!-- 右侧表单区 -->
      <main class="login-form-panel">
        <div class="form-wrapper">
          <div class="form-header">
            <h2>{{ mode === 'login' ? '登录系统' : '创建账号' }}</h2>
            <p>临床辅助诊断平台 · JWT 安全鉴权</p>
          </div>

          <div class="mode-tabs">
            <button type="button" class="mode-tab" :class="{ active: mode === 'login' }" @click="mode = 'login'">登录</button>
            <button type="button" class="mode-tab" :class="{ active: mode === 'register' }" @click="mode = 'register'">注册</button>
          </div>

          <form v-if="mode === 'login'" class="auth-form" @submit.prevent="submitLogin">
            <div class="field">
              <label>用户名</label>
              <el-input v-model="loginForm.username" placeholder="请输入用户名" size="large" clearable autocomplete="username" />
            </div>
            <div class="field">
              <label>密码</label>
              <el-input v-model="loginForm.password" type="password" placeholder="请输入密码" size="large" show-password autocomplete="current-password" @keyup.enter="submitLogin" />
            </div>
            <el-button type="primary" class="submit-btn" size="large" :loading="auth.loading" native-type="submit">
              登录系统
            </el-button>
          </form>

          <form v-else class="auth-form" @submit.prevent="submitRegister">
            <div class="field">
              <label>用户名</label>
              <el-input v-model="registerForm.username" placeholder="3–32 位，字母/数字/下划线/中文" size="large" clearable autocomplete="username" />
            </div>
            <div class="field">
              <label>邮箱 <span class="optional">（选填）</span></label>
              <el-input v-model="registerForm.email" placeholder="example@hospital.org" size="large" clearable autocomplete="email" />
            </div>
            <div class="field">
              <label>密码</label>
              <el-input v-model="registerForm.password" type="password" placeholder="至少 6 位" size="large" show-password autocomplete="new-password" />
            </div>
            <div class="field">
              <label>确认密码</label>
              <el-input v-model="registerForm.confirm" type="password" placeholder="再次输入密码" size="large" show-password autocomplete="new-password" @keyup.enter="submitRegister" />
            </div>
            <el-button type="primary" class="submit-btn" size="large" :loading="auth.loading" native-type="submit">
              注册并登录
            </el-button>
          </form>
        </div>
      </main>
    </div>
    <div class="app-bg" />
  </div>
</template>

<style scoped>
.login-page {
  position: relative;
  min-height: 100vh;
  width: 100%;
  overflow: auto;
  background: var(--bg-primary);
}

.login-layout {
  position: relative;
  z-index: 1;
  display: grid;
  grid-template-columns: 1fr 480px;
  min-height: 100vh;
}

.login-brand-panel {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  padding: 48px 56px;
  background: linear-gradient(160deg, rgba(236, 253, 245, 0.7) 0%, rgba(224, 242, 254, 0.5) 100%);
  border-right: 1px solid var(--border-color);
}

.brand-content {
  max-width: 520px;
}

.brand-logo { margin-bottom: 20px; }

.brand-title {
  font-size: 28px;
  font-weight: 700;
  color: var(--text-primary);
  line-height: 1.3;
  margin-bottom: 16px;
}

.brand-desc {
  font-size: 14px;
  color: var(--text-secondary);
  line-height: 1.75;
  margin-bottom: 36px;
}

.feature-list {
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.feature-item {
  display: flex;
  align-items: flex-start;
  gap: 14px;
}

.feature-icon {
  flex-shrink: 0;
  width: 36px;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(13, 148, 136, 0.1);
  border: 1px solid rgba(13, 148, 136, 0.2);
  border-radius: var(--radius-sm);
  color: var(--accent-primary);
}

.feature-text {
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.feature-text strong {
  font-size: 13px;
  color: var(--text-primary);
  font-weight: 600;
}

.feature-text span {
  font-size: 12px;
  color: var(--text-muted);
  line-height: 1.5;
}

.brand-footer {
  font-size: 11px;
  color: var(--text-muted);
}

.login-form-panel {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 40px 48px;
  background: var(--bg-secondary);
  box-shadow: -4px 0 24px rgba(14, 116, 144, 0.06);
}

.form-wrapper {
  width: 100%;
  max-width: 360px;
}

.form-header {
  margin-bottom: 28px;
}

.form-header h2 {
  font-size: 22px;
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 6px;
}

.form-header p {
  font-size: 13px;
  color: var(--text-muted);
}

.mode-tabs {
  display: flex;
  gap: 4px;
  margin-bottom: 24px;
  padding: 3px;
  background: var(--bg-inset);
  border-radius: var(--radius-sm);
  border: 1px solid var(--border-color);
}

.mode-tab {
  flex: 1;
  padding: 9px 0;
  font-size: 14px;
  font-weight: 500;
  color: var(--text-secondary);
  background: transparent;
  border: none;
  border-radius: 5px;
  cursor: pointer;
  transition: all 0.18s;
}

.mode-tab:hover { color: var(--text-primary); }

.mode-tab.active {
  color: var(--accent-primary);
  background: rgba(13, 148, 136, 0.1);
}

.auth-form {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.field label {
  display: block;
  font-size: 12px;
  color: var(--text-secondary);
  margin-bottom: 7px;
  font-weight: 500;
}

.optional { color: var(--text-muted); font-weight: 400; }

.submit-btn {
  width: 100%;
  margin-top: 6px;
  height: 42px;
  font-size: 14px;
  font-weight: 600;
}

@media (max-width: 900px) {
  .login-layout {
    grid-template-columns: 1fr;
  }
  .login-brand-panel {
    display: none;
  }
  .login-form-panel {
    min-height: 100vh;
    box-shadow: none;
  }
}
</style>
