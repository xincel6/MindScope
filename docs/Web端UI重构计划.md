# MindScope Web 端 UI 重构计划（基于两端现状盘点）

> 范围：`E:\MindScope\dashboard`（Vue 3 + Vite 前端）对齐 `E:\MindScope\harmony`（ArkTS / ArkUI）。
> 本文只出计划，不改代码、不启服务。所有结论均标注证据位置（`文件:行`）。
> 盘点日期：2026-10-22。盘点依据：两端源码、`dashboard/backend/routers/*.py`、`README.md`、`docs/`、`BUG清单.md`。

---

## 一、现状盘点

### 1.1 两端信息架构快照

**鸿蒙端**（`harmony/entry/src/main/ets/pages/PageRoutes.ets:79-90` 为唯一真源）：

| 层级 | 页面 | 说明 |
|---|---|---|
| 登录流 | `LoginPage` / `RegisterPage` | 独立两页，非 tab 切换 |
| 一级页签（5） | 工作台 / 素材库 / 历史报告 / 统计 / 我的 | 底部 tab，顺序即导航顺序 |
| 二级页 | `MediaPickerPage`（选素材上传）/ `AnalysisDetailPage`（历史报告查看器） | `pushPathByName` 入栈 |
| 调试页 | `HeatmapProbePage` | 不进业务流 |

**Web 端**（`dashboard/src/router/index.ts`）只有 **3 条路由**：

| 路由 | 组件 | 实际承载 |
|---|---|---|
| `/login` | `LoginView.vue` | 登录 + 注册（同页 tab 切换） |
| `/` | `StatsView.vue` | 统计概览 |
| `/analysis` | `AnalysisView.vue` | 三栏工作台：素材列表 + 监控区 + 右栏（3 个 tab） |

**根本差异**：鸿蒙把「素材库」「历史报告」「统计」「我的」拆成 4 个一级入口；Web 把素材库塞进 248px 左栏、历史报告塞进 400px 右栏的第 3 个 tab、统计页做成首页、**没有「我的」**。这不是皮肤差异，是导航模型差异——任何"只换配色"的方案都无法达成要求 (1)(3)。

### 1.2 鸿蒙端能力清单（页面 / 组件 / Store / DAO / 接口）

**页面级能力**

| 页面 | 已实现能力 |
|---|---|
| `WorkbenchPage.ets` | 页头（标题+问候·日期+统计说明+刷新，`:939-993`）、离线横幅+重试（`:997-1038`）、7 张业务卡（`:1118-1185`：页头→离线横幅→本次评估 hero→开始新的辅助评估→注意力热力图→情绪曲线→严重度分布→智能解读→诊断意见）、"无查看目标时整段不渲染"（`:1149`） |
| `MediaLibraryPage.ets` | 搜索（名称/患者，`:163-204`）、排序（时间/姓名，`:206-235`）、按患者分组（`buildGroups` `:476`）、分组卡片、上传（`:144-156`）、重命名患者、删除、破图兜底（`isBroken/markBroken` `:655-660`） |
| `ReportsPage.ets` | 严重度筛选（`:454`）、素材类型筛选（`:480`）、关键字搜索（`searchScoreOf` `:275`）、按素材分组（`ReportMediaGroupModel`）、清除筛选（`:553`）、分页「加载更多」、只剩最早一份的终止提示（`:745`）、"只展示服务端已保存报告"（`:695`）、**详情入口**（`:658`） |
| `StatsPage.ets` | KPI hero + 严重度分布（`:236`）+ BDI 日均趋势（`:283`）+ 空态（`暂无分析数据` `:260`） |
| `ProfilePage.ets` | 账号信息（头像首字/用户名/邮箱/注册时间，`:128-165`）+ 退出登录 + **二次确认弹层**（`ConfirmSheet`，`:260-280`） |
| `AnalysisDetailPage.ets` | 分析进度、BDI 分值与 0–63 口径说明、逐帧热力图+「回到最新」、智能解读、"取消可能不生效"提示（`:931`） |
| `LoginPage.ets` | 登录成功/失败分流（退出码 0/1/2/3）、失败弹窗（`AuthAlert`）、服务端不可达引导 |

**Store / DAO 能力**（`harmony/entry/src/main/ets/store/*`、`persistence/*`）

- `MediaStore`：`visibleItems/totalCount/imageCount/videoCount/patientOptions/patientFilterValue/setPatientFilter/filteredItems/hasPatientFilter/findById/playableUrl/thumbnailUrl/select/refresh/loadFromCache/warmUp/deleteMedia/uploadMedia/uploadMediaWithPatient/uploadImage/uploadImageWithPatient/renamePatient/clear`
- `ReportStore`：`isFiltered/filterSummary/emptyHint/buildFilter/refresh/loadAllPages/loadMore/applyFilter/applyFilterAndLoadAll/resetFilter/loadDetail(mediaId, mediaName, mediaType)/loadFromCache/warmUp`
- `StatsStore`：`hasData/totalAnalyses/totalMedia/avgInferenceTimeMs/bdiTrend/recentReports/dominantSeverityLabel/refresh/loadFromCache/warmUp/ratioText/colorOf`
- `AuthStore`：`login/register/restore/loadMe/logout/onUnauthorized/refresh/snapshot`
- `AnalysisStateHolder`（22KB）：分析会话状态与逐帧数据
- 持久化：`MediaDao(username 过滤)/ReportDao/StatsCacheDao/AssessmentCacheDao/BaseDao/DbSchema/StorageManager/PreferenceStore`（`token`、`server_host`、`server_port`、`last_sync_at`、`keep_cache_on_logout`）

**网络层**（`harmony/entry/src/main/ets/network/*`）
`/api/auth/login|register|me`、`/api/media/list`、`DELETE /api/media/{id}`、`PUT /api/media/{id}/patient`、`POST /api/upload/image`（含 `?patient=`）、`GET /api/reports`、`GET /api/report/{media_id}`、`GET /api/stats`、`/ws/analysis`、`/health`；401 全局拦截（`HttpClient.ets:177`）。

### 1.3 Web 端能力清单

| 文件 | 能力 |
|---|---|
| `src/api/index.ts`（102 行） | `fetchMediaList`、`deleteMedia`、`triggerAnalysis`、`analyzeFaceBase64`、`fetchStats`、`fetchReports` |
| `src/api/auth.ts` | `loginApi`、`registerApi`、`fetchMeApi` |
| `src/stores/dashboard.ts`（485 行） | 素材/分析/WS/VLM/受试者信息 + **演示数据生成器** |
| `src/stores/stats.ts` | `load()` |
| `src/stores/auth.ts` | `login/register/logout/loadUser/initFromStorage`（**无 refresh token、无 401 全局续期**，`loadUser` 失败即 `logout`） |
| `src/composables/useWebSocket.ts` | `/ws/analysis`、心跳 `ping`、断线重连 |
| `src/composables/usePdfExport.ts` | html2canvas + jsPDF 导出（**Web 独有**） |
| `src/components/center-panel/MainVideoPlayer.vue` | 视频播放、`getUserMedia` 摄像头采集、`MediaRecorder` 录制上传（**Web 独有**） |
| `src/components/left-panel/FaceFrameGallery.vue` | 逐帧人脸缩略条 + 点击单帧重推理（`analyzeFaceBase64` → `switchVideoAnalysisToSingleFaceImage`，**Web 独有交互**） |
| `src/components/right-panel/HistoryPanel.vue` | 平铺表格 `fetchReports({limit:100})` + 双选对比（`ComparisonModal`，**Web 独有**） |

### 1.4 功能差异表（逐条，含证据）

