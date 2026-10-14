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
│   └── backend/                   FastAPI 推理服务
│       ├── main.py                ASGI 入口：注册路由 + 挂载 /media 静态目录
│       ├── config.py              配置（密钥从 .env / 环境变量读取）
│       ├── serve_all.py           一体化启动：SPA + API + WS 同端口，规避跨域
│       ├── routers/               auth / media / report / upload / ws
│       ├── services/              face_alignment / frame_processor / inference / vlm / llm
│       ├── models.py schemas.py database.py auth_utils.py deps.py seed.py
│       ├── best.pt                MSSTformer 权重（3.9 MB，已提交）
│       ├── depression.db          演示数据（见第六节）
│       ├── media/                 演示媒体文件
│       └── requirements.txt
├── harmony/                       鸿蒙端 DevEco Studio 工程（ArkTS）
│   ├── AppScope/  entry/src/
│   └── build-profile.json5  oh-package.json5  hvigorfile.ts
├── docs/                          设计文档与部署指南
│   ├── 项目分析报告与HarmonyOS端构建方案.md
│   ├── 鸿蒙端接口清单与登录注册实现.md
│   ├── 鸿蒙端网络层与类型共享方案.md
│   ├── Windows复现部署指南.md
│   └── images/                    系统界面截图
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

| 脚本 | 用途 | 访问地址 |
|---|---|---|
| `dashboard/启动-仅本机.bat` | 本机演示，仅 `127.0.0.1` 可访问（安全默认） | http://127.0.0.1:8000 |
| `dashboard/启动-局域网共享.bat` | 局域网演示，同网段设备均可访问 | http://<本机IP>:8000 |

> 两个脚本都会把工作目录切到 `backend/`，并用自带的 `venv` 启动 `serve_all.py`。
> 若你的 Python 不在 `D:\python\`，请按脚本内 `[ERROR]` 提示改 venv 重建路径。

### 5.4 手工启动（等价于上面的一键启动）

```bash
cd dashboard/backend
set KMP_DUPLICATE_LIB_OK=TRUE
set HOST=0.0.0.0            # 仅本机演示时改为 127.0.0.1
venv\Scripts\python.exe serve_all.py
```

`serve_all.py` 会把 `dashboard/dist/` 的前端页面、`/api` 接口、`/ws` 信道与 `/media` 静态文件全部挂在**同一个端口**上，前端用相对路径访问，从根上避免 CORS / 跨域问题。

### 5.5 纯前后端分离调试（可选）

```bash
# 后端
cd dashboard/backend && venv\Scripts\python.exe -m uvicorn main:app --reload --port 8000

# 前端（Vite dev server，已配好 /api /ws /media 代理到 8000）
cd dashboard && npm run dev        # http://localhost:3000
```

---

## 六、演示数据说明（重要）

仓库**刻意包含**了服务端演示数据，克隆下来启动后界面上就能直接看到完整数据，无需自己造数据：

| 文件 | 内容 | 是否提交 |
|---|---|---|
| `dashboard/backend/depression.db` | **8 个用户、121 条诊断报告、11 条媒体记录** | ✅ 已提交 |
| `dashboard/backend/media/` | 18 个图片 / 视频（约 15 MB），媒体库与报告预览依赖它 | ✅ 已提交 |
| `dashboard/backend/processed/label.csv` | 标签表 | ✅ 已提交 |
| `dashboard/backend/best.pt` | MSSTformer 模型权重（3.9 MB） | ✅ 已提交 |

> ⚠️ **请勿把这些文件当作临时文件清理掉**，否则远程界面会变成空列表。
> `seed.py` 只能生成 3 条演示媒体，**重建不出这 121 条报告**，删了不可恢复。
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
| [项目分析报告与 HarmonyOS 端构建方案](docs/项目分析报告与HarmonyOS端构建方案.md) | 项目定位、四层架构、两条数据链路、MSSTformer 细节、鸿蒙端落地方案 |
| [鸿蒙端接口清单与登录注册实现](docs/鸿蒙端接口清单与登录注册实现.md) | 14 条真实接口清单、鉴权细节、错误码表、ArkTS 实现步骤 |
| [鸿蒙端网络层与类型共享方案](docs/鸿蒙端网络层与类型共享方案.md) | WebSocket 时序与边界条件、ArkTS ↔ TS 类型零漂移方案 |
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
