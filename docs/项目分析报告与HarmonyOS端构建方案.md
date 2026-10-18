# MindScope · 项目分析报告与 HarmonyOS 端构建方案

> 分析对象：`E:\大挑项目\基于 MSSTformer 与端云协同的轻量化抑郁症智能筛选系统设计\`
> 分析方式：通读技术文档、答辩 PPT、训练日志、B 端全部源码（FastAPI 后端 + Vue3 前端 + LMTformer 模型）
> 报告生成时间：本项目工作区快照

---

## 第一部分 · 这个项目是做什么的

### 1.1 一句话概括

**一个"对着摄像头拍一段人脸视频 → AI 算出 BDI-II 抑郁量表分数 → 自动生成临床辅助诊断报告"的端云协同医疗筛查系统。**

它面向的是基层医疗/心理门诊场景：精神科医生资源严重不足，而传统抑郁筛查靠医生问诊 + 自评量表，主观性强、耗时长。本项目试图用"面部视频 + 轻量化深度学习模型"做一次**客观、可量化、可解释**的风险预筛，输出一个 0–63 分的 BDI-II 评分和对应的风险等级，再由云端大模型自动写出一段可读的面部病理分析建议。

### 1.2 项目来源与身份

| 项目 | 内容 |
|---|---|
| 赛事 | 第二十一届中国研究生电子设计竞赛（研电赛）技术文档 |
| 中文题目 | 基于 MSSTformer 与端云协同的轻量化抑郁症智能筛选系统设计 |
| 英文题目 | Design of a Lightweight Intelligent Depression Screening System Based on MSSTformer and Edge-Cloud Collaboration |
| 参赛单位 | 西安邮电大学 |
| 队伍名称 | 你说的不 |
| 指导老师 | 何浪 |
| 参赛队员 | 郭书萍、宫子明、张赛威 |
| 完成时间 | 2026-06-17 |
| 关键词 | 抑郁症筛查 / 轻量化 Transformer / 多尺度建模 / 可解释性 AI / 智能医疗 |

### 1.3 核心技术指标（来自技术文档与答辩材料）

| 指标 | 数值 | 说明 |
|---|---|---|
| 模型名称 | **MSSTformer**（代码中类名为 `LMTformer`） | Lightweight Multi-Scale SpatioTemporal Transformer |
| 参数量 | **0.95 M** | 对比 3D-ResNet50（46.8M）、ViT-Base+LSTM（86.2M） |
| 静态权重 | **3.8 MB** | 可随应用一起分发 |
| 计算量 | **1.1 GFLOPs** | 线性复杂度 |
| AVEC2013 MAE / RMSE | **6.12 / 7.75** | 优于 3D-ResNet50（8.12/10.45）与 ViT+LSTM（7.95/10.12） |
| AVEC2014 MAE / RMSE | **6.05 / 7.79** | 同上对比 8.46/10.92、8.18/10.34 |
| 服务器 GPU 单批次推理延迟 | **28.2 ms** | RTX 系列 12G 显存 |
| 普通 PC 纯 CPU 推理延迟 | **≈45 ms** | 基层社区医院降级部署场景 |
| 边缘开发板（香橙派 Orange Pi AIpro / 华为昇腾 NPU） | **48.24 ~ 48.70 ms** | 低于 25fps 的 40ms/帧 预算，满足实时 |
| 并发能力 | **50 路** WebSocket 流式并发 | JMeter 压测，CPU 占用 ≤62%，吞吐 >1200 req/s |
| 稳定性 | 24h 连续压测无内存泄漏 / 数据库死锁 | 人脸丢失 5–10 帧时可 12ms 内状态再对齐 |
| 云端 Token 压缩率 | **85%** | 时序病理空间池化，降低 MaaS 调用成本 |

### 1.4 三条技术主线（作品创新点）

1. **算法轻量化**——MSSTformer 用"异构感受野时域卷积"替代传统 3D-CNN/ViT，在单一极轻量通道内同时建模**高频微表情瞬变**与**长周期宏观行为退化**，把参数量压到 0.95M 的同时刷新了 AVEC 数据集的回归精度。
2. **双重可解释性**——① 端侧实时提取编码器自注意力权重矩阵，逆向重建 **16×16 面部显著性热力图**，给出"模型在看哪里"的视觉依据；② 通过无问芯穹 Infini-AI 平台的 MaaS 大模型（**GLM-4.6V** 视觉语言模型）生成符合 BDI-II 临床量表规范的**自然语言语义诊断报告**。
3. **抗噪高可用分布式部署**——Vue3 + FastAPI + WebSocket 前后端分离微服务；内置关键帧矩阵复用、丢帧拦截兜底；支持 TensorRT 剪枝与 INT8 量化；可平滑降级到国产 CPU / 昇腾 NPU 边缘端。

---

## 第二部分 · 系统架构

### 2.1 四层架构

```
┌─────────────────────────────────────────────────────────────┐
│  用户交互层   浏览器（Vue3 + TypeScript + Element Plus）        │
│              摄像头采集 / 视频上传 / 实时曲线 / 热力图 / 报告导出  │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTP(REST) + WebSocket(全双工)
┌──────────────────────────▼──────────────────────────────────┐
│  应用服务层   FastAPI 异步 ASGI 网关（Python 3.10+）            │
│   /api/auth   /api/media   /api/report   /api/upload          │
│   /ws/analysis（实时流式推理信道）    /media（静态文件）          │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  AI 推理引擎层                                                  │
│   OpenCV 流式解码 → MTCNN 5点地标检测 → 双眼仿射对齐 128×128      │
│   → MSSTformer 前向推理 → BDI-II 评分 + 自注意力热力图            │
│   → [端云链路] 关键帧抽取 → 85% Token 压缩 → GLM-4.6V MaaS 调用   │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  数据存储层   SQLite（aiosqlite）+ 本地文件系统 media/           │
│   User / MediaAsset / DiagnosisReport                         │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 两条并行数据链路（**这是理解整个系统的关键**）

**链路 A · 本地实时筛查（闭环、低延迟）**
```
客户端上传视频/图片 → 后端 OpenCV 逐帧解码
  → 每 10 个采样帧做一次 MTCNN 完整检测（中间帧复用上一帧仿射矩阵 M）
  → 攒 24 帧 → MSSTformer 前向 → 得到 1 个 BDI-II 分数
  → 通过 WebSocket 逐帧推送 {分数, 对齐人脸base64, 16×16热力图, 推理耗时, 进度}
  → 前端实时渲染 BDI 曲线 + 注意力热力图
```

**链路 B · 端云协同深度诊断（低频、语义化）**
```
分析结束时 → 抽取 25%/50%/75%/100% 进度处的关键帧
  → 时序病理空间池化压缩 85% Token
  → 单向调用云端 GLM-4.6V（vision-language）MaaS 接口
  → 返回结构化中文诊断文本 → 写入 SQLite → WebSocket 推给前端报告面板
```

### 2.3 技术栈清单

| 层 | 技术 |
|---|---|
| 前端 | Vue 3.5（`<script setup>` SFC）、TypeScript 6、Vite 8、Pinia 3、Vue Router 4 |
| UI 组件库 | Element Plus 2.13 + `@element-plus/icons-vue` |
| 图表 | ECharts 6（`vue-echarts` 8）—— 折线图 / 饼图 / 力导向关系图 |
| 样式 | Tailwind CSS 4（`@tailwindcss/vite`）+ 大量自定义 CSS 变量 |
| 报告导出 | `html2canvas` + `jspdf` + `dayjs` |
| 后端 | FastAPI + Uvicorn（ASGI）、SQLAlchemy 2.0 async + aiosqlite、Pydantic v2 |
| 鉴权 | Python-JOSE（JWT HS256）+ bcrypt |
| CV / DL | PyTorch 2.x、`facenet-pytorch`（MTCNN）、OpenCV（headless）、NumPy、Pillow、einops |
| 云端大模型 | 无问芯穹 Infini-AI MaaS：`glm-4.6v`（视觉）、`deepseek-v4-flash`（文本） |

---

## 第三部分 · MSSTformer 算法细节

### 3.1 输入输出契约

```
输入：  24 帧对齐人脸，每帧 (128,128,3) uint8 BGR
输出：  BDI-II 总分（单个 clip 级标量，回归值域 0–63）
        + 最后一层自注意力的 16×16 空间显著性热力图
```

### 3.2 网络前向流程（`LMTformer_model/LMTformer.py`）