| # | 能力 | 鸿蒙 | Web | 差异判定 | 建议 |
|---|---|---|---|---|---|
| 1 | 一级导航 | 5 页签 | 2 项顶部导航 | **缺 3 个入口** | P3 改左侧栏 5 项 |
| 2 | 素材搜索（名称/患者） | `MediaLibraryPage.ets:163-204` | 无 | **缺** | P3 补 |
| 3 | 素材排序（时间/姓名） | `:206-235` | 无 | **缺** | P3 补 |
| 4 | 按患者分组 | `buildGroups()` `:476` | 按 image/video 两段平铺 | **模型不同** | P3 改为按患者分组 |
| 5 | 上传带患者名 | `uploadImageWithPatient` | `uploadAndAnalyze(file)` 无 patient（`stores/dashboard.ts:174-202`） | **缺**（后端 `?patient=` 已支持） | P4 补 |
| 6 | 重命名所属患者 | `renamePatient` → `PUT /api/media/{id}/patient` | 无 | **缺**（后端已支持，`backend/routers/media.py`） | P4 补 |
| 7 | 历史报告筛选（严重度/类型/关键字） | `ReportsPage.ets:454/480/275` | 无，一次拉 100 条（`HistoryPanel.vue:43`） | **缺** | P3/P4 补 |
| 8 | 历史报告分页 | `loadMore`/`loadAllPages` | 无 | **缺** | P4 补 |
| 9 | 报告详情（单素材快照） | `AnalysisDetailPage` + `GET /api/report/{media_id}` | 无调用（`GET /api/report/{media_id}` 后端已存在，Web 全项目未使用） | **缺** | P4 补 |
| 10 | 逐帧热力图浏览 + 回到最新 | `AnalysisHeatmapCard` | `FaceFrameGallery` 缩略条可点单帧重推理 | 能力互补 | 合并为一张卡：缩略条 + 大图 + 回到最新 |
| 11 | 智能解读（VLM 分节） | 独立卡 `AnalysisVlmCard` | 折叠在报告里（`DiagnosisReport.vue:243-248`） | **位置不同，被埋没** | P3 提为独立卡 |
| 12 | 诊断意见（AI 初判 / 判断依据 / 医师意见 / 仅本次会话有效） | `DiagnosisOpinionCard`（`model.aiDraft/conclusion/evidence/doctorName/status`） | **半成品**：`src/utils/diagnosisOpinion.ts`（218 行）已实现 `buildEvidence/buildAiDraft/buildSubScales/topHotspot/isSameSnapshot/OPINION_MAX_LEN`，但**全项目 0 引用**，无任何组件使用 | **缺 UI（逻辑已在）** | P4 补卡片，并先裁决 `buildSubScales` 去留（见下） |
| 13 | 严重度分布 | 工作台独立卡 | 仅统计页饼图 | 位置不同 | P3 |
| 14 | 我的（账号信息 + 退出二次确认） | `ProfilePage.ets:167-243` | 无页面；header 退出**无二次确认**（`DashboardHeader.vue:105-107`） | **缺** | P4 补 |
| 15 | 离线态 + 重试 | 离线横幅 + 重试（`WorkbenchPage.ets:997-1038`） | 仅 `StatusBadge`/`AnalysisStatusBar` 显示连接态，无重试、无缓存 | **缺** | P4 补（Web 可只做"离线提示 + 重试"，不做 DB 缓存） |
| 16 | 取消分析 | `AnalysisHeroCard` `onCancel` | 无（全项目无取消入口，仅对话框有"取消"） | **缺** | P4 补 |
| 17 | 本地缓存 / 冷启动恢复 | 7 个 DAO + `PreferenceStore` | 无（刷新即全丢） | **缺** | P5 视需求（可选 localStorage 轻量版） |
| 18 | 忘记密码 / 验证码 | 后端 `POST /api/auth/send-code` 就绪 | 未调用 | **缺** | P4 视需求 |
| 19 | PDF 报告导出 | 无 | `usePdfExport.ts` | **Web 独有** | 保留，P5 按新令牌重做 |
| 20 | 双报告对比 | 无 | `ComparisonModal.vue` | **Web 独有** | 保留，P3 挂到报告详情页 |
| 21 | 摄像头采集 / 录制 | 无（用图库 `MediaPicker`） | `MainVideoPlayer.vue:141-330` | **Web 独有** | 保留 |
| 22 | 单帧重推理 | 无（只有"查看某帧"） | `analyzeFaceBase64` | **Web 独有** | 保留，收进热力图卡 |
| 23 | 演示数据 | 仅热力图卡内标注「演示数据」（`AnalysisHeatmapCard.ets:417`） | **全站伪装真实数据**：`loadDemoData()` 造 6 个假患者（`stores/dashboard.ts:382-394`）、`startDemoAnalysis` 造 60 帧假曲线（`:396-439`）、`generateDemoHeatmap` 造高斯热力图（`:441-456`）、**空列表自动触发**（`MediaLibrary.vue:42`）、header 有「加载演示数据」按钮（`DashboardHeader.vue:86-94`） | **必须整改** | P2 全删/改造 |
| 24 | 服务端地址配置 | `PreferenceStore` host/port + 登录页设置 | `baseResolver.ts` + `warmUpApiBase()` | 各有实现 | 不动 |

### 1.5 「AI 生成感」证据清单（带量化）

| 类别 | 证据 | 量 |
|---|---|---|
| 渐变滥用 | 实测 `linear-gradient` **11 处** + `radial-gradient` **3 处**（`.app-bg` 三层叠加（`style.css:151` + `:160-162`：`linear-gradient(145deg,#eef6fb,#e6f4f1,#edf5ff)` + 三个 radial）；`.section-title::before` 每个区块标题挂渐变小色条（`style.css:220`）；`GlowProgress.vue:32` 进度条渐变；`CloudTopology.vue:155`、`MainVideoPlayer.vue:561`、`DiagnosisReport.vue:332`、`LoginView.vue:170` 都是 `#ecfdf5→#e0f2fe` 薄荷→天蓝渐变块 | 14 处 |
| 发光 / 毛玻璃 | `DashboardHeader.vue:119-120` 半透明白 + `backdrop-filter: blur(12px)`；`GlowProgress.vue` 组件（命名即"发光进度条"，`DiagnosisReport.vue` 引用 4 次）；`CloudTopology.vue:66-68` `shadowBlur:8 + rgba(13,148,136,0.25)` 节点光晕 | 3 类 |
| 圆角失控 | 全局 `border-radius` 出现 **15 种取值**：`2px/3px/4px/5px/6px/8px/10px/12px/20px/50%/var(--radius-sm)/var(--radius-card)/var(--radius-lg)`，其中 **3 处带 `!important`**（`--radius-sm/card/lg` 各 1） | 15 档 |
| 字号失控 | `font-size` 出现 **15 种取值**：`9/10/11/12/13/14/15/16/18/20/22/28/32/42/48px`；其中 **9–11px 共 55 处**，低于两端可读性下限 | 15 档 |
| 卡片堆叠 | `.glass-card` 用在 **10 个组件**（MainVideoPlayer / FaceFrameGallery / MediaLibrary / EmotionCurve / RightPanel / BdiTrendChart / ModelMetricsCard / RecentReportsTable / SeverityPieChart / StatCard），且 `RightPanel(卡) > DiagnosisReport > score-hero(内层底) > stat-row(更内层底)` 出现 3–4 层嵌套；`.glass-card:hover` 还会改边框色+加深阴影（`style.css:198-200`） | 10 组件 / ≥3 层 |
| 逃避令牌 | `.vue/.ts` 内裸十六进制 **118 处**（`#94a3b8` 13 次、`#64748b` 9 次、`#475569` 8 次…），另 `style.css` 55 处；`rgba()` 裸用 70 处；`--accent-violet: #6366f1` 定义了但**全项目 0 引用**（死令牌） | 173 + 70 |
| 假图表 | ① `CloudTopology.vue:35-94`：ECharts `graph` + `force` 布局，3 个节点是**硬编码常量**（"终端设备/LMTformer 推理节点/结果输出"），与实际推理无关；② `DiagnosisReport.vue:91-101`：BDI 三维分量 = `总分×0.48 / 总分×0.35 / 余数`，用进度条渲染成"量表分项"；③ `ModelMetricsCard.vue`：整张算力卡数值全部硬编码（0.12M / 0.35G / 25ms / 32dim），无任何数据源 | 3 处 |
| 通用后台模板味 | 右栏 `el-tabs` 三 tab（诊断报告/云端推理/历史记录，`RightPanel.vue:12-22`）把三个不同层级的信息压进一个 400px 卡片；`LoginView` 左侧品牌区 = 4 条 feature-list 图标卡（通用 SaaS 落地页套路）；`StatsView` 4 张 KPI 卡 + 2 图 + 静态模型卡 + 最近报告表 | 3 处 |

