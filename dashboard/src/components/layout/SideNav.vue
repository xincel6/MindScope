<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import type { Component } from 'vue'
import {
  Odometer,
  Files,
  Document,
  DataAnalysis,
  User,
  SwitchButton,
} from '@element-plus/icons-vue'
import { useAuthStore } from '@/stores/auth'

withDefaults(defineProps<{ variant?: 'desktop' | 'drawer' }>(), {
  variant: 'desktop',
})

interface NavItem {
  label: string
  path: string
  icon: Component
}

/** 名称与顺序必须和鸿蒙 PageRoutes.ets 的 MAIN_TABS 完全一致 */
const navItems: NavItem[] = [
  { label: '工作台', path: '/workbench', icon: Odometer },
  { label: '素材库', path: '/library', icon: Files },
  { label: '历史报告', path: '/reports', icon: Document },
  { label: '统计', path: '/stats', icon: DataAnalysis },
  { label: '我的', path: '/profile', icon: User },
]

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

const username = computed(() => auth.user?.username ?? '未登录')
const initial = computed(() => (auth.user?.username ?? 'M').slice(0, 1).toUpperCase())

function isActive(path: string) {
  return route.path === path || route.path.startsWith(`${path}/`)
}

function handleLogout() {
  auth.logout()
  router.push('/login')
}
</script>

<template>
  <aside class="side-nav" :class="{ 'side-nav--drawer': variant === 'drawer' }">
    <router-link to="/workbench" class="side-brand" aria-label="MindScope 抑郁辅助诊断">

      <span class="brand-mark" aria-hidden="true">MS</span>
      <span class="brand-text">
        <strong class="brand-name">MindScope</strong>
        <span class="brand-sub">抑郁辅助诊断</span>
      </span>
    </router-link>

    <nav class="side-nav-list" aria-label="主要导航">
      <router-link
        v-for="item in navItems"
        :key="item.path"
        :to="item.path"
        class="side-nav-item"
        :class="{ active: isActive(item.path) }"
        :aria-label="item.label"
        :title="item.label"
      >
        <span class="side-nav-icon">
          <el-icon :size="22"><component :is="item.icon" /></el-icon>
        </span>
        <span class="side-nav-label">{{ item.label }}</span>
        <span class="side-nav-tip" role="tooltip">{{ item.label }}</span>
      </router-link>
    </nav>

    <div class="side-nav-footer">
      <router-link to="/profile" class="side-user">
        <span class="side-avatar" aria-hidden="true">{{ initial }}</span>
        <span class="side-user-text">
          <span class="side-user-name">{{ username }}</span>
          <span class="side-user-role">当前账号</span>
        </span>
      </router-link>
      <button type="button" class="side-logout" title="退出登录" aria-label="退出登录" @click="handleLogout">
        <el-icon :size="18"><SwitchButton /></el-icon>
      </button>
    </div>
  </aside>
</template>

<style scoped>
.side-nav {
  flex: 0 0 auto;
  width: var(--nav-width);
  height: 100vh;
  display: flex;
  flex-direction: column;
  gap: var(--space-5);
  padding: var(--space-4) var(--space-3) var(--space-3);
  background: var(--bg-card);
  border-right: 1px solid var(--border);
  overflow: visible;
}

.side-nav--drawer {
  width: 100%;
  height: 100%;
  border-right: none;
}

/* ── 品牌 ── */
.side-brand {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-1) var(--space-2);
  min-width: 0;
  text-decoration: none;
  border-radius: var(--radius-control);
}

.brand-mark {
  flex: 0 0 auto;
  width: 34px;
  height: 34px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--radius-tag);
  background: var(--gradient-brand);
  color: var(--bg-card);
  font-size: var(--font-sm);
  font-weight: 700;
  letter-spacing: 0.02em;
}

.brand-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
  line-height: 1.25;
}

.brand-name {
  font-size: var(--font-sm);
  font-weight: 600;
  color: var(--text-primary);
}

.brand-sub {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

/* ── 五项一级导航 ── */
.side-nav-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  flex: 1;
  min-height: 0;
}