```
x  [B, 3, 24, 128, 128]
  │
  ├─ 前置粗粒度特征提取 CFE（3 级 3D CNN Stem）
  │    Stem0: Conv3d(3→8,[1,5,5]) + BN + ReLU + MaxPool(1,2,2) → [B, 8, 24, 64, 64]
  │    Stem1: Conv3d(8→16,[3,3,3]) + BN + ReLU + MaxPool(1,2,2) → [B,16, 24, 32, 32]
  │    Stem2: Conv3d(16→32,[3,3,3]) + BN + ReLU + MaxPool(1,2,2) → [B,32, 24, 16, 16]
  │
  ├─ Patch Embedding: Conv3d(32,32,kernel=(2,4,4),stride=(2,4,4)) → [B, 32, 12, 4, 4]
  │    flatten → [B, 192, 32]   （192 = 12 时域块 × 4×4 空间块）
  │
  ├─ MSST-Encoder × 3 组（每组 4 层，共 12 层 Transformer Block）
  │    transformer1 → transformer2 → transformer3
  │
  ├─ 还原 [B, 32, 12, 4, 4] → AdaptiveAvgPool3d(1) → [B, 32]
  └─ MLP(32 → 32 → 1) → BDI-II 标量
```

**超参数（`backend/services/inference.py` 实际加载值）**：
`image_size=(24,128,128)`、`patches=(2,4,4)`、`dim=32`、`num_heads=4`、`num_layers=12`、`dropout=0.1`

### 3.3 三个核心模块（`transformer_layer.py`）

| 模块 | 作用 |
|---|---|
| **MSMHSA**（多尺度多头自注意力） | 用三组 3D 卷积替代线性层生成 Q/K/V：`Q=Conv3×3×3+BN`、`K=Conv2×2×2+BN`（配 CustomPad 补齐）、`V=Conv1×1×1`。不同感受野同时捕捉局部细节与全局依赖；单头内部再把三组局部特征沿通道拼接后 AvgPool 与注意力特征相加，弥补 MHSA 缺失的局部嵌入 |
| **MSSTFF**（多尺度时空前馈网络） | 对通道均值池化后的特征做 1³/2³/3³ 三组 3D 卷积并逐元素相加，再经 Sigmoid 生成门控权重，对原始融合特征加权，抑制背景/光照噪声 |
| **MSGFA**（多尺度全局特征聚合） | 三条带残差的多尺度卷积支路（3³/2³/1³）输出拼接后沿尺度维取均值，输出与注意力分支相加，构成 Block 的 `x = MSGFA(x) + proj(MSMHSA(norm1(x)))` |

### 3.4 训练损失（多任务联合）

```
L_total = α·L_reg + β·L_con + γ·L_sp
  L_reg : Huber 损失（融合 L1/L2 优点，抗离群值）
  L_con : 时空表征对比约束损失（拉近同质样本、推远异质样本）
  L_sp  : 稀疏注意力正则化
```

**消融实验（AVEC2014）**：

| 配置 | MAE | RMSE |
|---|---|---|
| Baseline（标准 Transformer） | 8.85 | 11.24 |
| + CFE 粗粒度特征提取 | 8.52 | 10.65 |
| + MSMHSA | 7.86 | 9.82 |
| + MSSTFF | 7.98 | 10.04 |
| **完整 MSSTformer** | **6.05** | **7.79** |

### 3.5 预处理流水线（工程参数）

| 参数 | 值 | 作用 |
|---|---|---|
| 输入帧率 | 25 fps | 前端/客户端流式抓取频率 |
| 人脸地标 | MTCNN **5 点** | 左眼、右眼、鼻尖、左右嘴角 |
| 对齐方式 | 刚性仿射变换 M | 把双眼映射到 128×128 上的规范位置 |
| 规范眼位 | 左眼 (38,52)、右眼 (90,52) | `services/face_alignment.py` 常量 |
| 参数复用周期 | 每 10 个采样帧重算一次 M | 中间帧直接复用，平摊算力 |
| 输出分辨率 | 128×128 | 送入 MSSTformer |
| 兜底机制 | MTCNN 失败 → 中心裁剪 + 合成热力图 | 保证流水线不中断 |
| 训练增强 | RGB / YUV 双色彩空间直方图均衡 + 自适应光照 | 扩充数据多样性 |
| 归一化 | 减 BGR 均值 `[[[90, 98, 102]]]` | 与训练一致 |
| 张量排布 | (24,128,128,3) → transpose → (3,24,128,128) → unsqueeze(0) | `[1, 3, 24, 128, 128]` |

### 3.6 BDI-II 严重度分级（全系统一致）

| 分数区间 | 枚举值 | 中文标签 | 颜色 |
|---|---|---|---|
| 0 – 13 | `none` | 正常范围 | `#059669`（前端图表色 `#f2f3b2`） |
| 14 – 19 | `mild` | 轻度抑郁 | `#0284c7`（图表色 `#b2f3cd`） |
| 20 – 28 | `moderate` | 中度抑郁 | `#d97706`（图表色 `#b2c3f3`） |
| 29 – 63 | `severe` | 重度抑郁 | `#dc2626`（图表色 `#f3b2bd`） |

---

## 第四部分 · 代码资产地图

```
基于 MSSTformer 与端云协同的轻量化抑郁症智能筛选系统设计/
├── 技术文档.docx / .pdf          ← 21 页技术论文（已提取全文）
├── 答辩ppt.pptx                  ← 5 页（封面 + 3 页整图 + 致谢），内容在 ppt/media/*.png
├── 官方平台资源训练日志.docx       ← 4 张资源监控曲线图（显卡功率/显存/CPU 内存/Token 消耗）
├── 演示视频.mp4（162MB）          ← 系统实机演示
├── 展示图片/
│   ├── 系统登录界面.png / 系统测试界面.png / 统计界面.png
│   ├── 信息导出.png               ← PDF 报告导出效果
│   └── 边缘部署测试.jpg           ← 香橙派/昇腾开发板实物
└── 系统代码/                      ← ★ 工程主体
    ├── index.html / vite.config.ts / package.json / tsconfig*.json
    ├── 启动-仅本机.bat             ← cd backend && python serve_all.py（127.0.0.1:8000）
    ├── 启动-局域网共享.bat         ← HOST=0.0.0.0 python serve_all.py（局域网可访问）
    ├── dist/                      ← 已构建的前端产物（可由 serve_all.py 托管）
    ├── src/                       ← Vue3 前端源码
    ├── backend/                   ← FastAPI 后端 + 模型权重
    │   ├── main.py                ← FastAPI app 装配（5 个 router + /media 静态目录 + /health）
    │   ├── serve_all.py           ← 一体化启动入口（后端 + SPA 兜底路由，同端口免跨域）
    │   ├── config.py              ← ★ 全局配置（帧数/尺寸/模型路径/JWT/LLM 密钥）
    │   ├── database.py / models.py / schemas.py / deps.py / auth_utils.py
    │   ├── face_detect.py         ← 上传图片的 MTCNN 人脸裁剪（覆盖写回原文件）
    │   ├── seed.py                ← 生成演示用假视频 + 素材记录
    │   ├── test_image.py
    │   ├── best.pt                ← ★ 训练好的 MSSTformer 权重（3.96 MB）
    │   ├── depression.db          ← SQLite 数据库
    │   ├── routers/  auth.py · media.py · report.py · upload.py · ws.py
    │   ├── services/ inference.py · face_alignment.py · frame_processor.py · vlm.py · llm.py
    │   ├── media/                 ← 上传的音视频素材
    │   ├── processed/label.csv
    │   └── RGB_/process.py
    └── LMTformer_model/           ← 模型定义（backend/LMTformer_model 为副本）
        ├── LMTformer.py           ← 主网络
        └── transformer_layer.py   ← MSMHSA / MSSTFF / MSGFA / Block
```

---

## 第五部分 · 后端接口契约（★ HarmonyOS 端必须对接）

### 5.1 REST 接口

| 方法 | 路径 | 鉴权 | 请求 | 响应 |
|---|---|---|---|---|
| POST | `/api/auth/register` | 无 | `{username, password, email?}` | `{access_token, token_type:"bearer"}` |
| POST | `/api/auth/login` | 无 | `{username, password}` | `{access_token, token_type:"bearer"}` |
| GET | `/api/auth/me` | Bearer | — | `{id, username, email, created_at}` |
| GET | `/api/media/list` | Bearer | — | `{items:[{id,name,type,thumbnail_url,url,duration,created_at}]}` |
| DELETE | `/api/media/{media_id}` | Bearer | — | `{ok:true}`（同时删除磁盘文件与关联报告） |
| POST | `/api/upload/image` | Bearer | `multipart/form-data`，字段名 **`file`** | `{id, name, type, url}` |
| POST | `/api/analyze` | Bearer | `{id}` | `{task_id}`（**仅回显，真正分析走 WebSocket**） |
| POST | `/api/analyze/face` | Bearer | `{image_base64}` | `{bdi_score, inference_time_ms, heatmap_data:number[][]}` |
| GET | `/api/report/{media_id}` | Bearer | — | `[{id, media_id, bdi_score, severity, detected_at, inference_time_ms, notes}]` |
| GET | `/api/reports` | Bearer | query: `severity, media_type, page, limit` | `{items:[ReportListItem], total}` |
| GET | `/api/stats` | Bearer | — | `{total_analyses, total_media, severity_distribution, avg_inference_time_ms, bdi_trend, recent_reports}` |
| GET | `/media/{filename}` | **无** | — | 静态文件（视频/图片流） |
| GET | `/health` | 无 | — | `{status:"ok"}` |