### 1.6 可访问性与一致性实测（对比度按 WCAG 2.1 相对亮度，对 #FFFFFF 计算）

| 颜色 | 用途 | 对比度 | 判定 |
|---|---|---|---|
| `--text-muted #94a3b8` | 11px 说明文字 | **2.56:1** | ✗ 不达 AA（4.5:1） |
| `--text-label #64748b` | 11px 标签 | 4.48:1 | △ 临界 |
| `--accent-primary #0d9488` | 主色文字/图标 | 3.74:1 | △ 仅达 AA 大字/UI 组件（3:1） |
| `--accent-cyan #0891b2` | 数值强调 | 3.68:1 | △ 同上 |
| `severityColors.severe #f3b2bd` | 重度占比卡数值+标签（`StatsView.vue:76`） | ≈1.2:1 | **✗✗ 严重失效** |
| 其余淡彩 `#f2f3b2/#b2f3cd/#b2c3f3` | 严重度标签/饼图 | ≈1.1–1.4:1 | **✗✗** |
| 鸿蒙 `#16a34a` / `#0284c7` / `#d97706` / `#dc2626` | 严重度数据表达 | 3.29 / 4.10 / 3.19 / **4.83** | 仅"重度"过 AA 正文 |
| 鸿蒙统计切片 `#17B26A/#2E6BE6/#F79009/#F04438` | 饼图扇区填充 | 2.76 / 4.81 / 2.35 / 3.76 | 仅作填充色可接受，**不得用于文字** |

**结论**：两端都存在"数据表达色被当文字色用"的问题；Web 端的淡彩严重度色板是本次重构中**最优先、零风险可修**的一项。

---

## 二、两端设计令牌对齐方案

### 2.1 对齐原则

1. **鸿蒙 `UiTheme.ets` 是唯一真源**（435 行集中定义，ArkTS 侧全部页面从它取值）。Web 端新建 `src/styles/tokens.css` + `src/styles/tokens.ts`，值逐条取自 `UiTheme.ets`，不允许新造值。
2. **色板收敛为 3 个功能色 + 中性灰阶 + 1 套数据表达色**（鸿蒙 `UiTheme.ets` 顶部纪律原文：只 3 个功能色；两套"红"必须分清）。
3. **圆角 4 档、字号 6 档、间距 8 档、阴影 2 级**——档位数即验收指标。
4. 渐变**白名单制**：只允许 2 处，且都必须是鸿蒙已有语义（品牌渐变 / KPI hero 渐变）。

### 2.2 色板映射表

| 语义 | 鸿蒙常量与值 | Web 现值 | 建议 Web token | 处置 |
|---|---|---|---|---|
| 页面底色 | `pageBackground #F2F3F7` | `--bg-primary #eef6fb`（青调） | `--bg-page: #F2F3F7` | 换 |
| 卡片底色 | `cardBackground #FFFFFF` | `#ffffff` | `--bg-card: #FFFFFF` | 保留 |
| 内嵌填充 | `fillSoft #E9EDF3` | `--bg-muted #e8f4f8`（青调） | `--bg-inset: #E9EDF3` | 换 |
| 描边/分隔 | `divider #E5E6EB` | `--border-color rgba(14,165,233,0.14)` / `--border-subtle rgba(148,163,184,0.18)` | `--border: #E5E6EB` | 换（去青调半透明边） |
| 主色 | `primary #0D9488` | `--accent-primary #0d9488` | `--color-primary: #0D9488` | 保留 |
| 主色（文字态，新增） | —（鸿蒙无，建议新增） | — | `--color-primary-text: #0F766E` | **新增**，正文用（5.50:1 过 AA） |
| 辅助色 | `accent #0284C7` | `--accent-blue #0284c7` | `--color-accent: #0284C7` | 保留 |
| 危险/失败 | `danger #DC2626` | `--accent-red #ef4444` | `--color-danger: #DC2626` | 换（与鸿蒙同值） |
| 错误底 | `dangerSoft #FEF2F2` | 无 | `--color-danger-soft: #FEF2F2` | 新增 |
| 正文 | `textPrimary #1D2129` | `--text-primary #1e3a5f`（深海军蓝） | `--text-primary: #1D2129` | 换 |
| 次级文字 | `textSecondary #4E5969` | `--text-secondary #475569` | `--text-secondary: #4E5969` | 换 |
| 弱化文字 | —（鸿蒙复用 `textSecondary`） | `--text-muted #94a3b8`（2.56:1 ✗） | **删除 `--text-muted`**，弱化一律用 `--text-secondary` | **删** |
| 在线/离线 | `statusOnline #16a34a` / `statusOffline #DC2626` | `#059669` / `#ef4444` 混用 | `--status-online: #16A34A` / `--status-offline: #DC2626` | 换 |
| 严重度数据色 | `severityMeta()`：`#16A34A/#0284C7/#D97706/#DC2626` | `severityColors`：`#f2f3b2/#b2f3cd/#b2c3f3/#f3b2bd`（`stores/dashboard.ts:37-42`） | `--severity-none/mild/moderate/severe` 取鸿蒙值 | **替换（最高优先）** |
| 严重度文字态（新增） | — | — | `#15803D/#0369A1/#B45309/#B91C1C` | **新增**，badge 文字用（均 ≥4.5:1） |
| 统计图切片 | `severityPieColors ['#17B26A','#2E6BE6','#F79009','#F04438']` | 复用严重度淡彩 | `--chart-1..4` 取鸿蒙值 | 换 |
| 图表网格/轴 | `chartGrid #E5E6EB`、`chartAxis #94A3B8` | `--chart-split`、`--chart-axis` | 对齐 | 换 |
| 删除的死令牌 | — | `--accent-violet #6366f1`、`--accent-mint #2dd4bf`、`--accent-teal #14b8a6`、`--accent-cyan #0891b2`（0–2 引用） | — | **删** |

### 2.3 字号阶（6 档，禁止 <12px）

| 档 | 鸿蒙 | Web token | 用途 |
|---|---|---|---|
| 12 | `fontSizeCaption` 12 | `--font-xs: 12px` | 标签、图表轴（鸿蒙 `fontSizeAxis` 11 为唯一例外，Web 图表轴用 11px 并加注释） |
| 14 | `fontSizeBody` 14 | `--font-sm: 14px` | **正文下限** |
| 16 | `fontSizeSection` 16 | `--font-base: 16px` | 卡片标题 |
| 20/22 | `fontSizeTitle` 22 | `--font-title: 22px` | 页面标题 |
| 24 | `fontSizeCardMetric` 24 | `--font-metric-sm: 24px` | 卡内主数值 |
| 32 | `fontSizeMetric` 32 | `--font-metric: 32px` | 页内主数值 |

替换后需消除的 15 档：`9/10/11(除图表轴)/12/13/14/15/16/18/20/22/28/32/42/48px` → 收敛到上表 6 档。**当前 42px / 48px / 28px / 20px 无对应语义，直接降级。**

### 2.4 间距阶（8 档）与布局常量

| token | 值 | 对应鸿蒙 |
|---|---|---|
| `--space-1..6` | 4 / 8 / 12 / 16 / 24 / 32 | `gapXs/gapS/gapM/gapL/gapXl/gapXxl` |
| `--page-padding` | 16（<1280）/ 24（≥1280） | `pagePadding 20`（移动端） |
| `--header-height` | 56 | 保留（桌面已有契约） |
| `--nav-width`（新） | 240 | 替代 `--sidebar-width 248` |
| `--content-gap` | 16 | 原 12 |

### 2.5 圆角（4 档）

| token | 值 | 对应鸿蒙 | 用途 |
|---|---|---|---|
| `--radius-card` | 16 | `cardRadius 16` | 所有卡片 |
| `--radius-control` | 12 | `buttonRadius 12` | 按钮、输入框、下拉 |
| `--radius-tag` | 8 | —（新增） | 标签、chip、缩略图内嵌块 |
| `--radius-pill` | 999 | —（新增） | 状态点、圆形头像 |

