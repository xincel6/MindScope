<div align="center">

# MindScope · 心镜

**基于 MSSTformer 与端云协同的轻量化抑郁情绪智能筛查系统**

本地实时筛查（低延迟闭环） · 端云协同深度诊断（语义化报告） · 鸿蒙端多端协同

</div>

---

## 一、项目简介

MindScope（心镜）是一套面向抑郁情绪早期筛查的**端云协同**智能系统。

系统以**人脸视频**为输入，在本地完成低延迟的连续情绪筛查，再把关键帧精简后单向调用云端多模态大模型生成结构化的中文诊断文本，从而在**隐私（原始视频不出本地）**、**延迟（本地实时出分）**与**语义深度（云端语义化报告）**之间取得平衡。

- **核心技术**：MSSTformer 轻量化时序模型 + MTCNN 五点地标对齐 + 时序病理空间池化 Token 压缩
- **端云协同**：原始视频仅在本机处理；上云的是压缩后的关键帧，Token 压缩比约 85%
- **多端**：Web 看板（Vue 3）+ 鸿蒙端（ArkTS / HarmonyOS）

---

## 二、核心特性

| 能力 | 说明 |
|---|---|
| 实时筛查 | WebSocket 全双工通道，逐帧推送 BDI-II 分数、对齐人脸与注意力热力图 |
| 轻量推理 | 24 帧/批次，128×128 人脸，单批次目标推理耗时 ~28ms |
| 注意力可视化 | 16×16 自注意力热力图，让模型的判断依据可解释 |
| 端云协同 | 分析结束时抽取 25% / 50% / 75% / 100% 关键帧，压缩后调用云端 GLM-4.6V |
| 报告与统计 | 历史报告、BDI 趋势图、严重程度分布、模型指标卡片、PDF 导出 |
| 多端协同 | 鸿蒙端复用同一套 REST / WebSocket 契约与共享类型定义 |

---

## 三、系统架构

### 3.1 四层架构

```
用户交互层   浏览器（Vue 3 + TypeScript + Element Plus）
             摄像头采集 / 视频上传 / 实时曲线 / 热力图 / 报告导出
                    │  HTTP(REST) + WebSocket(全双工)
应用服务层   FastAPI 异步 ASGI 网关（Python 3.10+）
             /api/auth  /api/media  /api/report  /api/upload
             /ws/analysis（实时流式推理信道）   /media（静态文件）
                    │
AI 推理引擎层 OpenCV 流式解码 → MTCNN 五点地标检测 → 双眼仿射对齐 128×128
             → MSSTformer 前向推理 → BDI-II 评分 + 自注意力热力图
             → [端云链路] 关键帧抽取 → 85% Token 压缩 → GLM-4.6V MaaS 调用
                    │
数据存储层   SQLite（aiosqlite）+ 本地文件系统 media/
             User / MediaAsset / DiagnosisReport
```

### 3.2 两条并行数据链路

**链路 A · 本地实时筛查（闭环、低延迟）**

```
上传视频/图片 → OpenCV 逐帧解码
  → 每 10 个采样帧做一次 MTCNN 完整检测（中间帧复用上一帧仿射矩阵 M）
  → 攒够 24 帧 → MSSTformer 前向 → 得到 1 个 BDI-II 分数
  → WebSocket 逐帧推送 {分数, 对齐人脸 base64, 16×16 热力图, 推理耗时, 进度}
  → 前端实时渲染 BDI 曲线 + 注意力热力图
```

**链路 B · 端云协同深度诊断（低频、语义化）**

```
分析结束 → 抽取 25%/50%/75%/100% 进度处关键帧
  → 时序病理空间池化压缩 ~85% Token
  → 单向调用云端 GLM-4.6V（vision-language）MaaS 接口
  → 返回结构化中文诊断文本 → 写入 SQLite → WebSocket 推送到报告面板
```

---

## 四、目录结构