.side-nav-item {
  position: relative;
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-height: 44px;
  padding: 0 var(--space-3);
  border-radius: var(--radius-control);
  color: var(--text-secondary);
  text-decoration: none;
  font-size: var(--font-sm);
  font-weight: 500;
  transition: background var(--motion-press) ease, color var(--motion-press) ease;
}

.side-nav-item::before {
  content: '';
  position: absolute;
  left: 0;
  top: 10px;
  bottom: 10px;
  width: 3px;
  border-radius: var(--radius-pill);
  background: transparent;
}

.side-nav-item:hover {
  background: var(--bg-inset);
  color: var(--text-primary);
}

.side-nav-item:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
}

.side-nav-item.active {
  background: var(--bg-press);
  /* P5 T2：14px 正文在选中底色上必须 ≥4.5:1；
     品牌主色只有 3.48:1，改用同色系文字令牌（5.47:1 对白、~5.1:1 对 bg-press）。 */
  color: var(--color-primary-text);
}

.side-nav-item.active::before {
  background: var(--color-primary);
}

.side-nav-icon {
  flex: 0 0 auto;
  width: 24px;
  height: 24px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.side-nav-label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* 1024–1279 图标条上的悬浮提示（不依赖 JS） */
.side-nav-tip {
  display: none;
  position: absolute;
  left: calc(100% + 10px);
  top: 50%;
  transform: translateY(-50%);
  padding: var(--space-1) var(--space-2);
  border-radius: var(--radius-tag);
  background: var(--text-primary);
  color: var(--bg-card);
  font-size: var(--font-xs);
  white-space: nowrap;
  z-index: 20;
  pointer-events: none;
}

/* ── 底部账号 / 退出 ── */
.side-nav-footer {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-width: 0;
  padding-top: var(--space-3);
  border-top: 1px solid var(--border);
}

.side-user {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  flex: 1;
  min-width: 0;
  padding: var(--space-1);
  border-radius: var(--radius-control);
  text-decoration: none;
}

.side-user:hover {
  background: var(--bg-inset);
}

.side-avatar {
  flex: 0 0 auto;
  width: 32px;
  height: 32px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--radius-pill);
  background: var(--bg-inset);
  color: var(--color-primary-text);
  font-size: var(--font-xs);
  font-weight: 600;
}

.side-user-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
  line-height: 1.3;
}

.side-user-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--font-sm);
  color: var(--text-primary);
}

.side-user-role {
  font-size: var(--font-xs);
  color: var(--text-secondary);
}

.side-logout {
  flex: 0 0 auto;
  width: 36px;
  height: 36px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 1px solid transparent;
  border-radius: var(--radius-control);
  background: transparent;
  color: var(--text-secondary);
  cursor: pointer;
  transition: background var(--motion-press) ease, color var(--motion-press) ease;
}

.side-logout:hover {
  background: var(--color-danger-soft);
  color: var(--color-danger);
  border-color: var(--border);
}

/* ── 1024–1279：收成 64px 图标条 ── */
@media (max-width: 1279px) {
  .side-nav:not(.side-nav--drawer) {
    width: 64px;
    padding-left: var(--space-2);
    padding-right: var(--space-2);
    gap: var(--space-3);
  }

  .side-nav:not(.side-nav--drawer) .side-brand {
    justify-content: center;
    padding: var(--space-1) 0;
  }

  .side-nav:not(.side-nav--drawer) .brand-text,
  .side-nav:not(.side-nav--drawer) .side-nav-label,
  .side-nav:not(.side-nav--drawer) .side-user-text {
    display: none;
  }

  .side-nav:not(.side-nav--drawer) .side-nav-item {
    justify-content: center;
    gap: 0;
    padding: 0;
  }

  .side-nav:not(.side-nav--drawer) .side-nav-item:hover .side-nav-tip {
    display: block;
  }

  .side-nav:not(.side-nav--drawer) .side-nav-footer {
    flex-direction: column;
  }

  .side-nav:not(.side-nav--drawer) .side-user {
    flex: 0 0 auto;
    justify-content: center;
    width: 100%;
  }
}
</style>