替换后需消除：`2/3/4/5/6/10/20px`、`50%`、两处 `!important`。

### 2.6 阴影（2 级，去青调）

```css
/* 对应 UiTheme: cardShadowRadius 14 / cardShadowColor #141D2129 / cardShadowOffsetY 3 */
--shadow-card: 0 1px 2px rgba(29, 33, 41, 0.04), 0 3px 14px rgba(29, 33, 41, 0.08);
--shadow-popover: 0 8px 24px rgba(29, 33, 41, 0.10);
```
**删除**：`--shadow-card-hover`（卡片 hover 抬升/变色）、所有 `GlowProgress` 光晕、`CloudTopology` 节点 `shadowBlur`、`backdrop-filter: blur()`。鸿蒙的三件套纪律是"浅灰页底 + 纯白卡片 + 极淡投影"，卡片内嵌元素（输入框、缩略图底、进度条轨道）**不用投影**，改用 `--bg-inset` / `--border` 描边——Web 端同为。

### 2.7 动效（对齐鸿蒙节拍）

| 场景 | 鸿蒙 | Web 现状 | 建议 |
|---|---|---|---|
| 按压反馈 | `pressDuration 120`（`RippleCard` 用原生按压，见 BUG-01 处置） | 无统一按压态 | `--motion-press: 120ms`，`transform: scale(0.985)` |
| 卡片入场 | `RevealCard` 错峰（工作台 `order`×stepMs，离线横幅用 `order 0.5` 插队） | `fadeInUp 0.28s` 全局同时 | 改为 `--motion-enter: 260ms` + `--stagger: 55ms`，仅首屏播放一次 |
| hover | 无抬升（移动端无 hover） | 卡片 `translateY(-2px)` + 换边框 + 加深阴影 | **删除**；桌面 hover 只允许改 `background` 或 `border-color` |
| 进度条 | 纯色主色填充 `progressHeight 8/radius 4` | `GlowProgress` 渐变+光晕 | 换纯色 `--color-primary` |

### 2.8 渐变白名单（只允许 2 处）

| # | 位置 | 渐变值 | 鸿蒙对应 |
|---|---|---|---|
| 1 | 登录页左侧品牌区 / 开屏位 | `linear-gradient(160deg, #22B49C 0%, #0C7A69 100%)` | `brandStart #22B49C` → `brandEnd #0C7A69` |
| 2 | 统计页 KPI hero 卡 | `linear-gradient(180deg, #E8F6EF 0%, #FFFFFF 100%)` | `kpiGradientStart #E8F6EF` → `kpiGradientEnd #FFFFFF` |

其余 12 处渐变（`.app-bg` 的 1 linear + 3 radial、`.section-title::before`、`GlowProgress`、4 处 `#ecfdf5→#e0f2fe` 块、PDF 模板内联）全部删除。

---

## 三、分阶段重构计划

> 每阶段独立成 PR，均可单独 revert。分支命名 `ui-refactor/p0..p5`；阶段门禁：`pnpm vue-tsc -b && pnpm build` 通过 + 令牌断言脚本通过 + 截图对比。

### P0 · 令牌单源与守卫（预计 1–2 天）

**目标**：先把"尺子"做出来，不动任何视觉。

**涉及文件/目录**
- 新增 `dashboard/src/styles/tokens.css`（本文 §2 全部 token）、`dashboard/src/styles/tokens.ts`（JS 侧常量，供 ECharts 用，替代 `src/utils/chartTheme.ts`）
- 改 `dashboard/src/style.css`：`:root` 段改为 `@import './styles/tokens.css'`，旧变量名保留别名映射（`--accent-primary: var(--color-primary)`），保证 P0 零视觉变化
- 新增 `dashboard/scripts/check-tokens.mjs`（断言脚本，见验收）
- 改 `dashboard/package.json`：加 `"check:tokens"` script

**验收标准**
1. `pnpm build` 通过，页面截图与改造前**像素一致**（`--accent-*` 等旧名仍是别名）。
2. 断言脚本输出 0 报错，且脚本本身可被后续阶段直接复用：
   - `grep -rn "border-radius" src --include=*.vue | grep -v "var(--radius"` → 0 行
   - `grep -rn "font-size" src --include=*.vue | grep -v "var(--font"` → 0 行
   - `grep -rnE "#[0-9a-fA-F]{6}" src --include=*.vue --include=*.ts` → 0 行
3. `dashboard/src/styles/tokens.css` 中每个值旁有 `/* ← UiTheme.<常量名> */` 注释，可逐条回查。

**风险 / 回滚**
- 风险：旧变量别名漏掉某个被引用的变量名（`--shadow-card` 引用点 10 处）。
- 回滚点：`git revert` P0 单个 commit 即可，因为不改任何视觉。

---

### P1 · 去「AI 生成感」外科手术（预计 3–5 天）

**目标**：把 §1.5 的 8 类"AI 感"证据逐条消灭；**不改信息架构、不改数据源**。

**涉及文件/目录**
- `dashboard/src/style.css`：删 `.app-bg/.neuro-bg` 三层渐变（`:145-163`）、删 `.section-title::before` 渐变小色条（`:216-223`）、`.glass-card` 去掉 `backdrop-filter`/`hover` 抬升/青调阴影（`:181-200`）、`.clinical-disclaimer` 改 `--color-warning-soft`、Element Plus 覆盖段重写（约 110 行，其中 `.el-tag` 的 8 个 `[color="#..."]` 硬编码分支改为类名 `.sev-none/.sev-mild/.sev-moderate/.sev-severe`）
- `dashboard/src/components/layout/DashboardHeader.vue`：去 `backdrop-filter: blur(12px)`（`:119-120`），改 `background: var(--bg-card)` + 底部 1px `--border`
- `dashboard/src/components/common/GlowProgress.vue`：整体替换为纯色 `ProgressBar.vue`（对齐鸿蒙 `components/common/ProgressBar.ets`：`progressHeight 8`、`progressRadius 4`、轨道 `--bg-inset`），同步改 `DiagnosisReport.vue` 4 处引用
- `dashboard/src/components/right-panel/CloudTopology.vue`：见 P2（本阶段只去渐变底 `:155` 与节点 `shadowBlur` `:66-68`）
- `dashboard/src/stores/dashboard.ts:37-42`：`severityColors` 改为鸿蒙 `severityMeta()` 四色；新增 `severityTextColors` 供文字使用
- `dashboard/src/views/StatsView.vue:76`：重度占比卡的 `accent` 改用 `severityTextColors.severe`
- `dashboard/src/views/LoginView.vue:170`：品牌区渐变替换为 §2.8 白名单 #1
- 全量字号/圆角替换（脚本化：14 档 → 6 档、16 档 → 4 档）

**验收标准**
1. `grep -rn "linear-gradient" src` 结果 ⊆ §2.8 白名单 2 处（含 `.vue`/`.css`/`.ts`）。
2. `grep -rn "backdrop-filter\|shadowBlur\|filter: blur" src` → 0 行。
3. `border-radius` 取值集合 = 4 档；`font-size` 取值集合 = 6 档（图表轴 11px 白名单除外，需在脚本里显式列出）。
4. 严重度四色在页面任意位置出现时，文字类用法一律取 `severityTextColors`；用 axe DevTools 扫 `/`、`/analysis`、`/login` 三轮，**color-contrast 违规 0 条**。
5. 卡片 hover 不再产生任何位置/尺寸变化（录屏确认）。

**风险 / 回滚**
- 风险 1：`severityColors` 是 `StatsView`、`HistoryPanel`、`SeverityPieChart`、`AnalysisStatusBar`、`DiagnosisReport`、`CloudTopology` 共 6 处的共享色源，替换后饼图/标签配色会同时变——需一次性同步截图核对。
- 风险 2：`GlowProgress` 有 `:height` prop，替换时容易漏传（3 处传 `:height="4"`）。
- 回滚点：P1 结束打 tag `ui-p1`；`severityColors` 与 `GlowProgress` 各单独 commit 便于定点 revert。

---

### P2 · 清除假数据与伪图表（预计 2–3 天）