```
MindScope/
├── dashboard/                     Web 看板 + 推理后端（一体部署）
│   ├── src/                       Vue 3 前端源码（views / components / stores / api）
│   ├── public/  index.html
│   ├── dist/                      前端构建产物（serve_all.py 直接托管，已提交）
│   ├── package.json  vite.config.ts  tsconfig*.json
│   ├── 启动-仅本机.bat            一键启动（仅 127.0.0.1 可访问，安全默认）
│   ├── 启动-局域网共享.bat        一键启动并开放局域网（演示用）
│   ├── 启动-仅本机.sh             ↑ Linux / macOS 等价脚本
│   ├── 启动-局域网共享.sh         ↑ Linux / macOS 等价脚本
│   └── backend/                   FastAPI 推理服务
│       ├── main.py                ASGI 入口：注册路由 + 挂载 /media 静态目录
│       ├── config.py              配置（密钥从 .env / 环境变量读取）
│       ├── .env.example           环境变量模板（复制为 .env 后填写）
│       ├── serve_all.py           一体化启动：SPA + API + WS 同端口，规避跨域
│       ├── routers/               auth / media / report / upload / ws
│       ├── services/              face_alignment / frame_processor / inference / vlm / llm
│       ├── models.py schemas.py database.py auth_utils.py deps.py seed.py
│       ├── best.pt                MSSTformer 权重（3.9 MB，已提交）
│       ├── demo/depression.db    演示数据种子（首次启动自动复制为 depression.db）
│       ├── media/                 演示媒体文件
│       └── requirements.txt
├── harmony/                       鸿蒙端 DevEco Studio 工程（ArkTS）
│   ├── AppScope/  entry/src/
│   │   └── main/ets/              页面 pages/ + 数据层 types/ common/ network/ persistence/ store/
│   └── build-profile.json5  oh-package.json5  hvigorfile.ts
├── docs/                          设计文档与部署指南
│   ├── README.md                  ★ 鸿蒙端文档中心（先读这里）
│   ├── 鸿蒙端开发进度.md           ★ 当前功能矩阵、缺口与验证状态
│   ├── 鸿蒙端页面框架与路由说明.md  ★ 页面 / 参数 / 路由 / 视觉规范
│   ├── 鸿蒙端数据获取使用指南.md    ★ 鸿蒙端取数接口与调用示例
│   ├── 鸿蒙端接口清单与登录注册实现.md
│   ├── 鸿蒙端网络层与类型共享方案.md
│   ├── 交付记录.md                 按时间整理的每轮交付
│   ├── 参考/                       专题分析与方案评估
│   ├── 归档/                       原始交付说明与需求输入
│   ├── 项目分析报告与HarmonyOS端构建方案.md
│   ├── Linux服务端部署指南.md      ★ 服务器（Linux）部署与验收
│   ├── Windows复现部署指南.md
│   └── images/                    系统界面截图
├── BUG清单.md                      鸿蒙端缺陷台账（活文档）
├── .gitattributes                 换行符与二进制文件属性
├── .gitignore
└── README.md
```

> 大体积素材（演示视频、答辩 PPT、技术文档原件、代码压缩包、PPT 导出图）保存在本地的 `_materials/`，已被 `.gitignore` 排除，不随仓库分发。

---

## 五、快速开始

### 5.1 后端（首次需要重建虚拟环境）

仓库不含 `venv/`，需在目标机器重建：

```bash
cd dashboard/backend

# 1) 建虚拟环境（把 python 换成你机器上的路径）
python -m venv venv

# 2) 装依赖
venv\Scripts\python.exe -m pip install -r requirements.txt
# 离线/内网环境可参考 docs/Windows复现部署指南.md 的 wheelhouse 方案

# 3) 配置密钥
copy .env.example .env
# 然后编辑 .env，填入 VLM_API_KEY / LLM_API_KEY / JWT_SECRET_KEY
```

### 5.2 前端

`dist/` 已随仓库提交，**直接跑后端即可**。若改动了前端源码再重新构建：

```bash
cd dashboard
npm install
npm run build      # 产物输出到 dashboard/dist/
```

### 5.3 一键启动（推荐）

| 脚本 | 平台 | 用途 | 访问地址 |
|---|---|---|---|
| `dashboard/启动-仅本机.bat` / `.sh` | Windows / Linux | 本机演示，仅 `127.0.0.1` 可访问（安全默认） | http://127.0.0.1:8000 |
| `dashboard/启动-局域网共享.bat` / `.sh` | Windows / Linux | 局域网演示，同网段设备 / 手机均可访问 | http://<本机IP>:8000 |

```bash
# Linux / macOS（首次需赋可执行权限）
cd dashboard
chmod +x 启动-局域网共享.sh 启动-仅本机.sh
./启动-局域网共享.sh
```

> Windows 脚本会切到 `backend/` 并用自带的 `venv` 启动 `serve_all.py`。
> 若你的 Python 不在 `D:\python\`，请按脚本内 `[ERROR]` 提示改 venv 重建路径。
> Linux 脚本会自动探测 `venv/bin/python`，找不到时回退系统 `python3` 并给出提示。

### 5.4 手工启动（等价于上面的一键启动）

```bash
# Windows
cd dashboard/backend
set KMP_DUPLICATE_LIB_OK=TRUE
set HOST=0.0.0.0            # 仅本机演示时改为 127.0.0.1
venv\Scripts\python.exe serve_all.py