**鉴权方式**：请求头 `Authorization: Bearer <JWT>`。JWT 载荷 `{sub: "<user_id>", username, exp}`，默认有效期 7 天（`JWT_EXPIRE_MINUTES = 60*24*7`）。

**约束细节**：
- 用户名：3–32 位，仅允许字母、数字、下划线、中文（`^[a-zA-Z0-9_\u4e00-\u9fa5]{3,32}$`）
- 密码：至少 6 位
- 上传允许扩展名：`.jpg .jpeg .png .bmp .mp4 .avi .mov .webm`
- 上传图片后，后端会用 MTCNN 检测人脸并**把上传文件覆盖写回裁剪对齐后的 128×128 人脸图**
- `media_list` 返回的 `url` 是相对路径 `/media/<uuid>.<ext>`，客户端需自行拼接 base URL

### 5.2 WebSocket 实时分析信道（★ 核心）

**连接**：`ws://<host>:<port>/ws/analysis?token=<JWT>`（token 放在 **query 参数**，不是 header）

**握手校验**：服务端从 query 取 `token` → JWT 解码 → 查库校验用户存在且 `is_active`；失败则 `close(code=1008, reason="Unauthorized")`

**完整交互时序**：

```
客户端                                     服务端
  │ ── 建立 WS（?token=xxx） ──────────────▶ │  校验 JWT
  │                                          │
  │ ── 发送 {"id": "<media_id>"} ──────────▶ │  15 秒内未收到则报错断开
  │                                          │  查 MediaAsset → 定位文件
  │ ◀── {"type":"status","message":"analysis_started","task_id":"<id>"}
  │                                          │
  │ ◀── 逐帧推送 AnalysisFrame（JSON）        │  process_media() 逐批推理
  │      （重复 N 次，直到 progress=1）        │
  │                                          │
  │   可选：── {"type":"cancel"} ──────────▶ │  服务端 0.01s 轮询接收，收到即中断
  │                                          │
  │                                          │  落库 DiagnosisReport
  │                                          │  调用 GLM-4.6V 生成解读文本
  │ ◀── {"type":"vlm_analysis","content":"..."} （可能没有，VLM 失败时静默跳过）
  │ ◀── {"type":"done","final_score":<float>}
  │ ◀── 服务端主动 close
```

**帧消息结构（`AnalysisFrame`）**：

```json
{
  "frame_id": 1,
  "timestamp": 1718700000.123,
  "bdi_score": 18.42,
  "aligned_face": "<裸 base64 JPEG，无 data: 前缀>",
  "heatmap_data": [[0.0, ... 16 列 ...], ... 16 行 ...],
  "inference_time_ms": 27.8,
  "progress": 0.0167
}
```

**错误消息**：`{"type":"error","message":"..."}`，可能出现在：未收到 media_id / media_id 缺失 / 素材不存在 / 文件不存在 / 推理异常。

**其他关键点**：
- 前端会每 30 秒发送 `{"type":"ping"}` 作为心跳（服务端不响应，仅用于保活）
- 分析过程中客户端的**前端应用逻辑**：`progress >= 1` 时才把 `analyzing` 置 false
- 图片素材分析：服务端会**人为把同一个结果推送 10 次**（每次间隔 0.2 秒），让曲线"看起来是流式的"
- 视频素材分析：每 24 个采样帧为一个 batch 一次性推 24 条消息（`await asyncio.sleep(0)` 让出事件循环）
- 图片路径的进度 = `i/10`；视频路径的进度 = `(start_id+i) / (总帧数/采样间隔)`

### 5.3 数据模型

```sql
users(id INTEGER PK, username VARCHAR(64) UNIQUE, email VARCHAR(128) UNIQUE,
      hashed_password VARCHAR(256), is_active BOOL, created_at DATETIME)

media_assets(id INTEGER PK, name VARCHAR(256), file_path VARCHAR(512),
             type ENUM('video','image'), thumbnail_url VARCHAR(512),
             duration INTEGER NULL, created_at DATETIME)

diagnosis_reports(id INTEGER PK, media_id FK→media_assets.id,
                  bdi_score FLOAT, severity ENUM('none','mild','moderate','severe'),
                  detected_at DATETIME, inference_time_ms FLOAT, notes TEXT NULL)
```

> ⚠️ 技术文档 4.2 节描述的表结构（含 `report_id`、`user_id`、`vlm_analysis` 字段）与实际代码**不一致**——实际代码只有上述三张表，且没有落库 VLM 文本、没有 `user_id` 外键。**以代码为准。**

---

## 第六部分 · Web 前端功能清单（→ HarmonyOS 页面映射依据）

### 6.1 路由与页面（共 3 个）

| 路由 | 页面 | 说明 |
|---|---|---|
| `/login` | `LoginView.vue` | 登录 / 注册双模式。左侧品牌区（4 条特性介绍 + 合规声明），右侧表单区。**移动端/窄屏（≤900px）隐藏品牌区** |
| `/` | `StatsView.vue` | 数据统计概览：4 张 KPI 卡 + 严重度环形图 + BDI 日均趋势折线图 + 模型算力信息卡 + 最近分析记录表 |
| `/analysis` | `AnalysisView.vue` | 智能分析工作台：**左栏**（素材库 + 关键人脸帧）/ **中栏**（主监控视频播放器 + 注意力热力图 + BDI 曲线）/ **右栏**（诊断报告 / 云端推理 / 历史记录 三 Tab） |

路由守卫：无 token 则跳 `/login?redirect=<原路径>`；已登录访问 `/login` 则跳 `/`。

### 6.2 组件级功能清单

**布局层**
| 组件 | 功能 | 关键中文文案 |
|---|---|---|
| `DashboardHeader.vue` | 顶部栏：Logo + 标题 + 导航 + 受试者录入按钮 + "加载演示数据" + WS 状态徽标 + 用户名 + 实时时钟 + 退出 | 标题「抑郁症智能辅助诊断系统」、副标题「基于 BDI-II · MSSTformer 多模态分析」、导航「统计概览 / 智能分析」、按钮「录入受试者 / 加载演示数据 / 退出」 |
| `AnalysisStatusBar.vue` | 分析状态条：BDI-II 分值 / 严重度 / 推理耗时 / 分析帧数 / WS 连接状态 / 「分析进行中」脉冲指示 | 芯片标签「BDI-II / 严重度 / 推理耗时 / 分析帧数」、状态「服务已连接 / 连接中 / 服务未连接 / 分析进行中」 |

**左栏**
| 组件 | 功能 | 关键文案 |
|---|---|---|
| `MediaLibrary.vue` | 素材库：视频/图片两个 Tab（`el-tabs type="border-card"`），2 列网格缩略图，右上角删除按钮（二次确认），标题右侧上传按钮。**素材列表为空时自动加载演示数据** | 标题「评估素材库」、Tab「视频素材 / 图片素材」、按钮「上传」、空态「暂无视频素材 / 暂无图片素材」、删除确认「确定删除「{name}」吗？删除后不可恢复。」 |
| `FaceFrameGallery.vue` | 关键人脸帧画廊：视频分析过程中累积的人脸缩略图（含 `#帧号 · 分数` 角标），可选中后点「单帧检测」调用 `/api/analyze/face`；支持折叠（localStorage 记忆）；最多保留 48 帧 | 标题「关键人脸帧」、按钮「单帧检测 / 清空」、徽标「检测中」、说明「视频分析中会累积关键帧。对视频帧做「单帧检测」会结束流式分析并切到主界面的抽帧图片结果。」、空态「分析后将显示人脸帧」 |

**中栏**
| 组件 | 功能 | 关键文案 |
|---|---|---|
| `MainVideoPlayer.vue` | 主监控画面。四种采集入口：**选择本地视频 / 选择本地图片 / 在线拍照 / 在线录制**。在线拍照用 `getUserMedia` + Canvas 截帧 → JPEG 上传；在线录制用 `MediaRecorder`（优先 vp9/vp8 webm）→ 停止后上传。播放器支持 `controls autoplay muted loop` | 标题「主监控画面」、占位标题「开始评估采集」、占位说明「上传本地视频或图片，或使用在线拍照 / 录制」、按钮「选择本地视频 / 选择本地图片 / 在线拍照 / 在线录制 / 拍照并分析 / 开始录制 / 停止并完成 / 返回」、录制提示「开始录制后，点击「停止并完成」将视频保存到素材库并自动开始分析。」、录制指示「● 录制中」、分析指示「● 分析中」 |
| `FacePreview.vue` | 注意力热力图：Canvas 200×200 绘制对齐人脸 + 叠加 16×16 热力图（`globalAlpha=0.4`）+ 4 个解剖区域虚线标注框（眶周×2 / 口周 / 眉间）+ 由蓝到红的色带图例。下方自动计算 **Top-3 注意力热点**并翻译为解剖学区域名 | 标题「注意力热力图」（副标题 MSSTformer）、色带「低 / 高」、占位「等待模型推理...」、解读「重点关注 {区域}（{百分比}%），其次 {区域}（{百分比}%）」、区域词表「眉间/前额区域、眶周区域（眼轮匝肌）、口周区域（降口角肌）、鼻唇沟区域、面部中央区域」 |
| `EmotionCurve.vue` | BDI-II 实时评分曲线：ECharts 折线 + 面积填充，y 轴固定 0–63、interval 13，每个数据点按严重度着色，底部 4 色区间图例 | 标题「BDI-II 评分曲线」、空态「上传素材后将实时显示评分曲线」、图例「正常 0-13 / 轻度 14-19 / 中度 20-28 / 重度 29-63」 |

