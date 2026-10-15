import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { resolve } from 'path'

// ==============================================================================
//  后端地址（仅影响 `npm run dev` 的开发代理；打包产物不含任何写死地址）
//
//  开发时前端跑在 vite 的 3000 端口，/api、/ws、/media、/health 都由这里代理出去：
//    默认指向已部署的鸿蒙组服务器（Tailscale，任意网络可达）
//    想连本机后端：  VITE_BACKEND=http://127.0.0.1:8000 npm run dev
//    想连局域网：    VITE_BACKEND=http://192.168.0.123:8000 npm run dev
//
//  打包后前端用的是「运行时自动解析」：同源 → 127.0.0.1:8000 → 远程兜底，
//  见 src/api/baseResolver.ts。远程兜底地址在构建时可覆盖：
//    VITE_REMOTE_BACKEND=http://your-server:8000 npm run build
// ==============================================================================
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
      // 运行时地址探测会请求 /health，必须一起代理，否则开发模式下会误判为「同源没有后端」
      '/health': BACKEND,
      '/ws': {
        target: BACKEND_WS,
        ws: true,
      },
    },
  },
})