**目标**：兑现要求 (2) 中"假数据图表"，让界面显示的每个数字都有出处。

**涉及文件/目录**
- `dashboard/src/stores/dashboard.ts`：**删除** `loadDemoData`(:382-394)、`startDemoAnalysis`(:396-439)、`generateDemoHeatmap`(:441-456)、`stopDemoAnalysis`、`isDemo`、`demoPlaying`、`demoInterval` 及 return 导出项；`removeMedia`/`startAnalysis` 里的 `isDemo` 分支同步删
- `dashboard/src/components/left-panel/MediaLibrary.vue:38-48`：删 `onMounted` 里的自动 `loadDemoData()`；删 `console.log` 调试输出（`:47`）
- `dashboard/src/components/layout/DashboardHeader.vue:86-94`：删「加载演示数据」按钮，改为「上传素材」主操作
- `dashboard/src/components/left-panel/FaceFrameGallery.vue:47`、`MediaLibrary.vue:54-55`、`MainVideoPlayer.vue:59/73/87-89/106`：删全部 `store.isDemo` 分支
- `dashboard/src/components/right-panel/CloudTopology.vue`：**删除整个 force graph**（`:35-94`），保留右侧 5 行真实指标（批推理耗时/帧序进度/当前 BDI/WS 连接/分析状态），标题从「云端推理状态」改为「本次推理指标」；`flow-desc` 的字符箭头链（`:105-111`）删除
- `dashboard/src/components/right-panel/DiagnosisReport.vue:91-101`：删除"BDI-II 维度估计"伪造条（`总分×0.48/0.35`）；若要保留维度概念，改为显式"本模型未输出量表分项"的空态（禁止用比例系数倒推）
- `dashboard/src/components/stats/ModelMetricsCard.vue`：改为折叠的「模型信息」，每项后标注来源（`best.pt` 权重名/`backend/services/`），**删除 4 个不同颜色的数值**，统一 `--text-primary`
- `dashboard/src/utils/diagnosisOpinion.ts:50-54`：**同一套倒推公式的第二份副本**（`buildSubScales()` 里 `total*0.48 / total*0.35`），且是「诊断意见」卡片的唯一逻辑来源。若按"禁止倒推"处置，此处必须同步改为 `available: false` + 文案「本模型未输出量表分项」，否则 P4 接线后伪造数据会从报告页蔓延到诊断意见卡。后端与鸿蒙端均无 subscale 字段（`backend/**.py` 0 命中、`harmony/**.ets` 0 命中），证明该维度确无数据源。
- 兜底：所有"无数据"位置统一走 `EmptyState` 组件（对齐鸿蒙 `PlaceholderView.ets` / `ErrorRetryView.ets`），禁止用假数据填位置

**验收标准**
1. `grep -rn "Demo\|demo" src` → 0 行（`demo/` 目录引用也应为 0）。
2. 断网启动、空库启动两种情况下，页面**只显示空态文案**，不出现任何患者名/分数/曲线。
3. 遍历界面上每个数字，能对应到 `/api/stats`、`/api/reports`、WS 帧或 `best.pt` 静态属性之一（逐项列表签字）。
4. 饼图/趋势图在 `total_analyses = 0` 时显示空态而非空坐标系。

**风险 / 回滚**
- 风险：`loadDemoData` 是当前**演示/答辩路径**（`DashboardHeader` 与 `MediaLibrary` 双入口），删除后无素材时页面会很空——需与产品确认是否保留"演示模式"为**显式开关**（如 URL `?demo=1` 或独立 `/demo` 路由，且横幅常驻标注"演示数据"）。
  - **建议**：保留但降级——独立 `/demo` 路由 + 顶部常驻黄色横幅（`--color-warning` + `--color-warning-soft`），主流程 0 假数据。此项需用户确认。
- 回滚点：demo 相关逻辑整体在 P2 一个 commit 内删除，`git revert` 即恢复。

---

### P3 · 信息架构重构（预计 5–8 天，最大工作量）

**目标**：把"三路由 + 三栏工作台"改成与鸿蒙 5 个一级入口同构的桌面布局。

**涉及文件/目录**
- 新增 `dashboard/src/layouts/AppLayout.vue`（侧栏 + 内容区）、`src/components/layout/SideNav.vue`（5 项，图标 24 grid，未选中 `--text-secondary`、选中 `--color-primary`，与鸿蒙 `tab_*.svg` 同语义）、`src/components/layout/PageHeader.vue`（对齐 `PageHeader.ets`）
- 新增 `src/components/common/EmptyState.vue`、`LoadingSkeleton.vue`、`ErrorRetry.vue`（对齐鸿蒙 `PlaceholderView/SkeletonView/ErrorRetryView`）
- 改 `src/router/index.ts`：`/login`、`/workbench`（默认重定向）、`/media`、`/reports`、`/reports/:mediaId`、`/stats`、`/profile`
- 新增 `src/views/WorkbenchView.vue`（12 栅格重排，映射鸿蒙 7 卡）、`src/views/MediaLibraryView.vue`、`src/views/ReportsView.vue`、`src/views/ReportDetailView.vue`、`src/views/ProfileView.vue`
- 改 `src/views/StatsView.vue`：去 4 张彩色 KPI 卡（改 1 张 hero 渐变卡 + 3 张中性小卡，对齐鸿蒙 `kpiHeroHeight 106 / kpiSmallHeight 78`）、删 `ModelMetricsCard` 彩色数值、`RecentReportsTable` 迁到 `/reports`
- 改 `src/views/AnalysisView.vue` → `WorkbenchView.vue`：删三栏 `grid-template-columns: 248px 1fr 400px`（`:69-77`），改 12 栅格
- 改 `src/components/right-panel/RightPanel.vue`：**删除 `el-tabs` 三 tab**（`:12-22`），拆成独立卡片
- 改 `src/components/right-panel/HistoryPanel.vue` + `ComparisonModal.vue`：迁入 `/reports` 与 `/reports/:mediaId`

**工作台 12 栅格映射表（对齐 `WorkbenchPage.ets:1118-1185` 的卡片顺序）**

| 栅格行 | 内容 | 跨度 | 鸿蒙对应 |
|---|---|---|---|
| 页头（非卡片） | 标题「工作台」+ 问候·日期 + 刷新 | 12 | `pageHeader()` |
| 离线提示（条件） | 无法连接服务器 + 重试 | 12 | `offlineBanner()` |
| A | 本次评估 hero（进度/BDI/严重度/重新分析/取消） | 8 | `AnalysisHeroCard` |
| A | 开始新的辅助评估 | 4 | `StartAssessmentCard` |
| B | 注意力热力图（帧缩略条 + 大图 + 回到最新 + 单帧重推理） | 7 | `AnalysisHeatmapCard` |
| B | 情绪曲线 | 5 | `EmotionCurveCard` |
| C | 严重度分布 | 4 | `SeverityDistributionCard` |
| C | 智能解读 | 4 | `AnalysisVlmCard` |
| C | 诊断意见 | 4 | `DiagnosisOpinionCard`（P4 实现） |

- 断点：≥1280 用上表；1024–1279 A/B 全宽、C 两列；768–1023 单列 + 侧栏折叠为图标条；<768 侧栏改抽屉。

**验收标准**
1. 主导航 5 项与鸿蒙 `MAIN_TABS`（`PageRoutes.ets:79-90`）**名称、顺序、图标语义**逐条一致（工作台/素材库/历史报告/统计/我的）。
2. `/media`、`/reports`、`/stats`、`/profile` 四个新页面均可独立访问（直接输入 URL 不白屏）；未登录统一跳 `/login?redirect=`。
3. 工作台卡片在渲染顺序上与 `WorkbenchPage.ets:1118-1185` 一致；无「查看目标」时 B/C 两行不渲染（对齐 `:1149`）。
4. 工作台不再出现 `el-tabs`；`grep -rn "el-tabs" src` → 0 行。
5. 1280×800 / 1024×768 / 768×1024 三个视口无横向滚动、无内容溢出（截图三张留档）。
6. 侧栏切换页面 ≤2 次点击可达任意一级页。