**右栏（三 Tab）**
| 组件 | 功能 | 关键文案 |
|---|---|---|
| `RightPanel.vue` | 容器，3 个 Tab | 「诊断报告 / 云端推理 / 历史记录」 |
| `DiagnosisReport.vue` | 诊断报告主面板：① 顶部**法律免责声明**；② 受试者信息条（编号/性别/年龄段/评估日）；③ **BDI-II 总评分大字卡**（带数字滚动动画 + 严重度标签 + 推理耗时）；④ 分析进度条；⑤ 三个可折叠区块（BDI-II 维度估计 / 临床干预建议 / 多模态面部分析）；⑥ 「导出 PDF 报告」按钮 | 见 7.3 节完整文案 |
| `CloudTopology.vue` | 云端推理状态：ECharts 力导向关系图（终端设备 → LMTformer 推理节点 → 结果输出）+ 流程文字条 + 5 项实时统计 | 标题「云端推理状态」、流程「终端采集 → LMTformer 推理 → BDI 评分输出」、统计项「批次推理耗时 / 帧序进度 / 当前 BDI 评分 / WebSocket 连接 / 分析状态」、值「已连接 / 连接中... / 未连接 / 进行中 / 空闲」 |
| `HistoryPanel.vue` | 历史记录：表格（复选框 / 素材 / BDI / 等级 / 时间），**勾选恰好 2 条后可点「对比分析」**打开对比弹窗 | 标题「历史分析记录」、表头「素材 / BDI / 等级 / 时间」、按钮「对比分析」、空态「暂无分析记录」、计数「共 N 条」 |
| `ComparisonModal.vue` | 双报告对比弹窗：左右两列大分数 + 中间 delta 差值（`+x.x`/`-x.x`，下降为绿色表示好转） | 标题「诊断报告对比」、列头「报告 A / 报告 B」、中间「评分变化」、空态「请选择两条记录进行对比」、文案「推理耗时 x ms」 |

**统计页组件**
| 组件 | 功能 |
|---|---|
| `StatCard.vue` | 通用 KPI 卡（标题/副标题/数值/图标/强调色） |
| `ModelMetricsCard.vue` | MSSTformer 算力信息卡 ⚠️ **数值与实际不符**：UI 写 0.12M / 0.35G / 25ms，实际为 0.95M / 1.1G / 28.2ms —— 移植时应更正 |
| `SeverityPieChart.vue` | 严重度分布环形图（radius `['55%','80%']`，中心叠加总例数文字） |
| `BdiTrendChart.vue` | BDI 日均趋势折线（smooth + areaStyle + y=13/19/28 三条虚线 markLine） |
| `RecentReportsTable.vue` | 最近 10 条分析记录表（图标区分视频/图片） |

**通用组件**
| 组件 | 功能 |
|---|---|
| `PatientInfoDialog.vue` | 受试者信息录入弹窗：受试者编号（必填）、性别（男/女，必填）、年龄段（18–25/26–35/36–45/46–55/56–65/65+，必填）、评估日期（默认今天）；带「随机填充」按钮 |
| `GlowProgress.vue` | 渐变发光进度条（teal→cyan），`width` 过渡 0.4s |
| `ScoreCounter.vue` | 数字滚动动画计数器（`requestAnimationFrame` + easeOutCubic，默认 800ms） |
| `StatusBadge.vue` | WebSocket 状态徽标（圆点 + 文字：已连接 / 连接中 / 已断开） |

### 6.3 状态管理（Pinia）

| Store | 关键状态 | 关键动作 |
|---|---|---|
| `auth` | `token, user, loading, isAuthenticated` | `login / register / logout / loadUser / initFromStorage`（token 持久化到 `localStorage['depression_auth_token']`） |
| `dashboard` | `mediaList, selectedMediaId, analyzing, currentFrame, bdiHistory[], faceImageData, heatmapData, inferenceTimeMs, analysisProgress, wsConnected, isDemo, vlmAnalysis, patientInfo, faceFrameHistory[], localVideoUrl, singleFaceImageMode/Url/Label, ignoreIncomingWsFrames`；计算属性 `currentScore / severity / severityLabel / severityColor / suggestion` | `loadMediaList / removeMedia / startAnalysis / uploadAndAnalyze / handleWsMessage / handleFrame / reset / setPatientInfo / clearFaceFrameHistory / applySingleFrameAnalysisResult / switchVideoAnalysisToSingleFaceImage / setLocalVideo / loadDemoData / startDemoAnalysis / stopDemoAnalysis` |
| `stats` | `loading, error, data` | `load()` |

**业务常量**（`stores/dashboard.ts`，HarmonyOS 端需逐条复刻）：
```ts
getSeverity(score)  // ≤13 none / ≤19 mild / ≤28 moderate / else severe
severityLabels     // none:「正常范围」 mild:「轻度抑郁」 moderate:「中度抑郁」 severe:「重度抑郁」
severityColors     // none:#f2f3b2  mild:#b2f3cd  moderate:#b2c3f3  severe:#f3b2bd
severitySuggestions// 四级一句话建议（见 7.3）
```

### 6.4 PDF 报告导出逻辑（`usePdfExport.ts`）

1. 用 `echarts.getInstanceByDom(el).getDataURL({type:'png', pixelRatio:2})` 抓取 BDI 曲线图；
2. `buildReportHtml()` 拼装一个 794px 宽的离屏 `div`（A4 210mm 宽度在 794px@96dpi 下的等效宽度）；
3. `html2canvas(wrapper, {scale:2, backgroundColor:'#ffffff', windowWidth:794})` 整体截图；
4. `jsPDF('p','mm','a4')`，页边距 14mm，内容宽 182mm；
5. 若截图高度 ≤ A4 可用高度则单页 `addImage`；否则按可用高度**纵向切片分页**（逐片 drawImage → toDataURL('image/jpeg', 0.92) → addImage）；
6. `pdf.save('depression_report_YYYYMMDD_HHmmss.pdf')`。

**报告内容顺序**：页眉（品牌 + 日期 + 素材名）→ **顶部法律免责声明（黄色警示框）** → 受试者信息块 → 评估结果大字卡 → 简要说明 → BDI 曲线图 → BDI-II 维度估计（3 条进度条）→ 临床干预建议（列表 + 随访 + 指南）→ 多模态面部分析（VLM 分节）→ 页脚（免责声明 + 生成说明）。

---

## 第七部分 · 设计系统（HarmonyOS 端视觉复刻规范）

### 7.1 主题色与变量（`src/style.css`）

整体风格：**清新浅色医疗风**，主色"天青 + 薄荷绿"，白色卡片 + 淡青边框 + 柔和阴影，**不是深色科技风**。

| 类别 | 变量 | 值 |
|---|---|---|
| 背景 | `--bg-primary` | `#eef6fb` |
| | `--bg-secondary` / `--bg-card` / `--bg-elevated` | `#ffffff` |
| | `--bg-card-hover` | `#f5fbff` |
| | `--bg-inset` | `#f1f5f9` |
| | `--bg-muted` | `#e8f4f8` |
| 边框 | `--border-color` | `rgba(14,165,233,0.14)` |
| | `--border-active` | `rgba(13,148,136,0.45)` |
| | `--border-subtle` | `rgba(148,163,184,0.18)` |
| 品牌色 | `--accent-primary` | `#0d9488`（天青绿，主按钮/强调） |
| | `--accent-cyan` | `#0891b2` |
| | `--accent-blue` | `#0284c7` |
| | `--accent-teal` | `#14b8a6` |
| | `--accent-mint` | `#2dd4bf` |
| | `--accent-violet` | `#6366f1` |
| | `--accent-yellow` | `#f59e0b` |
| | `--accent-red` | `#ef4444` |
| 严重度 | `--severity-none` | `#059669` |
| | `--severity-mild` | `#0284c7` |
| | `--severity-moderate` | `#d97706` |
| | `--severity-severe` | `#dc2626` |
| 文字 | `--text-primary` | `#1e3a5f`（深蓝灰，非纯黑） |
| | `--text-secondary` | `#475569` |
| | `--text-muted` | `#94a3b8` |
| | `--text-label` | `#64748b` |
| 图表 | `--chart-axis` | `#94a3b8` |
| | `--chart-split` | `rgba(148,163,184,0.25)` |
| | `--chart-line` | `#0891b2` |
| | `--chart-area` | `rgba(8,145,178,0.12)` |
| 阴影 | `--shadow-sm` | `0 1px 2px rgba(14,116,144,0.06)` |
| | `--shadow-card` | `0 1px 3px rgba(14,116,144,0.08), 0 4px 12px rgba(14,116,144,0.05)` |
| | `--shadow-card-hover` | `0 4px 16px rgba(14,116,144,0.12)` |
| 圆角 | `--radius-sm / card / lg` | `8px / 12px / 16px` |
| 布局 | `--header-height` | `56px` |
| | `--sidebar-width` | `248px` |
| | `--report-width` | `400px` |
| | `--content-gap` | `12px` |
| | `--page-padding` | `16px` |
| 字体 | `--font-sans` | `'PingFang SC','Microsoft YaHei','SF Pro Display',sans-serif` |
| | `--font-mono` | `'JetBrains Mono','Fira Code',monospace`（数字统一用等宽） |
| 动效 | `--ease-out-expo` | `cubic-bezier(0.16, 1, 0.3, 1)` |

