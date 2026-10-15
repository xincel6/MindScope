import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { resolve } from 'path'

// 后端地址 · 默认指向已部署的鸿蒙组服务器（Tailscale，任意网络可达）
// 只有局域网时用环境变量覆盖，不必改代码：
//   VITE_BACKEND=http://192.168.0.123:8000 npm run dev
const BACKEND = process.env.VITE_BACKEND ?? 'http://100.122.178.113:8000'
const BACKEND_WS = BACKEND.replace(/^http/, 'ws')

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
  server: {
    port: 3000,
    proxy: {
      '/media': BACKEND,
      '/api': BACKEND,
      '/ws': {
        target: BACKEND_WS,
        ws: true,
      },
    },
  },
})