**风险 / 回滚**
- 风险 1：P3 会同时动路由、布局、组件归属，是本计划中**唯一无法按组件单独回滚**的阶段 → 强制要求 P3 前两个阶段的 tag 已打，且 P3 拆 3 个 commit（路由+布局骨架 / 工作台重排 / 三页面迁移），每个 commit 都可独立 revert。
- 风险 2：`/` 从统计页改为工作台，**外部书签与文档里的链接会失效** → `router` 里保留 `/` 重定向；若必须保持"首页=统计"，改为 `/` = `/workbench` 并把统计留在 `/stats`，二选一需用户确认。
- 风险 3：`MediaLibrary.vue`/`HistoryPanel.vue` 迁出后，`AnalysisView` 里对 `store.selectedMediaId` 的依赖会形成"跨路由共享状态"耦合 → 工作台与素材库共享同一 Pinia store，素材库"打开"动作 = `select + 跳 /workbench`，与鸿蒙 `MainPage.openMedia(mediaId)` 行为一致。
- 回滚点：tag `ui-p3a / p3b / p3c`，任一步可用 `git revert <commit>` 退回上一可用形态。

---

### P4 · 功能对齐补齐（预计 5–8 天）

**目标**：把 §1.4 差异表里 15 项「缺」逐条补齐；Web 独有能力（PDF/对比/摄像/单帧重推理）保持可用。

**涉及文件/目录**
- `src/api/index.ts`：新增 `uploadMedia(file, patient)`（`POST /api/upload/image?patient=`）、`renamePatient(id, patient)`（`PUT /api/media/{id}/patient`）、`fetchReportDetail(mediaId)`（`GET /api/report/{media_id}`）、`sendCode(email)`；**注意** `ReportApi.ets:5` 记明 `/api/report/{media_id}` 的 path 参数是 **int**，Web 侧必须 `Number(mediaId)`
- `src/api/auth.ts`：`sendCodeApi`
- `src/stores/dashboard.ts`：加 `cancelAnalysis()`、`offline` 状态、`retry()`
- `src/components/left-panel/MediaLibrary.vue`：加搜索（名称/患者）、排序（时间/姓名）、按患者分组（复刻 `MediaLibraryPage.ets:476-566` 的 `buildGroups/patientSummaryOf/groupTitleOf` 语义）、重命名患者、上传时录入患者名
- `src/views/ReportsView.vue`：严重度/类型筛选（对齐 `ReportsPage.ets:454/480`）、关键字搜索、按素材分组、分页"加载更多"、清除筛选、"只展示服务端已保存报告"说明文案
- `src/views/ReportDetailView.vue`：`GET /api/report/{media_id}` + 逐帧热力图（若本机有会话）+ 智能解读；把 `ComparisonModal` 作为该页的"与另一次评估对比"入口
- 新增 `src/components/right-panel/DiagnosisOpinionCard.vue`：**优先复用已有** `src/utils/diagnosisOpinion.ts` 的 `buildEvidence/buildAiDraft/isSameSnapshot/OPINION_MAX_LEN`（218 行、0 引用，等于白写），只补 UI 与状态；再复刻 `harmony/.../components/analysis/DiagnosisOpinionCard.ets` 的字段（`conclusion / aiDraft / evidence / doctorName / status / scoreText / severityLabel / severityColor / timeText / ready / emptyHint / mediaId`）与文案「模型辅助生成 · 需医师复核后生效」「仅本次会话有效，未写入报告」
- 新增 `src/views/ProfileView.vue`：账号信息（用户名/邮箱/注册时间）+ 退出二次确认（对齐 `ProfilePage.ets:167-243`，用 `ConfirmSheet` 语义；**当前 header 直接 logout，无确认**）
- `src/components/layout/DashboardHeader.vue`：退出改为仅跳 `/profile`，不再直接登出
- `src/views/WorkbenchView.vue`：接 `cancelAnalysis`（`AnalysisHeroCard` 原文案「取消分析」+ 提示「视频分析在服务端处理得很快，取消可能不会生效」）
- `src/views/LoginView.vue`：加"忘记密码"入口（`send-code`）+ 服务端不可达引导（对齐 `LoginPage.ets` 的退出码 0/1/2/3 分流）

**验收标准**
1. §1.4 表中 1–16 项逐条勾选，每项附一次实际操作截图。
2. 上传带患者名后，鸿蒙端素材库能看到同一患者分组（跨端一致性实证）。
3. `/reports/:mediaId` 能打开历史报告；后端 422 场景（传字符串 mediaId）在 Web 侧已被 `Number()` 规避。
4. 「诊断意见」卡在无数据时显示空态、有数据时显示 AI 初判 + 医师意见可编辑，且**不写库**（与鸿蒙一致）。
5. Web 独有能力回归通过：PDF 导出、双报告对比、摄像头录制上传、单帧热力图重推理。

**风险 / 回滚**
- 风险 1：Web 无本地 DB，「离线可用」只能做到提示+重试，做不到鸿蒙的缓存读取 → 需在验收里明确"Web 不做离线数据能力"，避免被认为未完成。
- 风险 2：「诊断意见」涉及医疗文案与"需医师复核"免责，Web 文案必须与鸿蒙逐字一致，否则出现两端合规差异。
- 风险 3：`PUT /api/media/{id}/patient` 鸿蒙注释写明"鸿蒙 RequestMethod 无 PATCH，用 PUT"，Web 直接 PUT 无额外风险，但需确认后端允许 `patient` 为空串（清空患者名）的行为。
- 回滚点：P4 每项功能一个 commit（共 15 个），可逐项单独 revert，互不阻塞。

---

### P5 · 细节收口与可访问性（预计 3–4 天）

**目标**：把一致性、可访问性、响应式、状态完备性做到可验收。

**涉及文件/目录**
- `src/styles/tokens.css`：补 `--focus-ring: 0 0 0 3px rgba(13,148,136,0.35)`（鸿蒙 `focus-visible` 无对应常量，Web 需补），键盘焦点环统一
- 全站：触达目标 ≥44×44（当前 header 的 `demo-btn`/`logout-btn` 为 `el-button size=small text`，实测高度 <32px）
- 全站：`@media (prefers-reduced-motion: reduce)` 关掉 `--motion-enter` 与错峰
- 全站：支持 200% 文本缩放不破版（重点查 `--header-height 56` 与 `font-size 32` 的 KPI 卡）
- `src/composables/usePdfExport.ts`：71 处硬编码色值改为新令牌（PDF 不能读 CSS 变量，抽 `tokens.ts` 常量注入模板）
- `src/components/right-panel/EmotionCurve.vue`：单点判定（`:19` `isSinglePoint` → 水平直线 + 说明文案）已与 BUG-13 的 Web 侧要求一致，**保留不动**，仅换配色与字号
- `src/api/baseResolver.ts`：`warmUpApiBase()` 的探测失败态接 `ErrorRetry`（对齐鸿蒙登录页"服务端不可达"分流）

**验收标准**
1. axe DevTools 三个主页面 + 登录页：**critical/serious 违规 0 条**（P1 要求 contrast 0 条，此阶段为全量 0 条）。
2. 纯键盘可完成：登录 → 选素材 → 分析 → 看报告 → 退出；焦点顺序合理，焦点可见。
3. `prefers-reduced-motion` 生效时无入场动画。
4. 浏览器 200% 缩放 + 768px 视口无横向滚动、无文字截断。
5. PDF 导出结果与屏幕端配色一致（抽 1 份样张比对）。

**风险 / 回滚**
- 风险：焦点环 `rgba(13,148,136,0.35)` 在深色卡片上可能不明显；PDF 令牌注入漏项会导致导出样式回退。
- 回滚点：P5 全为增量样式/属性，单 commit 可 revert，不影响 P0–P4。

---

## 四、总验收表（要求 → 阶段 → 可测指标）