**全局背景**：`linear-gradient(145deg, #eef6fb 0%, #e6f4f1 45%, #edf5ff 100%)` + 三层径向光晕
（左上薄荷 `rgba(45,212,191,0.12)`、右下天青 `rgba(14,165,233,0.1)`、中心白光 `rgba(255,255,255,0.6)`）

**关键复用样式类**（HarmonyOS 端建议做成公共 `@Styles` / 组件）：
- `.glass-card`：白底 + 1px 淡青边 + 卡片阴影 + 12px 圆角 + `fadeInUp .28s` 入场动画 + hover 边框/阴影变化
- `.section-title`：13px/600 + 左侧 3×14px 的 teal→cyan 渐变竖条（`::before`）
- `.clinical-disclaimer`：浅黄底 `#fffbeb` + 琥珀边框 + `#78350f` 文字
- `.mono-num`：等宽数字 + `tnum` 特性
- `.status-dot`：7px 圆点，connected `#10b981` / disconnected `#ef4444` / connecting `#f59e0b`（呼吸动画）
- 滚动条：6px 宽，`rgba(13,148,136,0.22)` 拇指

**动画关键帧**：`fadeInUp`（6px 上移淡入）、`breathe`（透明度 0.45↔1）、`pulse-dot`（缩放 1↔1.15）、`pulse-soft`（透明度 1↔0.55）

**热力图色带**：`heatColor(t)` 采用蓝→青→绿→黄→红的五段映射，CSS 图例 `linear-gradient(to right, #0000ff, #00ffff, #00ff00, #ffff00, #ff0000)`
**注意力区域标注色**：眶周 `rgba(0,230,180,0.5)`、口周 `rgba(77,138,240,0.5)`、眉间 `rgba(240,160,40,0.5)`

### 7.2 VLM 大模型输出格式（客户端需要按 `【】` 分节解析）

**图片模式 prompt 要求输出**：`【量表总分】【抑郁程度判定】【面部特征抑郁推理依据】【抑郁情绪缓解建议】`
**视频模式 prompt 要求输出**：`【量表总分】【抑郁程度判定】【面部特征动态变化】【面部特征抑郁推理依据】【抑郁情绪缓解建议】`

前端解析逻辑：正则 `/【(.+?)】\s*/g` 全局匹配，把 `【标题】` 之间的文本作为上一节的内容 → 渲染为"多模态面部分析"折叠区里的分节卡片。
**HarmonyOS 端必须实现同样的解析器**（正则 → `Array<{title, content}>`）。

### 7.3 需要逐字复刻的临床文案

**法律免责合规技术声明**（出现在报告顶部 + PDF 顶部 + PDF 页脚）：
> 本报告仅作为人工智能技术驱动的心理健康辅助筛查结果，不能作为替代精神科临床医生核心病理确诊与处方开具的唯一医学诊断依据。

**四级严重度一句话建议**（`severitySuggestions`）：
| 等级 | 建议文案 |
|---|---|
| none | 当前情绪状态良好，建议保持健康的生活作息和社交活动。 |
| mild | 建议结构化心理治疗（CBT/IPT），结合运动处方和正念训练。 |
| moderate | 建议 CBT 联合 SSRI 药物治疗，强化随访频率，评估自杀风险。 |
| severe | 建议立即转诊精神专科，考虑 SNRI/augmented 方案或 ECT/rTMS。 |

**四级临床干预建议**（`DiagnosisReport.vue` treatmentPlan）：
- **一级干预**（none）：保持规律作息，每周 ≥150 分钟中等强度运动／维持社交活动频率，建议每周至少 2 次线下社交／正念冥想训练，每日 10–15 分钟。随访：建议每 3 个月使用 PHQ-9 自评量表随访。指南：APA 实践指南 (2019) · NICE CG90 · 中国抑郁障碍防治指南 (第二版)
- **二级干预**（mild）：结构化心理治疗（CBT 或 IPT），每周 1 次 × 8–12 周／行为激活疗法（BA）／运动处方每周 3 次／互联网 CBT（iCBT）辅助。随访：每 2–4 周使用 BDI-II 或 HAM-D 评估疗效。指南：APA (2019) — 推荐等级 1A · NICE CG90 · CANMAT 2016
- **三级干预**（moderate）：CBT + SSRI 联合治疗（有效率 60–70%）／SSRI 一线：舍曲林 50–200 mg/d 或艾司西酞普兰 10–20 mg/d／心理治疗频次提升至每周 2 次持续 ≥12 周／评估自杀风险（C-SSRS），建立安全计划／必要时转诊精神专科调整用药。随访：每 1–2 周随访，第 4 周评估药物应答，第 8 周评估缓解
- **四级干预（紧急）**（severe）：立即转诊精神专科医疗机构综合评估／考虑 SNRI 或 augmented 方案／每周 ≥2 次高强度心理治疗（CBT/DBT）／评估 ECT 或 rTMS 适应证／建立 24 小时紧急联系人机制，移除自杀工具。随访：每周至少 1 次门诊随访，必要时住院

**BDI-II 维度估算公式**（模型推算，非真实量表分项）：
```
认知-情感维度 = round(总分 × 0.48)   / 满分 30
躯体症状维度 = round(总分 × 0.35)   / 满分 22
行为表现维度 = 总分 - 认知 - 躯体   / 满分 11
```

---

## 第八部分 · HarmonyOS 端构建方案

### 8.0 先明确一个好消息：**客户端不需要跑模型**

从代码可以确认，**当前架构下所有计算都在服务端**：
- 客户端只负责：**采集（拍照/录像/选文件）→ 上传原文件 → 建立 WebSocket → 展示服务端回传的分数/人脸图/热力图 → 渲染报告**
- 视频解码、MTCNN 人脸检测、仿射对齐、MSSTformer 推理、VLM 调用**全部在 Python 后端**

技术文档里的"端侧推理/边缘 NPU 部署"指的是 **香橙派 Orange Pi AIpro / 昇腾 NPU 这类边缘服务器**，不是手机客户端。

这意味着 HarmonyOS 端的工程量集中在 **UI 复刻 + 相机采集 + WebSocket 长连接 + Canvas 热力图 + 报告导出**，不涉及 NPU 模型移植。**这是本任务最重要的判断。**

### 8.1 三条可行路线（建议 A 为主 + B 兜底）

| 方案 | 做法 | 工期估算 | 优点 | 缺点 |
|---|---|---|---|---|
| **A · 原生 ArkTS/ArkUI 重写**（推荐） | 用 ArkTS 声明式 UI 完整重写 3 个页面与全部组件，直连后端 REST + WebSocket | 3–5 周 | 技术含量高、答辩加分、性能与体验好、可调用原生相机/录音 | 工作量大，图表/PDF 需自研 |
| **B · ArkUI Web 组件内嵌 dist** | 把 `系统代码/dist/` 打包进 `resources/rawfile/`，用 `Web({src: $rawfile('index.html')})` 加载，通过 `javaScriptProxy` 桥接相机等原生能力 | 1–3 天 | 出成品极快、视觉 100% 一致、风险最低 | 技术含量低，答辩容易被质疑"只是套壳" |
| **C · 混合** | 原生页面 + 关键模块（如报告页/图表）用 Web 组件 | 1–2 周 | 平衡 | 架构复杂度上升 |

> **建议**：以方案 A 为主线开发，**先用方案 B 在 1 天内做出一个能跑的 demo 作为保底**（比赛演示不至于开天窗），再用 A 逐步替换页面。这也符合"答辩时能讲、演示时不慌"的策略。

### 8.2 工程结构（方案 A）

