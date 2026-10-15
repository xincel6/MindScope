# dashboard · 前端（Vue 3 + TypeScript + Vite）

## 一键启动（推荐）

不用看下面的内容，直接在 `dashboard` 目录双击：

- `启动-仅本机.bat` —— 只有本机能访问，**日常用这个**
- `启动-局域网共享.bat` —— 同 WiFi 的其它设备也能访问

脚本会自动准备 Python 环境、装依赖、构建缺失的前端、启动服务并打开浏览器。
详细说明见 `../docs/Windows复现部署指南.md`。

---

## 后端地址是怎么确定的（重要）

前端所有请求（`/api`、`/ws`、`/media`）**不写死任何地址**，由
`src/api/baseResolver.ts` 在页面启动时自动解析，优先级如下：

| 优先级 | 候选 | 说明 |
|---|---|---|
| 0 | `?api=http://x:8000` 查询参数，或 localStorage 的 `mindscope_api_base` | 手动指定，会记住；现场排查时临时切换用 |
| 1 | **同源** | 页面由后端托管时（`serve_all.py` 把 `dist` 挂在 8000）最正确，**部署到任何服务器都不用改配置** |
| 2 | **本机** `http://127.0.0.1:8000` → `http://localhost:8000` | 本机开着后端就优先用本机 |
| 3 | **远程兜底** `VITE_REMOTE_BACKEND` | 默认 `http://100.122.178.113:8000`（已部署的服务器） |
| 4 | 都探测不通 | http(s) 页面继续用同源（保持原有报错行为） |

判定方式是请求 `候选地址 + /health`，必须返回 `{"status":"ok"}` 才算命中
（避免把静态服务器返回的 200 + HTML 误判成后端）。各候选**并发探测**，
但按优先级顺序取第一个命中的，所以正常部署下几毫秒就定了，不会等远程超时。

解析结果会：

- 打印到浏览器控制台：`[MindScope] 后端地址：...`
- 挂在 `window.__MINDSCOPE_API_BASE__`，便于现场排查

**典型场景**

| 场景 | 结果 |
|---|---|
| 后端在本机 8000，浏览器打开 `http://127.0.0.1:8000` | 同源（本地） |
| 后端部署在服务器，浏览器打开该服务器上的页面 | 同源（远程服务器的端口天然可用） |
| `dist` 单独托管在 nginx，后端在另一台机器 | 同源失败 → 本地失败 → **自动用远程地址** |
| `dist` 托管在 8080，本机后端在 8000 | 同源失败 → **自动用本机后端**（本地优先） |

> 注意：不要把 `dist/index.html` 直接双击用 `file://` 打开 —— 应用用的是
> history 路由（`createWebHistory`），必须由 http(s) 服务器托管。

## 开发

```bash
npm install
npm run dev        # http://localhost:3000
```

开发服务器会把 `/api`、`/media`、`/ws`、`/health` 代理到 `vite.config.ts` 里的
`BACKEND`（默认是已部署的服务器）。要连本机后端：

```bash
# Windows cmd
set VITE_BACKEND=http://127.0.0.1:8000 && npm run dev
# PowerShell
$env:VITE_BACKEND="http://127.0.0.1:8000"; npm run dev
```

## 构建

```bash
npm run build      # vue-tsc 类型检查 + vite 构建
npx vite build     # 只构建，跳过类型检查（仓库里存在历史类型错误时用这个）
```

构建产物 `dist/` **要提交进仓库**（`serve_all.py` 直接托管它，一键启动也依赖它）。

远程兜底地址可在构建时覆盖：

```bash
set VITE_REMOTE_BACKEND=http://your-server:8000 && npx vite build
```
