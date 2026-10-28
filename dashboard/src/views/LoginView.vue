<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { useAuthStore } from '@/stores/auth'
import { sendCodeApi } from '@/api/auth'
import { getApiBase, getApiBaseSync } from '@/api/baseResolver'
import SiteFooter from '@/components/layout/SiteFooter.vue'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

/** 三种形态：登录 / 注册 / 找回密码。
 *  「找回密码」不出现在页签上，只能从登录表单的链接进入 —— 它是低频出口，
 *  不该和登录/注册平级占一个页签。 */
const mode = ref<'login' | 'register' | 'forgot'>('login')

const loginForm = reactive({ username: '', password: '' })
const registerForm = reactive({
  username: '',
  email: '',
  password: '',
  confirm: '',
  code: '',
})
const forgotForm = reactive({ email: '', code: '', password: '', confirm: '' })

const loginError = ref('')
const loginErrorKind = ref<'' | 'auth' | 'network' | 'other'>('')
const registerError = ref('')
const registerErrorKind = ref<'' | 'auth' | 'network' | 'other'>('')
const forgotError = ref('')
const forgotErrorKind = ref<'' | 'auth' | 'network' | 'other'>('')
const serverBase = ref('')
const sendingCode = ref(false)
const codeSent = ref(false)
const countdown = ref(0)
let countdownTimer: ReturnType<typeof setInterval> | null = null

const serverLabel = computed(() => serverBase.value || getApiBaseSync() || window.location.origin)

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/** 密码强度 · 与后端 auth.py 的 _validate_password 逐条对齐（注册与重置共用） */
function validatePassword(pwd: string): string {
  if (pwd.length < 6) return '密码至少 6 位，且需包含大写字母、小写字母和特殊字符'
  const missing: string[] = []
  if (!/[A-Z]/.test(pwd)) missing.push('大写字母')
  if (!/[a-z]/.test(pwd)) missing.push('小写字母')
  if (!/[^A-Za-z0-9]/.test(pwd)) missing.push('特殊字符')
  if (missing.length) return `密码需同时包含大写字母、小写字母和特殊字符，当前缺少：${missing.join('、')}`
  return ''
}

function classifyError(e: unknown): 'auth' | 'network' | 'other' {
  const message = e instanceof Error ? e.message : String(e)
  if (/401|用户名或密码|账号或密码|密码错误/i.test(message)) return 'auth'
  if (/failed to fetch|networkerror|load failed|fetch failed|network request failed|无法连接|网络/i.test(message)) {
    return 'network'
  }
  return 'other'
}

function friendlyError(e: unknown, kind: 'auth' | 'network' | 'other'): string {
  const message = e instanceof Error ? e.message : String(e)
  if (kind === 'network') {
    return '请求没有到达服务端。请确认后端已启动、地址可达，然后重新登录。'
  }
  if (kind === 'auth') {
    return message && !/^HTTP \d+$/.test(message) ? message : '用户名或密码不正确。'
  }
  return message || '请求失败，请稍后重试。'
}

async function submitLogin() {
  loginError.value = ''
  loginErrorKind.value = ''
  if (!loginForm.username.trim() || !loginForm.password) {
    ElMessage.warning('请输入用户名和密码')
    return
  }
  try {
    await auth.login(loginForm.username.trim(), loginForm.password)
    ElMessage.success('登录成功')
    await router.replace((route.query.redirect as string) || '/')
  } catch (e: unknown) {
    const kind = classifyError(e)
    loginErrorKind.value = kind
    loginError.value = friendlyError(e, kind)
  }
}

function startCountdown(seconds: number) {
  if (countdownTimer) clearInterval(countdownTimer)
  countdown.value = seconds
  countdownTimer = setInterval(() => {
    countdown.value -= 1
    if (countdown.value <= 0 && countdownTimer) {
      clearInterval(countdownTimer)
      countdownTimer = null
    }
  }, 1000)
}