```
DepressionHarmonyOS/                    ← DevEco Studio 工程根
├── AppScope/
│   ├── app.json5                       ← bundleName / versionCode / icon / label
│   └── resources/base/element/string.json
├── entry/                              ← 主 HAP 模块
│   ├── src/main/
│   │   ├── module.json5                ← 权限声明 / ability 注册 / 网络配置引用
│   │   ├── ets/
│   │   │   ├── entryability/EntryAbility.ets
│   │   │   ├── common/
│   │   │   │   ├── Theme.ets            ← ★ 第七部分全部色值/圆角/间距常量
│   │   │   │   ├── Constants.ets        ← 严重度阈值/标签/颜色/建议/干预文案
│   │   │   │   ├── ApiConfig.ets        ← baseUrl / wsUrl（可在设置页修改）
│   │   │   │   └── Logger.ets
│   │   │   ├── model/                   ← ★ 与后端 schema 一一对应的 interface
│   │   │   │   ├── AuthModel.ets        ← TokenResponse / AuthUser
│   │   │   │   ├── MediaModel.ets       ← MediaItem
│   │   │   │   ├── FrameModel.ets       ← AnalysisFrame / WsMessage 联合类型
│   │   │   │   ├── ReportModel.ets      ← ReportListItem / StatsData
│   │   │   │   └── PatientInfo.ets
│   │   │   ├── network/
│   │   │   │   ├── HttpClient.ets       ← 封装 @ohos.net.http + Bearer 注入 + 401 处理
│   │   │   │   ├── AuthApi.ets
│   │   │   │   ├── MediaApi.ets
│   │   │   │   ├── ReportApi.ets
│   │   │   │   ├── UploadApi.ets        ← multipart 上传（@ohos.request 或手搓 body）
│   │   │   │   └── AnalysisSocket.ets   ← ★ WebSocket 封装（心跳/重连/消息分发）
│   │   │   ├── store/                   ← AppStorage / @ObservedV2 + @Trace 或 V2 状态管理
│   │   │   │   ├── AuthStore.ets
│   │   │   │   ├── DashboardStore.ets   ← ★ 对应 Pinia dashboard store
│   │   │   │   └── StatsStore.ets
│   │   │   ├── util/
│   │   │   │   ├── Base64Util.ets       ← base64 ↔ PixelMap
│   │   │   │   ├── HeatmapUtil.ets      ← ★ heatColor + Top-3 热点→解剖区域 映射
│   │   │   │   ├── VlmParser.ets        ← ★ 【】分节正则解析
│   │   │   │   ├── SubScaleUtil.ets     ← BDI 三维度估算
│   │   │   │   ├── TreatmentPlan.ets    ← 四级干预文案
│   │   │   │   ├── PdfExporter.ets      ← 报告导出
│   │   │   │   └── Preferences.ets      ← 替代 localStorage
│   │   │   ├── components/
│   │   │   │   ├── common/  GlassCard · SectionTitle · StatusDot · GlowProgress ·
│   │   │   │   │            ScoreCounter · ClinicalDisclaimer · StatusBadge
│   │   │   │   ├── chart/   BdiLineChart · SeverityRingChart · BdiTrendChart
│   │   │   │   ├── analysis/ MediaLibrary · FaceFrameGallery · CameraPanel ·
│   │   │   │   │            FaceHeatmapView · DiagnosisReport · CloudStatus ·
│   │   │   │   │            HistoryList · ComparisonSheet · PatientInfoSheet
│   │   │   │   └── stats/   StatCard · ModelMetricsCard · RecentReportsList
│   │   │   └── pages/
│   │   │       ├── LoginPage.ets
│   │   │       ├── IndexPage.ets        ← Tabs: 统计概览 / 智能分析（替代顶部导航）
│   │   │       ├── StatsPage.ets
│   │   │       └── AnalysisPage.ets
│   │   └── resources/
│   │       ├── base/element/            ← color.json / string.json / float.json
│   │       ├── base/media/              ← 图标、logo
│   │       └── base/profile/
│   │           └── network_config.json  ← ★ 允许明文 HTTP（见 8.4）
│   └── build-profile.json5
└── build-profile.json5 / hvigorfile.ts / oh-package.json5
```

### 8.3 关键技术映射表（Web → HarmonyOS）

| Web 能力 | 现用实现 | HarmonyOS 对应方案 | 备注 |
|---|---|---|---|
| 声明式 UI | Vue 3 SFC | **ArkTS + ArkUI 声明式**（`@Component` / `@State` / `@Prop` / `@Link` / `@Builder`） | 组件粒度可 1:1 对应 |
| 路由 | `vue-router` `createWebHistory` | **`Navigation` + `NavPathStack`**（推荐）或 `router` | 用 Navigation 更现代 |
| 底部/顶部导航 | `DashboardHeader` 顶部导航 | **`Tabs`**（底部 Tab：统计概览 / 智能分析）+ 自定义顶部栏 | 移动端改造点 |
| 状态管理 | Pinia | `AppStorage` / `LocalStorage` 或 **状态管理 V2（`@ObservedV2` + `@Trace`）** | 单例 Store 用 class + static |
| HTTP | `fetch` + Bearer header | **`@ohos.net.http`** (`http.createHttp().request()`) | 支持 `method: http.RequestMethod.POST`、`header`、`extraData` |
| 文件上传 (multipart) | `FormData` + `fetch` | **`@ohos.request` 的 `uploadFile`**（文件需先落到应用沙箱 `cacheDir`）或手写 multipart body 走 `http.request` | 字段名必须为 **`file`** |
| WebSocket | 浏览器原生 `WebSocket` | **`@ohos.net.webSocket`** (`webSocket.createWebSocket()`) → `connect / on('open'|'message'|'close'|'error') / send / close` | token 放**查询参数** |
| base64 → 图片 | `<img src="data:image/jpeg;base64,...">` | `util.Base64Helper` 解码 → `ArrayBuffer` → **`image.createImageSource(buf).createPixelMap()`** → `Image(pixelMap)` | 服务端发的是**裸 base64 JPEG** |
| Canvas 热力图 | `CanvasRenderingContext2D` | **ArkUI `Canvas` + `CanvasRenderingContext2D`**（API 基本一致：`globalAlpha` / `fillRect` / `drawImage`） | 可直接照搬绘制逻辑 |
| 图表 | ECharts 6 | **`@ohos/mpchart`**（OpenHarmony 三方库，移植自 MPAndroidChart）或**自绘 Canvas 折线/环形图** | 若追求视觉 100% 一致，建议自绘 Canvas |
| 摄像头预览 | `getUserMedia` + `<video>` | **CameraKit（`@ohos.multimedia.camera`）+ `XComponent` 预览** | 需 CAMERA 权限 |
| 拍照 | Canvas 截帧 → JPEG | **`camera.PhotoOutput` + `photoCapture`** 或 `XComponent` 截屏 | 输出 JPEG 文件 |
| 录像 | `MediaRecorder`（webm） | **AVRecorder（`@ohos.multimedia.media`）输出 MP4** + CameraKit `VideoOutput` | 服务端允许 `.mp4/.webm` |
| 本地文件选择 | `<input type="file">` | **`photoAccessHelper.PhotoViewPicker`**（图片/视频，免权限）或 `picker.DocumentViewPicker` | 免 READ_MEDIA 权限 |
| 素材保存到相册 | — | **`photoAccessHelper` 安全控件保存** `photoAccessHelper.MediaAssetChangeRequest` | 可选功能 |
| localStorage | `localStorage` | **`@ohos.data.preferences`**（KV，如 token、人脸帧折叠状态、服务器地址） | token 也可用 `@ohos.security.asset` 加密存储 |
| PDF 导出 | html2canvas + jsPDF | ① **`@kit.PDFKit` 的 `pdfService`**（创建/编辑 PDF，需核对当前 SDK 是否含，或② 用 Canvas 绘制报告页 → 导出图片 → 保存到相册，或③ **PrintKit 打印服务**生成 PDF | ⚠️ 三方可行性需先用最小 demo 验证，见 8.6 |
| 系统提示 | `ElMessage` / `ElMessageBox` | **`promptAction.showToast()`** / **`AlertDialog.show()`** | 一一对应 |
| 对话框 | `el-dialog` | **`CustomDialogController` + `@CustomDialog`** 或 `bindSheet`（半模态） | 移动端更适合 bindSheet |
| 折叠面板 | `el-collapse` | `Column` + `@State expanded` + 条件渲染 + 动画 | 简单自研 |
| 表格 | `el-table` | **`List` + 自定义行**（移动端建议改卡片列表） | 表格在手机上体验差 |
| Tabs | `el-tabs` | **`Tabs` + `TabContent`** | 直接对应 |

### 8.4 权限与网络配置

`entry/src/main/module.json5` 需声明：

```
ohos.permission.INTERNET              ← 网络（REST + WebSocket）
ohos.permission.GET_NETWORK_INFO      ← 网络状态（WS 重连判断）
ohos.permission.CAMERA                ← 在线拍照 / 在线录制
ohos.permission.MICROPHONE            ← 录像需要音频（若不需要音频可不申请）
ohos.permission.WRITE_IMAGEVIDEO      ← 保存录像/照片到相册（若走安全控件则不需要）
```