# Linux / macOS
cd dashboard/backend
export KMP_DUPLICATE_LIB_OK=TRUE
export HOST=0.0.0.0
venv/bin/python serve_all.py
```

`serve_all.py` 会把 `dashboard/dist/` 的前端页面、`/api` 接口、`/ws` 信道与 `/media` 静态文件全部挂在**同一个端口**上，前端用相对路径访问，从根上避免 CORS / 跨域问题。

### 5.5 部署到 Linux 服务器

完整步骤（依赖安装、CPU 版 torch 省流量、防火墙、systemd 常驻、部署验收命令）见
**[docs/Linux服务端部署指南.md](docs/Linux服务端部署指南.md)**。

要点速览：

- 代码**无需为 Linux 改动**（无 Windows 专属 API、无硬编码路径）。
- 手机要访问**必须** `HOST=0.0.0.0`，并在防火墙 / 云安全组放行 8000 端口。
- `pip install torch` 在 Linux 上会拉带 CUDA 的版本（约 800 MB–2.5 GB）；本服务是 CPU 推理，
  可先装 `torch --index-url https://download.pytorch.org/whl/cpu` 再装其余依赖以省流量。

### 5.6 纯前后端分离调试（可选）

```bash
# 后端
cd dashboard/backend && venv\Scripts\python.exe -m uvicorn main:app --reload --port 8000

# 前端（Vite dev server，已配好 /api /ws /media 代理）
cd dashboard && npm run dev        # http://localhost:3000
```

> dev 代理**默认指向已部署的服务器**（见 5.7）。想改回连本机后端：
> `VITE_BACKEND=http://localhost:8000 npm run dev`。

### 5.7 已部署服务器与联调地址（当前团队环境）

系统已部署在**鸿蒙组服务器**上（Linux，`HOST=0.0.0.0`，systemd 用户服务 `mindscope.service`，开机自启）：

| 入口 | 地址 | 说明 |
|---|---|---|
| Tailscale | http://100.122.178.113:8000 | **任意网络可达，推荐** |
| 局域网 | http://192.168.0.123:8000 | 需与服务器同一 Wi-Fi / 网段 |
| 服务器本机 | http://127.0.0.1:8000 | 仅在服务器上有效 |

**客户端已指向该服务器，本地不必再跑后端**：

| 位置 | 默认值 | 怎么改 |
|---|---|---|
| 鸿蒙端 `harmony/entry/src/main/ets/common/ApiConfig.ets` | `100.122.178.113:8000` | 改 `host` / `port`，或运行期调 `AppStore.changeServer(host, port)` |
| 桌面端 `dashboard/vite.config.ts`（dev 代理） | `http://100.122.178.113:8000` | `VITE_BACKEND=http://192.168.0.123:8000 npm run dev` |

> 服务端不必再改地址（已监听 `0.0.0.0`）。换网段或换服务器时，**只改客户端这一处**。

---

## 六、演示数据说明（重要）

仓库**刻意包含**了服务端演示数据，克隆下来启动后界面上就能直接看到完整数据，无需自己造数据：

| 文件 | 内容 | 是否提交 |
|---|---|---|
| `dashboard/backend/demo/depression.db` | **演示种子**：8 个用户、130 条诊断报告、11 条媒体记录 | ✅ 已提交 |
| `dashboard/backend/media/` | 18 个图片 / 视频（约 15 MB），媒体库与报告预览依赖它 | ✅ 已提交 |
| `dashboard/backend/processed/label.csv` | 标签表 | ✅ 已提交 |
| `dashboard/backend/best.pt` | MSSTformer 模型权重（3.9 MB） | ✅ 已提交 |

> **运行时数据库不在仓库里**：首次启动会把 `demo/depression.db` 复制成
> `dashboard/backend/depression.db`（已 `.gitignore`），之后**只写运行库、绝不再复制种子**。
> 这样 `git pull` / `git reset` 不会再把线上数据覆盖回演示快照（BUG-26）。
>
> 线上请把库指到仓库外，并保留启动前自动备份：
>
> ```ini
> DATABASE_PATH=/var/lib/mindscope/depression.db
> DB_BACKUP_DIR=/var/lib/mindscope/backups
> ```
>
> 手动备份：`venv/bin/python backup_db.py`（热备，运行中可用；默认保留最近 10 份）。
> 详见 [Linux 服务端部署指南](docs/Linux服务端部署指南.md) 的 3.4.1。