async function sendRegisterCode() {
  registerError.value = ''
  registerErrorKind.value = ''
  const email = registerForm.email.trim()
  if (!EMAIL_RE.test(email)) {
    registerErrorKind.value = 'other'
    registerError.value = '请先填写有效的邮箱地址，验证码会发送到该邮箱。'
    return
  }
  if (sendingCode.value || countdown.value > 0) return
  sendingCode.value = true
  try {
    const message = await sendCodeApi(email, 'register')
    codeSent.value = true
    startCountdown(60)
    ElMessage.success(message)
  } catch (e: unknown) {
    const kind = classifyError(e)
    registerErrorKind.value = kind
    registerError.value = friendlyError(e, kind)
  } finally {
    sendingCode.value = false
  }
}

/** 找回密码的发码 · 与注册页共用同一个 60 秒冷却计时器 */
async function sendForgotCode() {
  forgotError.value = ''
  forgotErrorKind.value = ''
  const email = forgotForm.email.trim()
  if (!EMAIL_RE.test(email)) {
    forgotErrorKind.value = 'other'
    forgotError.value = '请先填写注册时使用的邮箱地址，验证码会发送到该邮箱。'
    return
  }
  if (sendingCode.value || countdown.value > 0) return
  sendingCode.value = true
  try {
    const message = await sendCodeApi(email, 'reset')
    codeSent.value = true
    startCountdown(60)
    ElMessage.success(message)
  } catch (e: unknown) {
    const kind = classifyError(e)
    forgotErrorKind.value = kind
    forgotError.value = friendlyError(e, kind)
  } finally {
    sendingCode.value = false
  }
}

async function submitRegister() {
  registerError.value = ''
  registerErrorKind.value = ''
  const u = registerForm.username.trim()
  const email = registerForm.email.trim()
  if (!u || !registerForm.password) {
    ElMessage.warning('请填写用户名和密码')
    return
  }
  if (u.length < 3 || u.length > 32) {
    ElMessage.warning('用户名需为 3–32 位')
    return
  }
  if (!EMAIL_RE.test(email)) {
    ElMessage.warning('请填写有效的邮箱地址')
    return
  }
  const pwdError = validatePassword(registerForm.password)
  if (pwdError) {
    ElMessage.warning(pwdError)
    return
  }
  if (registerForm.password !== registerForm.confirm) {
    ElMessage.warning('两次输入的密码不一致')
    return
  }
  if (!/^\d{6}$/.test(registerForm.code.trim())) {
    ElMessage.warning('请输入 6 位邮箱验证码')
    return
  }
  try {
    await auth.register(u, registerForm.password, email, registerForm.code.trim())
    ElMessage.success('注册成功，已自动登录')
    await router.replace((route.query.redirect as string) || '/')
  } catch (e: unknown) {
    const kind = classifyError(e)
    registerErrorKind.value = kind
    registerError.value = friendlyError(e, kind)
  }
}

async function submitForgot() {
  forgotError.value = ''
  forgotErrorKind.value = ''
  const email = forgotForm.email.trim()
  if (!EMAIL_RE.test(email)) {
    ElMessage.warning('请填写有效的邮箱地址')
    return
  }
  if (!/^\d{6}$/.test(forgotForm.code.trim())) {
    ElMessage.warning('请输入 6 位邮箱验证码')
    return
  }
  const pwdError = validatePassword(forgotForm.password)
  if (pwdError) {
    ElMessage.warning(pwdError)
    return
  }
  if (forgotForm.password !== forgotForm.confirm) {
    ElMessage.warning('两次输入的密码不一致')
    return
  }
  try {
    const message = await auth.resetPassword(email, forgotForm.code.trim(), forgotForm.password)
    ElMessage.success(message || '密码已重置，请使用新密码登录')
    // 重置成功后回登录态并清空表单：用户手里只有新密码，回登录页是最自然的下一步
    mode.value = 'login'
    loginForm.username = ''
    loginForm.password = ''
    forgotForm.email = ''
    forgotForm.code = ''
    forgotForm.password = ''
    forgotForm.confirm = ''
  } catch (e: unknown) {
    const kind = classifyError(e)
    forgotErrorKind.value = kind
    forgotError.value = friendlyError(e, kind)
  }
}

