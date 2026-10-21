import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import AppLayout from '@/layouts/AppLayout.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('@/views/LoginView.vue'),
      meta: { title: '登录', public: true },
    },
    {
      path: '/',
      component: AppLayout,
      children: [
        { path: '', redirect: '/workbench' },
        {
          path: 'workbench',
          name: 'workbench',
          component: () => import('@/views/WorkbenchView.vue'),
          meta: { title: '工作台' },
        },
        {
          // 路径刻意不用 /media：后端媒体文件也挂在 /media/ 下，dev 代理按前缀转发，
          // /media 会被后端 404 吞掉（页面直接白屏）。改名 /library 绕开前缀冲突。
          path: 'library',
          name: 'library',
          component: () => import('@/views/MediaLibraryView.vue'),
          meta: { title: '素材库' },
        },
        {
          path: 'reports',
          name: 'reports',
          component: () => import('@/views/ReportsView.vue'),
          meta: { title: '历史报告' },
        },
        {
          path: 'reports/:mediaId',
          name: 'report-detail',
          component: () => import('@/views/ReportDetailView.vue'),
          meta: { title: '报告详情' },
        },
        {
          path: 'stats',
          name: 'stats',
          component: () => import('@/views/StatsView.vue'),
          meta: { title: '统计' },
        },
        {
          path: 'profile',
          name: 'profile',
          component: () => import('@/views/ProfileView.vue'),
          meta: { title: '我的' },
        },
      ],
    },
    {
      // 旧书签兼容：/analysis 已被工作台取代，query/hash 原样带过去
      path: '/analysis',
      redirect: (to) => ({ path: '/workbench', query: to.query, hash: to.hash }),
    },
    {
      // 演示模式独立成页：唯一允许展示编造数据的路由，进出都靠页面顶部的常驻横幅标注
      path: '/demo',
      name: 'demo',
      component: () => import('@/views/DemoView.vue'),
      meta: { title: '演示模式（非真实数据）' },
    },
    { path: '/:pathMatch(.*)*', redirect: '/workbench' },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (!auth.user && auth.token) {
    await auth.initFromStorage()
  }

  if (to.meta.public) {
    if (auth.isAuthenticated && to.name === 'login') {
      return { path: '/workbench' }
    }
    return true
  }

  if (!auth.isAuthenticated) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }
  return true
})

export default router