**★ 明文 HTTP 是关键坑**：项目后端是 `http://<局域网IP>:8000`，**没有 HTTPS**。HarmonyOS 默认禁止明文 HTTP 流量，必须在 `module.json5` 中通过 `metadata` 引用一份 `network_config.json`（`resources/base/profile/network_config.json`），把后端 IP/域名加入 `cleartextTrafficPermitted: true` 的白名单。
> 具体字段名与写法请以当前 SDK 版本的官方文档为准核对一次（不同 API 版本配置位置略有差异）。**如果这一步没做对，App 会表现为"网络请求全部失败但看不出原因"，是首次联调最容易卡住的地方。**

**WebSocket 也要注意**：`ws://` 同属明文，需要放在同一份网络配置的允许范围内。

### 8.5 移动端 UI 改造要点（Web 是横屏三栏，手机是竖屏）

Web 端 `AnalysisView` 是 `248px | 1fr | 400px` 的三栏横屏布局，**直接搬到手机上会不可用**。建议改造为：

```
┌──────────────────────────────┐
│  顶部栏：标题 + WS 状态点 + 用户  │
├──────────────────────────────┤
│  分析状态条（BDI/严重度/耗时/帧数）│
├──────────────────────────────┤
│                              │
│   主监控画面区（视频/图片预览）    │
│   + 采集按钮组（拍照/录像/选文件） │
│                              │
├──────────────────────────────┤
│  注意力热力图  |  BDI 实时曲线    │  ← 左右并排两张小卡
├──────────────────────────────┤
│  Tabs: 诊断报告 | 云端推理 | 历史  │
│  （内容可滚动）                  │
└──────────────────────────────┘
底部 TabBar: 统计概览 | 智能分析
```

- 关键人脸帧画廊 → 改为**横向滚动的缩略图条**（原 Web 端已支持 `layout="compact"` 横向模式，可直接照搬）
- 素材库 → 改为**抽屉/半模态面板**（`bindSheet`）从底部弹出，而不是常驻左栏
- 受试者信息录入 → `bindSheet` 或 `CustomDialog`
- 对比弹窗 → `bindSheet` 全宽
- 表格 → 卡片列表

### 8.6 需求确认清单（开工前必须先钉死）

| # | 待确认项 | 影响 | 建议默认取值 |
|---|---|---|---|
| 1 | 目标 HarmonyOS 版本 / API 等级 | 决定可用 API（如 PDFKit、状态管理 V2） | **HarmonyOS NEXT (API 12+)**，纯 ArkTS |
| 2 | 是否已有 DevEco Studio + 华为开发者账号 + 真机 | 无真机无法验证相机/WebSocket | 需真机（模拟器不支持摄像头） |
| 3 | 后端部署地址 | 决定 baseUrl 与明文 HTTP 白名单 | 局域网 `http://192.168.x.x:8000`；建议做成**可在设置页里改**并持久化 |
| 4 | PDF 导出是否必须 | 若必须，需先做 PDFKit 可行性验证 | 先做"报告导出为长图存相册"作为降级方案 |
| 5 | 图表是否必须视觉 100% 一致 | 影响是否引入三方图表库 | 自绘 Canvas（可控性最高） |
| 6 | 是否需要离线演示模式 | 比赛现场断网保险 | **强烈建议做**：移植 Web 端 `loadDemoData` + `startDemoAnalysis`，用本地定时器产假数据 |
| 7 | 是否需要端侧推理（NPU） | 工程量级差异巨大 | 本阶段**不做**，答辩时讲"已在昇腾边缘板验证"即可 |

### 8.7 建议里程碑计划

| 阶段 | 目标 | 交付物 | 验收标准 |
|---|---|---|---|
| **M0 · 环境**（1–2 天） | DevEco Studio 跑通 Hello World；后端 `启动-局域网共享.bat` 起来；手机能访问 `http://<PC_IP>:8000` 看到 Web 端 | 空工程 + 网络连通 | 手机上浏览器能打开并登录系统 |
| **M1 · 网络层**（2–3 天） | 打通明文 HTTP；实现 `HttpClient` + 登录/注册/me；token 存 preferences | `HttpClient.ets` `AuthApi.ets` | App 内能完成登录并保持登录态 |
| **M2 · 素材 + 上传**（3–4 天） | `PhotoViewPicker` 选图/选视频；拍照（CameraKit）；录像（AVRecorder）；上传到 `/api/upload/image`；素材列表页 | `CameraPanel` `MediaLibrary` | 拍照后能在素材列表看到，且服务端 `media/` 目录出现人脸裁剪图 |
| **M3 · WebSocket 实时分析**（4–5 天） | WS 建连（token 查询参数）、发 `{id}`、解析帧、断线重连、发送 `cancel` | `AnalysisSocket.ets` | 点素材能跑完一次完整分析，`progress` 到 1 后收到 `done` |
| **M4 · 可视化**（4–5 天） | Canvas 热力图（叠加 + 色带 + 区域框 + Top-3 热点解读）、BDI 实时曲线、状态条 | `FaceHeatmapView` `BdiLineChart` | 与 Web 端截图肉眼对比基本一致 |
| **M5 · 报告与统计**（4–5 天） | 诊断报告页（免责声明/受试者/大字分/三维度/四级干预/VLM 分节）、统计页（4 KPI + 环形图 + 趋势图 + 记录表）、历史 + 对比 | `DiagnosisReport` `StatsPage` `HistoryList` `ComparisonSheet` | 报告内容与 PDF 版式要素齐全 |
| **M6 · 导出 + 打磨**（3–5 天） | PDF/长图导出；离线演示模式；异常提示；空态；加载态；华为风格规范自检 | 可安装 `.hap` | 断网也能完整演示一遍 |

**总计约 4–5 周**（单人）。若并行或砍掉 PDF 原生导出，可压到 3 周。

### 8.8 移植时必须注意的"坑"（源码审查发现）

1. **命名不统一**：模型类名是 `LMTformer`，论文/UI 里叫 `MSSTformer`；PDF 报告页眉又写"LMTformer 多模态 AI 辅助筛查"。**HarmonyOS 端统一用 `MSSTformer`**。
2. **热力图数据格式陷阱**：`FacePreview.vue` 用 `data:image/png;base64,` 前缀拼 URL，但服务端 `frame_processor._encode_base64()` 实际编码的是 **JPEG**。ArkTS 端请**按 JPEG 解码，并同时兼容带/不带 `data:` 前缀**。
3. **`heatmap_data` 是 16×16 的 `number[][]`**，行优先（`data[y][x]`），值域 [0,1]，绘制时需 `globalAlpha = 0.4` 叠加在 128×128 对齐脸上。
4. **`/api/analyze` 是空壳**，只回显 `task_id`。**不要指望它触发分析** —— 真正的分析由 WebSocket 建连后发送 `{"id": ...}` 触发。
5. **素材 ID 类型**：DB 里是 `int`，接口返回是 `string`。ArkTS 是强类型，接口模型里统一按 `string` 处理。
6. **`/media/<filename>` 无需鉴权**，但 `url` 是相对路径，需拼 `baseUrl`。
7. **图片与视频的分析行为不同**：图片素材在 `_process_image` 里循环 10 次（内部 `sleep(0.2)`）后整批投递；视频素材每 24 帧一批整批投递。⚠️ 由于 `process_media` 被完整 `await` 后才开始取帧（详见第十部分 10.4），**两帧之间的时间间隔都发生在服务端处理阶段，客户端收到时已是一整批**。UI 上的"进度"和"帧数"会瞬间跳满，**不要按逐帧平滑动画设计，也不要写死帧数**。
8. **VLM 文本可能永远收不到**：`vlm.py` 任何异常都静默返回 `""`，且 `config.py` 里的 API Key 是硬编码的、可能已失效。**"多模态面部分析"折叠区必须允许为空并优雅降级**，否则演示时会缺一块。
9. **`severity` 过滤参数**：`/api/reports?severity=` 传的是枚举名（`none/mild/moderate/severe`），不是中文。
10. **`bdi_trend` 的 `date` 字段**在无数据时可能为 `null`，趋势图需处理空数组。
11. **模型指标 UI 数值有误**：`ModelMetricsCard.vue` 写的是 0.12M / 0.35G / 25ms，实际是 **0.95M / 1.1GFLOPs / 28.2ms**。HarmonyOS 端请写正确值，否则答辩被追问会很尴尬。
12. **安全提醒**：`backend/config.py` 里硬编码了 `VLM_API_KEY = "sk-..."`，`JWT_SECRET_KEY` 也有默认值。**如果这份代码要公开或提交，务必先把 Key 换成环境变量并作废原 Key。**
13. **WebSocket 心跳**：Web 端每 30s 发 `{"type":"ping"}`，服务端**不回复**（只是在帧循环里被 `receive_text` 消费掉）。ArkTS 端照做即可，但**不要把 pong 当作判活依据**。
14. **服务端 frame 循环里的取消轮询**：`asyncio.wait_for(ws.receive_text(), timeout=0.01)` —— 客户端消息只有在服务端推帧的间隙才被读到，**取消不是即时的**，UI 上不要承诺"点了就立刻停"。