function switchMode(next: 'login' | 'register' | 'forgot') {
  mode.value = next
  loginError.value = ''
  loginErrorKind.value = ''
  registerError.value = ''
  registerErrorKind.value = ''
  forgotError.value = ''
  forgotErrorKind.value = ''
}

onMounted(async () => {
  try {
    serverBase.value = await getApiBase()
  } catch {
    serverBase.value = ''
  }
})

onBeforeUnmount(() => {
  if (countdownTimer) clearInterval(countdownTimer)
})

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
            <rect x="4" y="4" width="32" height="32" rx="9" fill="var(--bg-card)" stroke="var(--color-primary)" stroke-width="1.5"/>
            <path d="M13 20h14M20 13v14" stroke="var(--color-primary)" stroke-width="1.5" stroke-linecap="round"/>
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
            <h2>{{ mode === 'login' ? '登录系统' : mode === 'register' ? '创建账号' : '找回密码' }}</h2>
            <p>临床辅助诊断平台 · JWT 安全鉴权</p>
          </div>

          <div class="mode-tabs">
            <button type="button" class="mode-tab" :class="{ active: mode === 'login' }" @click="switchMode('login')">登录</button>
            <button type="button" class="mode-tab" :class="{ active: mode === 'register' }" @click="switchMode('register')">注册</button>
          </div>

          <form v-if="mode === 'login'" class="auth-form" @submit.prevent="submitLogin">
            <div v-if="loginError" class="auth-error" role="alert">
              <strong class="auth-error-title">
                {{ loginErrorKind === 'network' ? '无法连接服务端' : '登录失败' }}
              </strong>
              <span class="auth-error-text">{{ loginError }}</span>
              <span v-if="loginErrorKind === 'network'" class="auth-error-hint">
                当前服务端地址：{{ serverLabel }}。请确认后端已启动且网络可达，然后点击「登录系统」重试。
              </span>
            </div>
            <div class="field">
              <label>用户名</label>
              <el-input v-model="loginForm.username" placeholder="请输入用户名" size="large" clearable autocomplete="username" />
            </div>
            <div class="field">
              <label>密码</label>
              <el-input v-model="loginForm.password" type="password" placeholder="请输入密码" size="large" autocomplete="current-password" @keyup.enter="submitLogin" />
            </div>
            <p class="forgot-row">
              <button type="button" class="link-btn" @click="switchMode('forgot')">忘记密码？</button>
              <span class="forgot-note">通过注册邮箱验证身份后重置密码</span>
            </p>
            <el-button type="primary" class="submit-btn" size="large" :loading="auth.loading" native-type="submit">
              登录系统
            </el-button>
          </form>

          <form v-else-if="mode === 'register'" class="auth-form" @submit.prevent="submitRegister">
            <div v-if="registerError" class="auth-error" role="alert">
              <strong class="auth-error-title">
                {{ registerErrorKind === 'network' ? '无法连接服务端' : '注册失败' }}
              </strong>
              <span class="auth-error-text">{{ registerError }}</span>
            </div>
            <div class="field">
              <label>用户名</label>
              <el-input v-model="registerForm.username" placeholder="3–32 位，字母/数字/下划线/中文" size="large" clearable autocomplete="username" />
            </div>
            <div class="field">
              <label>邮箱</label>
              <el-input v-model="registerForm.email" placeholder="example@hospital.org" size="large" clearable autocomplete="email" />
            </div>
            <div class="field">
              <label>邮箱验证码</label>
              <div class="code-row">
                <el-input
                  v-model="registerForm.code"
                  placeholder="6 位验证码"
                  size="large"
                  maxlength="6"
                  inputmode="numeric"
                  autocomplete="one-time-code"
                />
                <el-button
                  class="code-btn"
                  size="large"
                  :loading="sendingCode"
                  :disabled="countdown > 0"
                  @click="sendRegisterCode"
                >
                  {{ countdown > 0 ? `${countdown}s 后重发` : codeSent ? '重新发送' : '发送验证码' }}
                </el-button>
              </div>
              <p class="field-hint">验证码 5 分钟内有效；同一邮箱 60 秒内只能发送一次。</p>
            </div>
            <div class="field">
              <label>密码</label>
              <el-input v-model="registerForm.password" type="password" placeholder="至少 6 位，含大小写字母与特殊字符" size="large" autocomplete="new-password" />
            </div>
            <div class="field">
              <label>确认密码</label>
              <el-input v-model="registerForm.confirm" type="password" placeholder="再次输入密码" size="large" autocomplete="new-password" @keyup.enter="submitRegister" />
            </div>
            <el-button type="primary" class="submit-btn" size="large" :loading="auth.loading" native-type="submit">
              注册并登录
            </el-button>
          </form>

          <form v-else class="auth-form" @submit.prevent="submitForgot">
            <div v-if="forgotError" class="auth-error" role="alert">
              <strong class="auth-error-title">
                {{ forgotErrorKind === 'network' ? '无法连接服务端' : '重置失败' }}
              </strong>
              <span class="auth-error-text">{{ forgotError }}</span>
              <span v-if="forgotErrorKind === 'network'" class="auth-error-hint">
                当前服务端地址：{{ serverLabel }}。请确认后端已启动且网络可达，然后重试。
              </span>
            </div>
            <div class="field">
              <label>注册邮箱</label>
              <el-input v-model="forgotForm.email" placeholder="example@hospital.org" size="large" clearable autocomplete="email" />
            </div>
            <div class="field">
              <label>邮箱验证码</label>
              <div class="code-row">
                <el-input
                  v-model="forgotForm.code"
                  placeholder="6 位验证码"
                  size="large"
                  maxlength="6"
                  inputmode="numeric"
                  autocomplete="one-time-code"
                />
                <el-button
                  class="code-btn"
                  size="large"
                  :loading="sendingCode"
                  :disabled="countdown > 0"
                  @click="sendForgotCode"
                >
                  {{ countdown > 0 ? `${countdown}s 后重发` : codeSent ? '重新发送' : '发送验证码' }}
                </el-button>
              </div>
              <p class="field-hint">验证码 5 分钟内有效；同一邮箱 60 秒内只能发送一次。</p>
            </div>
            <div class="field">
              <label>新密码</label>
              <el-input v-model="forgotForm.password" type="password" placeholder="至少 6 位，含大小写字母与特殊字符" size="large" autocomplete="new-password" />
            </div>
            <div class="field">
              <label>确认新密码</label>
              <el-input v-model="forgotForm.confirm" type="password" placeholder="再次输入新密码" size="large" autocomplete="new-password" @keyup.enter="submitForgot" />
            </div>
            <el-button type="primary" class="submit-btn" size="large" :loading="auth.loading" native-type="submit">
              重置密码
            </el-button>
            <p class="form-note">
              老账户（未绑定邮箱时注册的账号）无法通过本页重置，请联系系统管理员。
            </p>
            <p class="form-note">
              <button type="button" class="link-btn" @click="switchMode('login')">返回登录</button>
            </p>
          </form>

          <p class="server-line">
            <span class="server-dot" :class="{ 'is-offline': (mode === 'forgot' ? forgotErrorKind : loginErrorKind) === 'network' }" aria-hidden="true" />
            服务端 {{ serverLabel }}
          </p>
        </div>
      </main>
    </div>
    <SiteFooter />
  </div>