| 用户要求 | 落地阶段 | 指标 |
|---|---|---|
| (1) 与鸿蒙视觉/交互统一 | P0 + P1 + P3 | 令牌值 100% 来自 `UiTheme.ets`；导航 5 项同名同序；工作台卡片顺序一致；动效节拍取 `pressDuration 120` / `stagger 55ms` |
| (2) 去掉 AI 生成感 | P1 + P2 | 渐变 2 处白名单；`backdrop-filter/shadowBlur` = 0；圆角 4 档；字号 6 档；裸色值 0；假数据路径 0；伪图表 3 处清除 |
| (3) 对齐鸿蒙新功能 | P3 + P4 | §1.4 差异表 24 项全部有结论；15 项「缺」补齐或被明确标注为"Web 不做" |
| (4) 优化 IA 与 UI 细节 | P3 + P5 | 任意一级页 ≤2 次点击；三视口无溢出；axe 0 违规；键盘全流程可达 |

---

## 五、需用户拍板的 3 个决策点

1. **演示模式去留**：全删（最干净）／降级为 `/demo` 独立路由 + 常驻标注横幅（推荐——P2 已按此写）／保留现状。
2. **首页归属**：`/` → `/workbench`（与鸿蒙"工作台"为第一页签一致，推荐）／`/` 保持统计概览。
3. **Web 是否要离线缓存**：不做（推荐，仅提示+重试）／做 localStorage 轻量缓存（对齐鸿蒙 DAO，但 Web 无 SQLite，收益/成本比低）。

---

## Plan Verification

- **Mode**: fact-check（fallback —— logicprobe 插件未安装）
- **验证方式**：对本文全部可核验断言逐条回到代码取证，取证命令为 `grep`/`read`，不修改任何文件。
- **Claims checked**: 首轮 26 confirmed / 0 refuted / 1 unverifiable；第二轮独立复算 12 条 → 8 confirmed / 0 refuted / 3 处计数偏差 / 1 处结论不完整（均已在正文就地修正）
- **Escalation**: model verification NOT run（需 logicprobe 插件）；对比度数值为按 WCAG 2.1 相对亮度公式手工计算的对 #FFFFFF 结果，属"可复算但未用工具二次验证"，建议 P1 阶段用 axe/APCA 工具复核一遍再定稿。

### 逐条核验记录（摘要）

| 断言 | 证据 | 结论 |
|---|---|---|
| Web 只有 3 条路由 | `dashboard/src/router/index.ts` 全文 | confirmed |
| 鸿蒙一级页签 5 个：工作台/素材库/历史报告/统计/我的 | `harmony/entry/src/main/ets/pages/PageRoutes.ets:79-90` `MAIN_TABS` | confirmed |
| 鸿蒙令牌集中定义于 `UiTheme.ets`（435 行） | `harmony/entry/src/main/ets/common/UiTheme.ets` | confirmed |
| `severityColors` 为 4 个淡彩值 | `dashboard/src/stores/dashboard.ts:37-42` | confirmed |
| 空素材自动加载演示数据 | `dashboard/src/components/left-panel/MediaLibrary.vue:42` `store.loadDemoData()` | confirmed |
| 假数据生成器 3 个函数存在 | `stores/dashboard.ts:382-394 / 396-439 / 441-456` | confirmed |
| header 有「加载演示数据」按钮 | `DashboardHeader.vue:86-94` | confirmed |
| `CloudTopology` 节点为硬编码常量 | `CloudTopology.vue:51-92`（3 个 data 项 + 2 个 links，均为字面量） | confirmed |
| `subScales` 由总分乘系数倒推 | `DiagnosisReport.vue:91-101`（`total*0.48`、`total*0.35`） | confirmed |
| Web 未调用 `GET /api/report/{media_id}` | 全 `src` grep `"/api/report/"` 命中 0 | confirmed |
| Web 未调用 `PUT /api/media/{id}/patient` | 全 `src` grep `"/patient"` 命中 0 | confirmed |
| Web 未调用 `POST /api/auth/send-code` | 全 `src` grep `"send-code"` 命中 0 | confirmed |
| 后端存在上述 3 个端点 | `backend/routers/{report,media,auth}.py` 装饰器清单 | confirmed |
| Web 无取消分析入口 | 全 `src` grep `取消|cancel|abort` 仅命中对话框/RAF | confirmed |
| Web auth 无 401 全局处理 | `src/stores/auth.ts` 全文，`loadUser` catch → `logout` | confirmed |
| `.vue/.ts` 裸色值 118 处 / `style.css` 55 处 | `Select-String '#[0-9a-fA-F]{6}'` 计数 | confirmed |
| `rgba(` 裸用 70 处 | 同上计数 | confirmed |
| `border-radius` 16 种取值 | 分组计数（含 `!important` 变体） | confirmed |
| `font-size` 14 种取值，9–11px 共 47 处 | 分组计数（11px×35、10px×10、9px×2） | confirmed |
| `.glass-card` 用于 10 个组件 | 分组计数 10 个 `.vue` 各 1 次 | confirmed |
| 渐变 12 处（含白名单外 10 处） | `grep linear-gradient` 逐条列点 | confirmed |
| `--accent-violet` 0 引用 | 全局 grep 仅定义处 1 命中 | confirmed |
| 鸿蒙严重度色 `#16A34A/#0284C7/#D97706/#DC2626` | `harmony/entry/src/main/ets/types/constant.ts` `severityMeta()` | confirmed |
| 鸿蒙统计切片色 `['#17B26A','#2E6BE6','#F79009','#F04438']` | `UiTheme.ets` `severityPieColors` | confirmed |
| `/api/report/{media_id}` 的 path 参数必须是 int | `harmony/entry/src/main/ets/network/ReportApi.ets:5` 注释 | confirmed |
| Web `EmotionCurve` 已实现单点水平直线（BUG-13 的 Web 侧要求已满足） | `EmotionCurve.vue:19` `isSinglePoint` + `:88/:101` 文案 | confirmed |
| 「对比度 2.56:1 / 3.74:1 / 1.2:1」等数值 | WCAG 2.1 相对亮度公式手算 | unverifiable（未用工具复核，见 Escalation） |

### 第二轮独立复算（2026-10-22，主理人复跑计数命令）

| 断言 | 复算命令 | 实测 | 处置 |
|---|---|---|---|
| 渐变 12 处 | `Select-String "radial-gradient"` 计数 → 3；`linear-gradient` → 11 | **14 处** | 已改 §1.5 与 §2.8 |
| `border-radius` 16 种取值、2 处 `!important` | 取值去重 | **15 种取值，其中 3 处 `!important`** | 已改 §1.5 |
| `font-size` 14 种取值、9–11px 共 47 处 | 取值去重 + 区间计数 | **15 种（漏 `20px`）、9–11px 共 55 处** | 已改 §1.5、§2.3 |
| `.vue/.ts` 裸色值 118 处 | `#[0-9a-fA-F]{6}` 计数 | 118 | confirmed |
| `.glass-card` 10 个组件 | 按文件去重 | 10 | confirmed |
| Web 仅 3 条路由 | `router/index.ts` 全文 | `/login` `/` `/analysis` | confirmed |
| 鸿蒙 5 页签名称与顺序 | `PageRoutes.ets:79-90` `MAIN_TABS` | 工作台/素材库/历史报告/统计/我的 | confirmed |
| 严重度色为 4 个淡彩 | `stores/dashboard.ts:37-42` | `#f2f3b2/#b2f3cd/#b2c3f3/#f3b2bd` | confirmed |
| 空库自动灌演示数据 | `MediaLibrary.vue:42` → `store.loadDemoData()` | 确认，另有 `DashboardHeader.vue:91` 按钮 | confirmed |
| 伪图表 `total*0.48/0.35` | `DiagnosisReport.vue:95-96` | 确认，**且 `utils/diagnosisOpinion.ts:52-53` 有第二份副本** | 结论不完整 → 已补 §1.4 第 12 项与 P2 |
| Web 未调用 `/api/report/`、`/patient`、`send-code` | 三组 grep | 0 命中 | confirmed |
| 后端/鸿蒙无 subscale 字段 | `sub_?scale` grep | 0 命中 | confirmed（支撑 P2 删除倒推） |

---

## 实施记录（2026-10-22）

### 阶段状态