---

## 第十部分 · 补充澄清：客户端到底要做多少？（源码级证据）

> 这一部分是针对"后端已经搭设完了，我是不是只要搭一个 UI 就行"这个疑问的正面回答。

### 10.1 客户端定位：薄客户端 + 上传器（结论：是）

从代码可以 100% 确认：**客户端不参与任何计算**。

| 环节 | 在哪里执行 | 证据 |
|---|---|---|
| 视频/图片解码 | 服务端 | `services/frame_processor.py` 用 `cv2.VideoCapture` / `cv2.imread` |
| MTCNN 人脸检测 | 服务端 | `services/face_alignment.py` |
| 双眼仿射对齐 → 128×128 | 服务端 | `_affine_from_eyes()` |
| MSSTformer 推理 | 服务端 | `services/inference.py`，加载 `best.pt` |
| 注意力热力图提取 | 服务端 | `_extract_attention_heatmap()` |
| VLM 语义报告 | 服务端（经公网调用 GLM-4.6V） | `services/vlm.py` |
| **客户端** | **采集 + 上传 + 建连 + 渲染** | 无任何算法代码 |

### 10.2 但"只搭一个 UI"低估了工作量——真实构成

| 层 | 内容 | 工作量占比 |
|---|---|---|
| 界面层 | 3 页面 / 25 组件的视觉复刻 | ~50% |
| **原生能力层** | CameraKit 拍照、AVRecorder 录像、PhotoViewPicker 选文件、multipart 上传、WebSocket 长连+心跳+重连、base64→PixelMap、Canvas 热力图、PDF/长图导出、preferences 持久化 | **~40%** |
| 业务逻辑层 | 严重度分级、四级干预文案、VLM `【】` 分段解析、BDI 三维度估算、Top-3 热点→解剖区域映射 | ~10% |

中间 40% 属于 **ArkTS 平台能力调用**，与"画界面"是两类工作，也是实际最容易卡壳的部分。

### 10.3 ★ 更正：论文描述与代码不一致，必须以代码为准

技术文档 4.2 节表述：

> "前端客户端利用 Canvas 算子以 25fps 帧率捕获视频，并转化为二进制 Blob 格式投递至后端。"

**实际代码并非如此。** `backend/routers/ws.py`：

```python
queue = await process_media(media_path, asset.type.value, str(asset.id))
#                        ↑ 传入的是服务端磁盘上的文件路径
```

`process_media` 内部用 `cv2.VideoCapture(path)` 自行解码。整个 WebSocket 只接收两种**文本**消息：

- `{"id": "<media_id>"}` —— 启动分析
- `{"type": "cancel"}` —— 请求取消

**没有任何接收视频帧 / 二进制分片的通道。**

➡️ **客户端不传帧，只传文件。** 若照论文实现"25fps 推流客户端"，会做出后端无法对接的客户端。

### 10.4 ★ 更正：所谓"实时流式"实为"先整体算完，再一次性回推"

`services/frame_processor.py`：

```python
async def process_media(media_path, media_type, task_id):
    queue: asyncio.Queue = asyncio.Queue()      # maxsize=0 → 无上限，put 永不阻塞
    if media_type == "image":
        await _process_image(media_path, task_id, queue)
    else:
        await _process_video(media_path, task_id, queue)   # ← 整个文件在此跑完
    return queue
```

`routers/ws.py` 中该调用被 **完整 `await`**，之后才进入 `while True: frame = await queue.get()` 的取帧循环。

**实际时间轴：**

```
t=0s     ◀── {"type":"status","message":"analysis_started"}
t=0~数秒   （服务端闷头处理整个视频，客户端收不到任何帧）
t=?s     ◀── 全部 AnalysisFrame 一次性连续推送（24 帧一批，无间隔）
         ◀── {"type":"vlm_analysis", ...}
         ◀── {"type":"done", "final_score": ...}
```

**对 HarmonyOS 端的直接影响：**

1. **进度会从 0 直接跳到 100%** —— `progress` 字段虽逐帧递增，但收包时已全部到达
2. **渲染管线可以做得很朴素**：收到一批 → 整体重绘，不需要处理背压 / 丢帧 / 渲染跟不上
3. **"取消"对视频基本无效** —— 处理早已完成
4. 图片模式同理：10 帧之间的 `asyncio.sleep(0.2)` 发生在 `process_media` 内部，只是**推迟了整批的投递时刻**，并非逐帧到达

### 10.5 后端部署形态（"服务端搭设完了"的真实含义）

```python
# backend/serve_all.py
host = os.getenv("HOST", "127.0.0.1")   # 默认仅本机可访问
port = int(os.getenv("PORT", "8000"))
```
```python
# backend/config.py
DATABASE_URL     = f"sqlite+aiosqlite:///{BASE_DIR / 'depression.db'}"  # 本地文件库
MODEL_CHECKPOINT = str(BASE_DIR / "best.pt")                            # 本地权重
```
```bat
:: 启动-仅本机.bat
"C:\anaconda3\python.exe" serve_all.py
```

**它是一个独立的 Python 进程，跑在某台机器上，不是云服务。** 工作区内无 Dockerfile、无部署清单、无公网地址。

➡️ **因此客户端可用性的第一前提不是 UI，而是"手机能否访问到那台机器"。**

**开工前的必做验证**：手机连同一 WiFi → 浏览器打开 `http://<PC局域网IP>:8000` → 能否打开并登录。

- 能 → 网络通路已通，可全力做 App
- 不能 → 先解决：同 WiFi / Windows 防火墙放行 8000 / 或将后端部署到公网服务器

### 10.6 最小可用客户端（5 步）

```
① POST /api/auth/login                               {username,password} → access_token
② POST /api/upload/image   (multipart, 字段名 = file)                  → {id, type, url}
③ ws://<host>:<port>/ws/analysis?token=<JWT>         建连（token 在 query，非 header）
④ ws.send({"id": "<②返回的 id>"})                    触发分析
⑤ 收消息循环：
     AnalysisFrame  → 更新 BDI / 人脸图 / 热力图
     vlm_analysis   → 填「多模态面部分析」区块
     done           → 结束、落库展示
```

**②③④⑤ 跑通，App 的核心价值即已交付，剩余皆为 UI 打磨。**

### 10.7 唯一会让"只搭 UI"不成立的情形：端侧推理

若验收明确要求"在 HarmonyOS 设备本地跑 MSSTformer"，则需新增一条现有代码完全不存在的链路：

| 工作项 | 内容 | 工期 |
|---|---|---|
| 模型转换 | `best.pt` → ONNX → MindSpore Lite / NNRt | 3–5 天 |
| 预处理移植 | MTCNN 5 点检测 + 双眼仿射 + BGR 均值归一化，ArkTS 或 C++ 重写 | 1–2 周 |
| 推理封装 | MindSpore Lite `Model`/`Tensor`、FP16/INT8 量化 | 3–5 天 |
| 后处理 | 热力图提取 + 分数映射 | 2 天 |

**合计 2–4 周额外工作**，与"搭 UI"是两个独立项目。可行性上没有障碍（0.95M 参数 / 3.8MB 权重本身就为端侧设计），但**除非验收明确要求，不建议现在开这个口子**——答辩时作为"已在昇腾边缘板验证、规划中"的扩展来讲更划算。

---

## 第九部分 · 一句话总结

> 这是一个**用 0.95M 参数轻量 Transformer 从人脸视频回归 BDI-II 抑郁评分的端云协同筛查系统**：浏览器采集 → FastAPI 后端做 MTCNN 对齐 + MSSTformer 推理 → WebSocket 实时回传评分与注意力热力图 → 云端 GLM-4.6V 生成临床语义报告 → HTML2Canvas + jsPDF 导出标准化 PDF。
>
> **你的任务（构建 HarmonyOS 端）在技术上的本质是：把这套"采集 → 上传 → WebSocket → 可视化 → 报告"的客户端流程，用 ArkTS/ArkUI 原生重写一遍，复用现有后端全部接口，不需要移植模型。** 最大风险点是**明文 HTTP 网络配置**、**CameraKit/AVRecorder 采集**、**PDF 原生导出**这三处，建议各自先做最小可行性验证再全面展开。

---

## 附：本次分析新增的中间产物

| 文件 | 内容 |
|---|---|
| `_extract/技术文档.txt` | 技术论文全文（17,377 字，已从 docx 提取） |
| `_extract/答辩ppt.txt` | PPT 文字（PPT 为整图版式，文字极少） |
| `_extract/训练日志.txt` | 训练日志文字（正文为 4 张资源监控图） |
| `_extract/pptmedia/` | PPT 内嵌图片（image1–3.png 内容页、image4.emf 架构图、image5.png） |
| `_extract/logmedia/` | 训练日志内嵌 4 张监控曲线图 |

> 注：`展示图片/*.png` 与 PPT 内容页为图片素材，需要看图确认视觉效果时可直接打开这些文件。