</template>

<style scoped>
.login-page {
  position: relative;
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  width: 100%;
  overflow: auto;
  background: var(--bg-page);
}

.login-layout {
  position: relative;
  z-index: 1;
  display: grid;
  flex: 1;
  grid-template-columns: 1fr 480px;
  min-height: calc(100vh - 45px);
}

.login-brand-panel {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  padding: 48px 56px;
  background: var(--bg-page);
  border-right: 1px solid var(--border);
}

.brand-content {
  max-width: 520px;
}

.brand-logo { margin-bottom: 20px; }

.brand-title {
  font-size: var(--font-metric-sm);
  font-weight: 700;
  color: var(--text-primary);
  line-height: 1.3;
  margin-bottom: 16px;
}

.brand-desc {
  font-size: var(--font-sm);
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
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  color: var(--color-primary);
}

.feature-text {
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.feature-text strong {
  font-size: var(--font-sm);
  color: var(--text-primary);
  font-weight: 600;
}

.feature-text span {
  font-size: var(--font-xs);
  color: var(--text-secondary);
  line-height: 1.5;
}

.brand-footer {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.login-form-panel {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 40px 48px;
  background: var(--bg-card);
  border-left: 1px solid var(--border);
}

.form-wrapper {
  width: 100%;
  max-width: 360px;
}

.form-header {
  margin-bottom: 28px;
}

.form-header h2 {
  font-size: var(--font-title);
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 6px;
}

.form-header p {
  font-size: var(--font-sm);
  color: var(--text-secondary);
}

.mode-tabs {
  display: flex;
  gap: 4px;
  margin-bottom: 24px;
  padding: 3px;
  background: var(--bg-inset);
  border-radius: var(--radius-control);
  border: 1px solid var(--border);
}

.mode-tab {
  flex: 1;
  padding: 9px 0;
  font-size: var(--font-sm);
  font-weight: 500;
  color: var(--text-secondary);
  background: transparent;
  border: none;
  border-radius: var(--radius-tag);
  cursor: pointer;
  transition: all 0.18s;
}

.mode-tab:hover { color: var(--text-primary); }

.mode-tab.active {
  color: var(--color-primary-text);
  background: var(--bg-press);
}

.auth-form {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.field label {
  display: block;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  margin-bottom: 7px;
  font-weight: 500;
}

.optional { color: var(--text-secondary); font-weight: 400; }

.auth-error {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  padding: var(--space-3);
  background: var(--color-danger-soft);
  border-left: 3px solid var(--color-danger);
  border-radius: var(--radius-tag);
}

.auth-error-title {
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--color-danger);
}

.auth-error-text {
  font-size: var(--font-xs);
  line-height: 1.6;
  color: var(--text-primary);
}

.auth-error-hint {
  font-size: var(--font-xs);
  line-height: 1.6;
  color: var(--text-secondary);
}

.forgot-row {
  display: flex;
  align-items: baseline;
  gap: var(--space-2);
  margin: 0;
  font-size: var(--font-xs);
}

.forgot-note { color: var(--text-secondary); }

.link-btn {
  padding: 0;
  font-size: var(--font-xs);
  font-weight: 600;
  color: var(--color-primary);
  background: none;
  border: none;
  cursor: pointer;
}

.link-btn:hover { text-decoration: underline; }

.form-note {
  margin: 0;
  font-size: var(--font-xs);
  line-height: 1.6;
  color: var(--text-secondary);
}

.field-hint {
  margin: var(--space-1) 0 0;
  font-size: var(--font-xs);
  line-height: 1.5;
  color: var(--text-secondary);
}

.code-row {
  display: flex;
  align-items: center;
  gap: var(--space-2);
}

.code-row :deep(.el-input) {
  flex: 1;
  min-width: 0;
}

.code-btn {
  flex: 0 0 auto;
}

.server-line {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  margin: var(--space-4) 0 0;
  font-size: var(--font-xs);
  color: var(--text-secondary);
  font-family: var(--font-mono);
  overflow-wrap: anywhere;
}

.server-dot {
  flex: 0 0 auto;
  width: 6px;
  height: 6px;
  border-radius: var(--radius-pill);
  background: var(--status-online);
}

.server-dot.is-offline {
  background: var(--status-offline);
}

.submit-btn {
  width: 100%;
  margin-top: 6px;
  height: 42px;
  font-size: var(--font-sm);
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
    border-left: none;
  }
}

@media (max-width: 520px) {
  .login-form-panel {
    /* 窄屏不垂直居中：登录表单顶到上方，避免大片空白，也不会把注册表单顶出屏幕 */
    align-items: flex-start;
    padding: calc(var(--space-6) * 2) var(--space-4) var(--space-5);
  }

  .code-row {
    flex-direction: column;
    align-items: stretch;
  }

  .code-btn {
    width: 100%;
  }
}
</style>