> ⚠️ **请勿把这些文件当作临时文件清理掉**，否则远程界面会变成空列表。
> `seed.py` 只能生成 3 条演示媒体，**重建不出这 130 条报告**，删了不可恢复。
>
> 数据库中 8 个测试账号的密码以 bcrypt 哈希存储，请向作者索取明文。

---

## 七、技术栈

| 层 | 技术 |
|---|---|
| 前端 | Vue 3.5（`<script setup>` SFC）、TypeScript 6、Vite 8、Pinia 3、Vue Router 4 |
| UI / 图表 | Element Plus 2.13、ECharts 6（`vue-echarts` 8）、Tailwind CSS 4 |
| 报告导出 | html2canvas + jsPDF + dayjs |
| 后端 | FastAPI + Uvicorn（ASGI）、SQLAlchemy 2.0 async + aiosqlite、Pydantic v2 |
| 鉴权 | python-jose（JWT HS256）+ bcrypt |
| CV / DL | PyTorch 2.x、facenet-pytorch（MTCNN）、OpenCV（headless）、NumPy、Pillow、einops |
| 云端大模型 | GLM-4.6V（多模态）+ DeepSeek（文本），Infini-AI MaaS OpenAI 兼容接口 |
| 鸿蒙端 | ArkTS / HarmonyOS、DevEco Studio、hvigor |

---

## 八、相关文档

| 文档 | 内容 |
|---|---|
| [**鸿蒙端文档中心**](docs/README.md) | **鸿蒙端文档的唯一入口**：阅读路线、文档状态、目录结构与更新规范 |
| [鸿蒙端开发进度](docs/鸿蒙端开发进度.md) | **当前做到哪了**：功能矩阵、应用结构、接口缺口、验证状态与下一步 |
| [鸿蒙端页面框架与路由说明](docs/鸿蒙端页面框架与路由说明.md) | 页面目录、参数契约、路由表、转场、视觉规范、ArkTS 踩坑 |
| [鸿蒙端数据获取使用指南](docs/鸿蒙端数据获取使用指南.md) | **写 UI 必读**：`AppStore` 字段与方法、分析会话取数、异常态处理 |
| [鸿蒙端接口清单与登录注册实现](docs/鸿蒙端接口清单与登录注册实现.md) | 15 条接口清单（含患者命名）、鉴权、错误码，以及患者命名 / 上传者的增量说明 |
| [鸿蒙端网络层与类型共享方案](docs/鸿蒙端网络层与类型共享方案.md) | WebSocket 时序与边界条件、ArkTS ↔ TS 类型零漂移方案 |
| [鸿蒙端交付记录](docs/交付记录.md) | 2026-10-14 起每轮交付的目标 / 交付 / 验证 / 遗留 |
| [项目分析报告与 HarmonyOS 端构建方案](docs/项目分析报告与HarmonyOS端构建方案.md) | 项目定位、四层架构、两条数据链路、MSSTformer 细节、鸿蒙端落地方案 |
| [Linux 服务端部署指南](docs/Linux服务端部署指南.md) | 服务器拉取部署全流程、依赖与流量注意事项、systemd 常驻、部署验收命令 |
| [Windows 复现部署指南](docs/Windows复现部署指南.md) | 零依赖起步、依赖安装绕行方案、离线 wheelhouse 部署 |

---

## 九、安全须知

1. **密钥不入库**：`VLM_API_KEY` / `LLM_API_KEY` / `JWT_SECRET_KEY` 一律放在 `dashboard/backend/.env`（已被 `.gitignore` 排除），仓库只提交 `.env.example` 模板。
2. **默认只监听本机**：`serve_all.py` 默认 `HOST=127.0.0.1`。只有演示时才临时改为 `0.0.0.0`，用完请改回。
3. **数据合规**：`depression.db` 与 `media/` 属演示数据，仅用于功能演示；正式场景请遵守受试者知情同意与数据脱敏要求。
4. **上线前**：务必替换 `JWT_SECRET_KEY` 默认值，并把 `CORS_ORIGINS` 从 `["*"]` 收紧到实际域名。

---

## 十、致谢

- MSSTformer / LMTformer 模型结构参考同组时序 Transformer 工作
- 人脸检测与对齐基于 [facenet-pytorch](https://github.com/timesler/facenet-pytorch) 的 MTCNN 实现
- 云端多模态与文本能力由 Infini-AI MaaS（GLM-4.6V / DeepSeek）提供