| 阶段 | 状态 | 验收方式 |
|---|---|---|
| P0 令牌单源 | 完成 | `check-tokens.mjs` [A]0 / [E]69↔69 |
| P1 去 AI 感 | 完成 | 裸色值 118→93、圆角 24→4、渐变 14→0 |
| P2 清假数据 | 完成 | 裸色值→84、演示数据只剩 `/demo` 一处 |
| P3 信息架构 | 完成 | 7 路由 + 5 项侧栏 + 12 栅格，`el-tabs` 0 |
| P4a 素材库 | 完成 | 搜索/排序/按患者分组/上传带患者名/改所属患者/视频回看 |
| P4b 报告与账号 | 完成 | 三条闸门 0；390 卡片化、详情接 API、诊断意见卡 |
| P5 可访问性收口 | 完成（证据由主理人补测） | 裸色值 81→35、主按钮 3.74→5.47:1、回流全绿 |

### P4b 后端能力事实核对（决定了哪些「差异」根本做不了）

| 能力 | 真实事实 | 依据 |
|---|---|---|
| `GET /api/reports` 参数 | 只有 `severity` / `media_type` / `page` / `limit(1–100)`，**没有 keyword** | `backend/routers/report.py:42-50,87`、`backend/schemas.py:113-129` |
| `GET /api/report/{media_id}` | 路径参数 **int**，返回 **`list[ReportOut]`** 而非单对象 | `report.py:15-20`、`schemas.py:89-98` |
| `ReportOut` 字段 | 只有 `id/media_id/bdi_score/severity/detected_at/inference_time_ms/notes`，**无帧、无 VLM 原文、无素材名** | `schemas.py:89-98` |
| VLM / notes 是否落库 | `notes` 从未写入；VLM 仅在分析 WS 会话内发送，不落库 | `ws.py:222-234`、`ws.py:251-253` |
| 重置密码接口 | **不存在**；auth 只有 `send-code/register/login/me`，且 `send-code` 对已注册邮箱直接 409 | `auth.py:44/62/95/109`、`auth.py:54-56` |
| 注册要求 | `UserRegister` 必填 `verification_code`（旧前端没传 → 422），已补发送验证码 + 6 位输入 | `schemas.py:7-17` |
| `/media` 冲突根因 | 后端把静态文件挂在 `/media`：`main.py:72`，所以 SPA 路由不能再用 `/media` 前缀 | `backend/main.py:72` |

因此以下三项**不是 UI 漏做，是后端没有数据/接口**，页面一律用空态如实说明、不伪造：

1. **忘记密码**：无 reset 接口 → 只显示「当前版本未开放自助重置密码，请联系系统管理员处理」，不做点了没反应的按钮。
2. **报告详情的逐帧热力图 / VLM 原文**：`ReportOut` 不返回，VLM 不落库 → 详情页诚实空态，`storedVlmRaw` 留了接入口。
3. **报告关键字搜索**：无 `keyword` 参数 → 客户端在 `page=1&limit=100` 全量拉取后本地过滤，命中数只报真实拉到的条数。

其余事实：`dashboard/backend/media/` 目录是空的，**所有旧素材记录对应的文件都已丢失，无法重新跑分析**（非本计划引入）；P4b 为验证推理链路临时上传过一个人脸样本（id 59，WS 返回 12.74 → 页面取整 13）后已删除，报告总数恢复 130。

### P5 可访问性实测（P5 子智能体跑到 80% 中断，以下由主理人补测）

| 项 | 结果 | 证据 |
|---|---|---|
| 主按钮白字对比度 | 常态 **5.47:1**、hover 6.42、active 7.35（原 `#0D9488` 上白字 3.74 不达 AA） | 新增 `--color-primary-button: #0F766E`，`tokens.css`/`tokens.ts` 成对 |
| 侧栏选中项文字 | 3.48 → **5.09:1** | 改用 `--color-primary-text` |
| 回流（WCAG 1.4.10） | 320 / 360 / 390 / 720 / 1440 × `/workbench` `/library` `/reports` `/stats` `/profile` `/demo`：**页面级横向滚动 0**，溢出元素 0 | `_backup/ui-check/audit.json` |
| 焦点可见 | 全局 `:focus-visible` 2px + 2px offset；报告行补 `tabindex` + Enter/Space | 6 张焦点截图 |
| 减弱动效 | `prefers-reduced-motion: reduce` 下 `runningAnimations: []`，两个 ECharts `animation:false` | CDP `setEmulatedMedia` 实测 |
| 图片兜底 | 加载失败 → 类型图标 + 「预览不可用」，尺寸不跳动 | 1440/1024/390 截图 |
| PDF 色值 | `usePdfExport.ts` 68 处裸值收敛为 22 色 `PDF_COLORS` 常量表（canvas 读不到 CSS 变量，必须留真实色值） | checker [B] 81→35 |
| 触达目标 | 页头按钮已 44×44；**素材卡 26×26 图标按钮、筛选 chip 32–36px 仍偏小**（符合 WCAG 2.2 AA 的 24×24 下限，未达 AAA 44×44） | `audit.json` small-target 项 |
| 唯一低对比命中 | 侧栏品牌块「MS」≈2.6:1，属 WCAG 1.4.3 的 **logotype 豁免**，且 `aria-hidden` + 外层 `aria-label` 已给文本替代 | `audit.json` low-contrast 项 |

**未做**：PDF 导出的视觉实测（html2canvas 在无头环境跑通但未人工比对样张），故 PDF 排版仍属"未验证"。

### 闸门实测（`dashboard/`，均为 exit 0）

```text
node node_modules/vue-tsc/bin/vue-tsc.js --noEmit -p tsconfig.app.json   → 0
node node_modules/vite/bin/vite.js build                                 → 0（dist 产出，1.6s）
node scripts/check-tokens.mjs --strict                                   → 0
```

P0 时被增量 `tsbuildinfo` 掩盖的 10 条既有类型错误（`ComparisonModal` / `HistoryPanel` / `RecentReportsTable` / `MediaLibrary` / `DiagnosisReport`）已在 P1 用 `severityColorOf()` / `severityTextColorOf()` 收窄修掉，未使用 `any` 或 `@ts-ignore`。

### 实施中发现并修掉的真实缺陷（不在原计划里）

1. **`/media` 路由被 dev 代理吃掉**：`vite.config.ts` 的 `'/media': BACKEND` 前缀转发与 SPA 路由 `/media` 冲突，后端返回 404，页面白屏（`#app` 根本没挂载）。已把路由改为 `/library`（`router/index.ts`、`SideNav.vue`、`AssessmentHeroCard.vue`、`StartAssessmentCard.vue`）。**生产环境若用 nginx 同前缀反代，同样会中招。**
2. **视频回看能力回退**：P3 清掉旧 `MainVideoPlayer.vue` 后工作台没有任何播放器。已在 `AttentionHeatmapCard` 加「注意力热力图 / 原始视频」分段并重写播放器。
3. **窄屏报告表内容被截断**：390px 宽下 `el-table` 时间列被切（实测 364 个元素超出视口）。列入 P4b。
4. **图片加载失败无兜底**：素材缩略图 `img` 的 alt 文本直接铺满卡片。列入 P5。

### 视觉验证（沙箱解锁后新增能力）

会话中途获取了完整磁盘/进程权限，因此可以真实启动 `vite dev` + 无头 Chrome（CDP）截图。截图与探针数据在 `_backup/ui-check/`：

- `fix-1440-workbench.png` / `lib-1440.png` / `wb-pop-1440.png` / `lib-390.png` / `wb-pop-390.png` / `390-reports.png` 等
- `report.json`：每页 `scrollWidth/clientWidth`、超出视口元素数、控制台输出
- 结论：1440 / 1024 / 390 三档均**无页面级横向滚动**；页面级 overflow 0；例外是 390 宽的报告表格内部溢出（见上第 3 条）。

### 环境限制（仍然存在）

- 本会话无法 `git commit`：`.git/index.lock` 创建被拒（沙箱层）。回滚依赖 `_backup/web-ui/<stage>-before/` 快照。
- 中途一度无法删除文件，只能留空壳；权限放开后 8 个空壳已实际删除（`AnalysisView` / `DashboardHeader` / `AnalysisStatusBar` / `CenterPanel` / `RightPanel` / `CloudTopology` / `StatCard` / `__delete_probe.tmp`）。

