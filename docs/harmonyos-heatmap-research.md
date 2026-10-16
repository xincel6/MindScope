# HarmonyOS NEXT (API 12~23 / ArkTS) 热力图叠加图像 —— 现成三方库与官方能力调研

> 调研目标：在 HarmonyOS NEXT 手机端、ArkTS、Stage 模型、compileSdk/targetSdk = 6.1.0(23) 的工程里，
> 把 128×128 人脸底图 + 16×16 浮点矩阵（0..1）渲染成 jet 色带（蓝→青→绿→黄→红）半透明（≈0.4）热力图叠加层，
> 再叠加虚线矩形框 + 文字标注，底部再加一条渐变色带 colorbar。
>
> 检索轮次：ohpm 中心仓 API 直查（关键词 热力/热度/heat/heat map/heat-map/chart/图表/canvas/colormap/colorbar/
> pixelmap/drawing/图像合成/图片叠加/3d/图形 等 20+ 个关键词）+ 中英文 web 搜索 15 轮以上。

---

## 一、结论速览

1. **没有「端到端可直接拿来用」的现成库。** ohpm 中心仓（OpenHarmony 三方库中心仓）里用 `热力`、`热度`、`heat`、`heat map`、`heat-map`、`colormap`、`colorbar` 等关键词检索，**唯一命中 heatmap 的包是 `@ohmos/activity_overview`**（GitHub 贡献格子风格的日历热力图，1.0.1，97 次下载，24KB），**它不是矩阵热力图，也不支持叠加图片**，不可用。
   - 检索入口：<https://ohpm.openharmony.cn/>
   - `@ohmos/activity_overview` 描述：*"A GitHub-like contribution graph component for HarmonyOS Next."*，关键词 `calendar, heatmap, github, contribution, activity`

2. **`@ohos/mpchart`（含你正在用的 3.0.30）确认没有 HeatmapChart。** 我直接读取了库对外入口文件源码（`library/index.ets`，约 15KB 导出表），已导出图表组件只有：
   `BarChart / CandleStickChart / LineChart / RadarChart / HorizontalBarChart / BubbleChart / PieChart / ScatterChart / CombinedChart / WaterfallChart`
   —— **全文不含任何 `heat` 字样**。其 CHANGELOG 从 1.0.0 到 4.0.0-rc.1 也从未出现过热力图条目。华为官方优选三方库介绍也明确写的是「线形/柱状/饼状/蜡烛/气泡/雷达/瀑布 7 大类」。**不要指望 mpchart 能画热力图。**
   - 源码证据：<https://gitee.com/openharmony-tpc/ohos_mpchart/raw/master/library/index.ets>
   - CHANGELOG：<https://gitee.com/openharmony-tpc/ohos_mpchart/blob/master/CHANGELOG.md>
   - 华为官方介绍：<https://developer.huawei.com/consumer/cn/blog/topic/03221825816621099>

3. **唯一「图表库自带 heatmap 类型」且原生 ArkTS 的候选是 `@visactor/harmony-vchart`**（VisActor VChart 鸿蒙版，1.13.5，MIT）。VChart 官方文档的图表类型侧边栏里确实有「热力图」页面，所以 VChart 家族支持 heatmap。**但它是通用统计图表库**，把 16×16 注意力矩阵当背景图+叠加框+colorbar 的那套极客用法，需要在图表 spec 里想办法塞进去，是否顺滑**未找到公开资料**证明。
   - VChart 图表类型列表（左侧目录含「热力图」）：<https://www.visactor.com/vchart/guide/tutorial_docs/Chart_Types/chart_types>
   - VChart Heatmap 文档：<http://www.visactor.io/vchart/guide/tutorial_docs/Chart_Types/Heatmap>
   - VChart 鸿蒙版说明：<https://www.visactor.com/vchart/guide/tutorial_docs/Cross-terminal_and_Developer_Ecology/harmony>

4. **ECharts 路线的可行路径已经存在，但走的是「Canvas 内跑 echarts 内核」而非 WebView**：`@wuyan/hm_chart`（基于 echarts 5.5.1 适配）。我读了它的源码，`hmChart` 组件内部是 **ArkUI 原生 `Canvas(this.context)` + `CanvasRenderingContext2D`**，把 echarts 跑在原生 Canvas 上，不是 WebView 内嵌。而 WebView 内嵌 echarts 是社区普遍做法并有官方论坛讨论。
   - `@wuyan/hm_chart`：<https://gitee.com/dssasdadssdfsdfs/hm_chart>
   - 组件源码（`Canvas` + `CanvasRenderingContext2D`）：<https://gitee.com/dssasdadssdfsdfs/hm_chart/raw/master/hm_chart/src/main/ets/components/MainPage.ets>
   - WebView 内嵌 echarts 讨论：<https://developer.huawei.com/consumer/cn/forum/topic/0203166979128830238>、<https://developer.huawei.com/consumer/cn/forum/topic/0204157989239546351>

5. **官方能力完全够用，而且社区已有「鸿蒙 + Canvas 画热力图 + 颜色映射」的官方答复代码。** 华为开发者论坛有一条问答，官方答复给出了完整可跑代码：**离屏 Canvas 画灰度/透明度场 → `getImageData` 逐像素做颜色映射 → `putImageData` 画回主 Canvas**，色带映射就用「蓝→绿→黄→红」分段。这与你需要的「矩阵 → 色彩映射 → 叠加」几乎一一对应。
   - <https://developer.huawei.com/consumer/cn/forum/topic/0203208726669479239?fid=0109140870620153026>

6. **推荐结论：不要找库，用 ArkUI 原生 `Canvas` / `OffscreenCanvas` 自绘。** 你的需求（16×16 矩阵、jet 色带、0.4 透明叠加、虚框、文字、colorbar）在 ArkUI 2D Canvas 上属于低复杂度任务，估 200~400 行 ArkTS 就能做完，且零依赖、零包体积、性能可控（16×16 = 256 次矩形填充即可，甚至不需要逐像素）。引入 echarts/VChart 反而要付出 0.6MB~数 MB 包体积、跨 JS 引擎边界、无法直接访问底图坐标系、定制成本更高的代价。

---

## 二、候选方案逐条评估

### 方案 1：`@visactor/harmony-vchart`（VisActor VChart 鸿蒙版）—— 唯一自带 heatmap 的原生 ArkTS 图表库

| 项 | 内容 |
|---|---|
| 名称 | `@visactor/harmony-vchart` |
| 来源链接 | <https://ohpm.openharmony.cn/>（版本 1.13.5，MIT）；文档：<https://www.visactor.com/vchart/guide/tutorial_docs/Cross-terminal_and_Developer_Ecology/harmony>；图表类型：<https://www.visactor.com/vchart/guide/tutorial_docs/Chart_Types/chart_types> |
| 支持 HarmonyOS NEXT ArkTS | ✅ 是。官方文档专设 "Harmony VChart" 章节，定位为「针对 harmonyOS 打造的图表库，拥有近 20 种图表类型，以及**原生的渲染性能**」（对比 Web 版需 WebView 的路线） |
| 能力覆盖度 | **热力图本身：✅**（VChart 图表类型目录含「热力图」）。**16×16 矩阵 → 色彩映射：✅**（heatmap 图表本质就是二维矩阵按色带映射）。**叠加在 128×128 人脸底图上：⚠️ 未找到公开资料** —— 需要靠图表库自身的背景图/自定义 mark/annotation 能力实现，不是热力图组件的默认行为。**虚线矩形框 + 文字标注：⚠️** 需要依赖 annotation 类能力。**底部渐变色带 colorbar：⚠️** VChart 热力图文档建议自行查证是否内置 colorbar/visualMap 组件 |
| 集成成本 | 中。`ohpm install @visactor/harmony-vchart`，写 VChart spec（JSON）即可出热力图；但要把「底图 + 框 + 标注 + colorbar」拼进同一 spec 需要熟悉 VChart 的 annotation / customMark / 布局，学习曲线比手写 Canvas 陡 |
| 风险与坑 | ① 包体积（VChart 系列体量不小，具体数值未在本次检索中获得，建议 `ohpm install` 后实测）；② 一旦图表库的坐标轴、标题、padding 介入，把 16×16 网格精确对齐到 128×128 底图的像素坐标会很别扭，通常要关掉全部轴和 padding 自己控；③ 未找到「用 harmony-vchart 做注意力热力图叠加人脸」的任何公开案例；④ 版本 1.13.5 与 VChart 2.x web 版存在版本代差，文档示例以 web 版为主 |
| 结论 | **可以作为「如果我必须用图表库」的首选候选，风险中等**。建议先花半天做一个 POC：只验证「heatmap spec + 关轴 + 精确铺满一个 128×128 区域」。若 POC 顺利就继续；不顺利立刻转方案 4。 |

### 方案 2：`@wuyan/hm_chart`（ECharts 5.5.1 鸿蒙适配，跑在原生 Canvas 上）

| 项 | 内容 |
|---|---|
| 名称 | `@wuyan/hm_chart`（源码仓库名 `openharmony_echarts`） |
| 来源链接 | <https://gitee.com/dssasdadssdfsdfs/hm_chart>；安装：`ohpm install @wuyan/hm_chart`；组件源码：<https://gitee.com/dssasdadssdfsdfs/hm_chart/raw/master/hm_chart/src/main/ets/components/MainPage.ets> |
| 支持 HarmonyOS NEXT ArkTS | ⚠️ 是 ArkTS HAR 包，但**最后一次提交在 2 年前**，仓库 README 写「适配 OpenHarmony」，未标注 HarmonyOS NEXT / API 12+ 验证。DevEco 5.0 / API 12 上能否直接编译**未找到公开资料** |
| 能力覆盖度 | **热力图：✅ 理论上**（echarts 5.5.1 原生有 `series.type='heatmap'` + `visualMap` 渐变色带，正好对应你要的 colorbar）。**16×16 → 色彩映射：✅**。**叠加在图片上：✅ 理论上**（echarts 支持 `graphic` 图片元素和 `xAxis/yAxis` 用 `type:'value'` 精确控坐标）。**虚框 + 文字：✅**（`graphic` 或 `markArea`/`markPoint` + `label`） |
| 集成成本 | 低（如果它能编译）。安装后 `import { hmChart, ChartOptions, hmChartType } from '@wuyan/hm_chart'`，直接喂 echarts option，生态资料极多 |
| 风险与坑 | ① **实测发现：`MainPage.ets` 内部是 ArkUI 原生 `Canvas` + `CanvasRenderingContext2D`，把 echarts 内核跑在原生 Canvas 上**（这既是优点：无 WebView 开销、原生渲染；也是风险：echarts 依赖 DOM 环境，作者做了一层 Canvas shim，未覆盖的 API 到你的场景可能直接报错）；② 仓库 **6 star、6 fork、9 个 open issue**，社区极小，**维护基本停滞**（最近 issue 是 1 年前）；③ 报出的问题里有「Series data 数据类型限制」「点击事件绑定问题」，说明封装不完整；④ 无 HarmonyOS NEXT / API 12+ 的验证记录，你还要用 API 23 工程，**编译期风险不低**；⑤ 包体 612KB / 36 文件 |
| 结论 | **不推荐作为主方案。** 如果愿意赌，可以先花 1 小时 `ohpm install` 验证它能否在你的 API 23 工程里编译通过——能通过再考虑用 `heatmap` + `visualMap`；否则立刻放弃。 |

### 方案 3：WebView 内嵌 ECharts（H5 方案）

| 项 | 内容 |
|---|---|
| 名称 | ArkWeb（`Web` 组件）+ echarts.js，或 npm 侧 `@wolfx/echarts_adaptor` / `@serene/echarts` / `@liuming/echarts` / `@wuyan/hm_chart`（WebView 与 Canvas 封装并存，需逐个确认） |
| 来源链接 | 官方问答：<https://developer.huawei.com/consumer/cn/forum/topic/0203166979128830238>、<https://developer.huawei.com/consumer/cn/forum/topic/0204157989239546351>、<https://developer.huawei.com/consumer/cn/forum/topic/0203167510622143022>（WebView 加载 echart 滑动问题）；实现案例：<https://blog.csdn.net/qq_39652397/article/details/143374295>；ohpm 上的 echarts 封装包：<https://ohpm.openharmony.cn/> 搜索 `echarts` |
| 支持 HarmonyOS NEXT ArkTS | ✅ 技术可行（`Web` 组件 + `runJavaScript`/`javaScriptProxy`） |
| 能力覆盖度 | **全套都行**：heatmap series、visualMap colorbar、graphic 图片叠加、标注框，全都是 echarts 现成能力 |
| 集成成本 | 中。要写 HTML/JS 资源、准备 rawfile、搭 ArkTS↔JS 数据通道（`javaScriptProxy` 传 16×16 矩阵）、处理 Web 组件生命周期 |
| 风险与坑 | ① **性能/内存代价明显**：为一张 128×128 图启动整个 Web 渲染栈，首帧慢、内存占用高（量级远高于自绘 Canvas）；② **包体积**：echarts.min.js 单独约 1MB（未在本次检索中实测，建议自测），加 HTML/JS 资源；③ **交互与手势冲突**是已知坑（见上面论坛链接：webview 内 echart 无法左右滑动）；④ **截图/导出**链路复杂（Web 内容转 PixelMap）；⑤ 数据同步有跨语言边界开销；⑥ 首次渲染闪烁 |
| 结论 | **不推荐。** 你只要一张静态叠加图，用 WebView 属于用高射炮打蚊子；且手势、截图、内存三项代价都要长期背。 |

### 方案 4：ArkUI 原生 `Canvas` / `OffscreenCanvas` 自绘（**推荐**）

| 项 | 内容 |
|---|---|
| 名称 | ArkUI `Canvas` + `CanvasRenderingContext2D` + `OffscreenCanvas` / `OffscreenCanvasRenderingContext2D`，底层 ArkGraphics 2D |
| 来源链接 | 官方指南《使用画布绘制自定义图形 (Canvas)》：<https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-drawing-customization-on-canvas>；`CanvasRenderingContext2D` API：<https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-canvasrenderingcontext2d>；`OffscreenCanvasRenderingContext2D` API：<https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-offscreencanvasrenderingcontext2d>；ArkGraphics 2D 简介：<https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkgraphics2d-introduction> |
| 支持 HarmonyOS NEXT ArkTS | ✅ 官方内置能力，API 9 起可用，API 12~23 全覆盖 |
| 能力覆盖度 | **16×16 矩阵 → 色彩映射：✅**（两种做法都行，见下）；**叠加 128×128 图片：✅**（`drawImage` 直接把 `ImageBitmap`/`PixelMap` 画到底层）；**0.4 透明度：✅**（`globalAlpha`，或直接把 alpha 烘进色带 RGBA）；**虚线矩形框：✅**（`setLineDash` + `strokeRect`/`rect`）；**文字标注：✅**（`fillText` + `measureText` 算背景框）；**colorbar：✅**（`createLinearGradient` + `addColorStop` + `fillRect`，或用 ArkUI 通用属性 `linearGradient`） |
| 集成成本 | 低（自估 200~400 行 ArkTS，零依赖） |
| 已验证可复用的官方代码 | 华为开发者论坛官方答复给了一段完整 ArkTS 代码：`OffscreenCanvas` 画灰度/透明度场 → `getImageData` 取 `data[i+3]` 作为 alpha → `getColorMap(alpha/255)` 输出「蓝/绿/黄/红」→ `putImageData` 回写。链接：<https://developer.huawei.com/consumer/cn/forum/topic/0203208726669479239?fid=0109140870620153026> |
| 风险与坑 | ① 需要自己写色带映射函数（但 16×16 只有 256 个格子，可以用**分段色带 LUT**：预计算 256 项 `[r,g,b]` 查表，jet 色标是公开标准）；② 分辨率问题：16×16 放大到 128×128 会得到**块状（nearest-neighbor）外观**——这通常正是注意力热力图想要的；如果你要平滑，用 `createRadialGradient` 在每个格心叠加或做一次双线性插值再 `putImageData`；③ `drawImage` 与 `putImageData` 的混合模式：`putImageData` **不受 `globalAlpha` 影响**，若走像素路线要自己把 0.4 乘进 alpha，或用 `createImageData`+`putImageData` 到离屏再 `drawImage` 到主画布；④ Canvas 在 List/Scroll 里滚动时可关掉不可见绘制（`setOnVisibleAreaApproximateChange`，API 13+）；⑤ 高 DPI 下建议用 `LengthMetricsUnit.PX` 构造上下文以避免 vp/px 换算踩坑 |
| 结论 | **强烈推荐。** 这是唯一「零依赖 + 完全可控 + 官方长期支持 + 可精确对齐底图像素坐标」的方案。 |

### 方案 5：`@ohos/mpchart` 继续使用 + 自绘补热力图

| 项 | 内容 |
|---|---|
| 名称 | `@ohos/mpchart` 3.0.30（你现在用的） |
| 来源链接 | <https://gitee.com/openharmony-tpc/ohos_mpchart>；ohpm：<https://ohpm.openharmony.cn/>；华为官方介绍：<https://developer.huawei.com/consumer/cn/blog/topic/03221825816621099>；新仓库：<https://gitcode.com/CPF-ApplicationTPC/ohos_mpchart> |
| 支持 HarmonyOS NEXT ArkTS | ✅（3.0.x 已在 API 12 验证，README 写 "DevEco Studio: 5.0 (5.0.3.500), SDK: API12 (5.0.0.25)"） |
| 能力覆盖度 | **HeatmapChart：❌ 不存在（已核对导出表 + CHANGELOG）。** 其余能力可用：`LimitLine.enableDashedLine()`（虚线）、`setLineDash([5,5,0])`（源码里可见）、`MarkerView` 自定义气泡、`Fill(startColor, endColor)` 渐变填充（**可以用来做 colorbar 的近似**）、`LineDataSet.setGradientFillColor([...ChartColorStop])`（README 里有完整渐变示例） |
| 集成成本 | 已集成，0 |
| 风险与坑 | ① **MPAndroidChart 的 HeatmapChart 在鸿蒙移植版里被去掉了**（Android 版有，鸿蒙版没有；另外 Android 版的 HeatmapChart 也不支持底图叠加）；② 想「魔改」它加 HeatmapChart 需要动 renderer 层，成本高于直接自绘；③ 它的 Canvas 坐标系是「数据坐标 → 像素坐标」的图表坐标，不适合画与底图严格对齐的叠加层 |
| 结论 | **保持现状即可，但不要指望它出热力图。** 热力图 / 底图 / 叠加框 / colorbar 全部走方案 4 自绘；mpchart 只继续承担你已有的其他图表。 |

### 方案 6：其他被检索到但**不适合**的候选（列出以证明覆盖面）

| 名称 | 来源链接 | 为什么不适用 |
|---|---|---|
| `@ohmos/activity_overview` | <https://ohpm.openharmony.cn/>（关键词含 `heatmap`） | GitHub contribution graph 式日历热力图，**不是矩阵热力图**，不支持叠加图片 |
| 华为 Map Kit `Heatmap` | <https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/map-map-heatmap> | 地图热力图层，必须依附地图，**不能当通用矩阵热力图** |
| 高德地图 HarmonyOS NEXT SDK 绘制热力图 | <https://developer.amap.com/api/harmonyosnext-map3d-sdk/guide/draw-on-map/draw-heatmap> | 同上，地图专属 |
| `github.com/Explore-In-HMOS-Wearable/how-to-build-heat-map-explorer` | <https://github.com/Explore-In-HMOS-Wearable/how-to-build-heat-map-explorer> | 手表 Map Kit 热区示例，地图专属 |
| `@hxa-atpc/chillingvan-opengl-canvas` | <https://ohpm.openharmony.cn/>（关键词 `canvas`） | Android `openGL-canvas` 移植，做通用 Canvas/GL 绘制的低层封装，**不含热力图语义**，集成成本高于直接用官方 Canvas |
| `@ryan/canvas_utils` | <https://ohpm.openharmony.cn/>（关键词 `canvas`） | ArkTS Canvas 绘制工具类（路径/文本/撤销重做），**无热力图/色彩映射能力**，最多当便利封装 |
| `@hxa-atpc/leafchart` | <https://ohpm.openharmony.cn/> | Canvas 自绘轻量图表，只有折线/直方图 |
| `@mcui/mccharts` | <https://gitee.com/cyaofeng_admin/mc-charts>（亦见 <https://ohpm.openharmony.cn/>） | 鸿蒙 ArkTS 图表组件，能力为「折线图、柱状图、饼图、散点图、雷达图等等」，**未列热力图** |
| `@ibestservices/ucharts`（uCharts 鸿蒙版） | <https://ohpm.openharmony.cn/>；uCharts 本体：<https://gitee.com/stevin7998/uCharts>；官网 heatmap demo：<https://junbin-yang.github.io/uCharts-v3/examples/h5/heatmap-demo.html>；UCharts for Harmony 介绍：<https://developer.huawei.com/consumer/cn/blog/topic/03190404066132114> | ⚠️ **这是本次调研里最值得注意的一条「边界情况」**：uCharts 上游（H5/小程序版）**确实有 heatmap 图表类型**（第三行链接可直接打开 heatmap demo），但**鸿蒙版 `@ibestservices/ucharts` 的公开描述与 UCharts for Harmony 介绍中均未提及热力图**，是否把 heatmap 类型一起移植过来**未找到公开资料**。若你愿意验证，这是成本最低的一次试探：`ohpm install @ibestservices/ucharts` 后查其 API 是否有 heatmap 类型 |
| `kchart` / `@hxa-atpc/hellocharts` / `@hxa-atpc/paulroehr_eazegraph` / `@hxa-atpc/pfuster12_livechart` / `lite_chart` / `@wuyan/hm_chart` 之外的其他 chart 包 | <https://ohpm.openharmony.cn/> | 均为折线/柱/饼/K线类，**无 heatmap** |
| `@nutpi/mini_canvas` / `@baijiayun/painter` / `hmflowkit` / `fabric`(鸿蒙版) / `@ohos/vexflow` | <https://ohpm.openharmony.cn/> | 通用 Canvas 绘制/白板/流程图/音乐谱，**都不含热力图与色彩映射**；`fabric` 是对象模型封装，对「每帧重绘一张热力图」反而更重 |
| `@ohos/hamcrest`、`@liuzhanghao/rocker` 等 | <https://ohpm.openharmony.cn/> | 检索噪声（关键词误命中），无关 |

---

## 三、官方能力清点（做方案 4 时的 API 清单，均已核实存在）

来源：<https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-drawing-customization-on-canvas> 与
<https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-canvasrenderingcontext2d>

| 需求 | 官方 API | 备注 |
|---|---|---|
| 画底图（128×128 人脸） | `context.drawImage(ImageBitmap\|PixelMap, dx, dy, dw, dh)` | 指南「绘制图片和图像像素信息处理」小节明确列出 `drawImage`；`ImageBitmap` 可直接 `new ImageBitmap('/common/images/x.png')` |
| 像素级操作（色彩映射） | `getImageData(sx,sy,sw,sh)` / `createImageData` / `putImageData(data,dx,dy)` / `getPixelMap` | 同上小节明确列出 |
| 每格填色（16×16，最简做法） | `fillStyle` + `fillRect(x,y,w,h)` | 256 次调用，足够快；块状外观天然是「注意力格子」 |
| 平滑热力（可选） | `createRadialGradient(x0,y0,r0,x1,y1,r1)` + `addColorStop` | 论坛官方答复的热力图实现就是径向渐变 + 灰度场 + 颜色映射 |
| 半透明叠加（0.4） | `globalAlpha` 属性 | 指南明确列出「globalAlpha（设置透明度）」；**注意 `putImageData` 不受其影响** |
| 虚线矩形框 | `setLineDash([...])` + `strokeRect` / `beginPath`+`rect`+`stroke` | mpchart 源码中亦见 `c.setLineDash([5,5,0])` 用法 |
| 文字标注 | `fillText` / `strokeText` / `font` / `measureText` / `textBaseline` | 指南有「绘制文本边框」完整示例（用 `measureText` 算框尺寸） |
| colorbar（渐变色带） | `createLinearGradient` + `addColorStop` + `fillRect` | 指南「其他方法」小节有径向渐变示例；亦可用 ArkUI 通用属性 `linearGradient`（<https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-universal-attributes-gradient-color-V5>） |
| 离屏渲染 | `OffscreenCanvas(w,h)` + `offCanvas.getContext('2d', settings)` + `transferToImageBitmap()` + `context.transferFromImageBitmap(img)` | 指南示例完整演示了这一链路（含 `drawImage`→`getImageData`→`putImageData`→`transferFromImageBitmap`） |
| 不可见时不绘制 | `setOnVisibleAreaApproximateChange`（API 13+）/ `onVisibleAreaApproximateChange`（API 17+） | 指南列出两种方式 |
| 矩阵传入 | `Float32Array` / `ArrayBuffer` 作为参数传入自绘函数 | 无特殊限制 |

**jet 色带（蓝→青→绿→黄→红）落地方式**：预计算 256 项 LUT，或直接在 `createLinearGradient` 上按 jet 关键停靠点 `addColorStop`：
`0.0 #000080 → 0.125 #0000ff → 0.375 #00ffff → 0.625 #ffff00 → 0.875 #ff0000 → 1.0 #800000`（经典 jet；你可按需求只取蓝→红区间）。
叠加透明度通过 `globalAlpha = 0.4`，或把 0.4 预乘进每个 LUT 项的 alpha 通道。

---

## 四、社区可直接参考 / 拷贝的公开实现

| 内容 | 链接 | 可复用程度 |
|---|---|---|
| **华为开发者论坛官方答复：Canvas 绘制热力图（灰度场 → 颜色映射 → putImageData）** | <https://developer.huawei.com/consumer/cn/forum/topic/0203208726669479239?fid=0109140870620153026> | ⭐⭐⭐⭐⭐ 完整 ArkTS 代码，含 `OffscreenCanvas` + `getImageData` + `getColorMap` + `putImageData`，**这是本次调研中最贴近你需求的公开代码** |
| 官方指南：画布绘制自定义图形（含 drawImage / getImageData / putImageData / transferFromImageBitmap 完整示例） | <https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-drawing-customization-on-canvas> | ⭐⭐⭐⭐⭐ 官方示例代码可直接改写 |
| 官方：图片绘制（ArkTS） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/pixelmap-drawing-arkts> | ⭐⭐⭐⭐ PixelMap 绘制链路 |
| 官方：图片绘制（ArkTS）英文版 | <https://developer.huawei.com/consumer/en/doc/harmonyos-guides/pixelmap-drawing-arkts> | ⭐⭐⭐⭐ |
| 官方：ArkGraphics 2D 简介 | <https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkgraphics2d-introduction> | ⭐⭐⭐ 了解更底层的 drawing 能力（C API 可用） |
| 自研 HabitHeatmapView 习惯热力图：自定义绘制 + 离屏 Canvas 渲染调优 | <https://blog.csdn.net/sjw890821sjw/article/details/162100790> | ⭐⭐⭐ 工程化/性能调优经验（CSDN 正文有防盗链，需浏览器打开） |
| 高密度数据可视化渲染：基于 ArkUI Grid 的状态热力图组件 | <https://harmonyosdev.csdn.net/6a4f6e2d10ee7a33f28b82e1.html> | ⭐⭐ Grid 路线（非 Canvas），可对比选型 |
| 鸿蒙 Next 图像混合模式 blendMode 解析 | <https://ost.51cto.com/posts/56342> | ⭐⭐⭐ 若叠加效果要更细腻（如 multiply/screen）时的参考 |
| 鸿蒙 NEXT 实战：基于 ArkTS 的高性能图像处理应用开发 | <https://segmentfault.com/a/1190000046183156> | ⭐⭐ 像素处理性能实践 |
| 鸿蒙 Next 中多层 Canvas 融合 | <https://bbs.itying.com/topic/69172defe1e30e00420d8e94> | ⭐⭐ 多层 Canvas 叠加方案 |
| Qt for HarmonyOS 热力图组件开发实战 | <https://openharmonycrossplatform.csdn.net/6940f64f96fa167eeece886f.html> | ⭐ 仅思路参考（Qt 技术栈，不能直接用于 ArkTS） |
| 鸿蒙 NEXT 版开发图表（ECharts）实战案例【附源码】 | <https://blog.csdn.net/qq_39652397/article/details/143374295> | ⭐⭐ WebView+echarts 路线的完整案例 |
| OpenHarmony 三方组件资源汇总 | <https://gitee.com/openharmony-tpc/tpc_resource> | ⭐⭐ 已核对：**全表 688 行无任何热力图组件**，图表类仅收录 ohos-MPChart |
| awesome-harmony-library | <https://github.com/Madixin/awesome-harmony-library> | ⭐⭐ 已核对：Charts 章节仅收 `@ohos/mpchart`、`@mcui/mccharts`、`@visactor/harmony-vchart` 三个，**无 heatmap 库** |
| `Explore-In-HMOS-Wearable/how-to-use-vchart` | <https://github.com/Explore-In-HMOS-Wearable/how-to-use-vchart> | ⭐⭐⭐ 官方风格 `harmony-vchart` 接入示例（对方案 1 的 POC 有用） |

**明确「未找到公开资料」的项**：
- 未找到任何「HarmonyOS NEXT + ArkTS + 热力图叠加在人脸图片上 + 叠加矩形框/文字标注 + colorbar」的完整开源仓库或文章。
- 未找到 `@ibestservices/ucharts` 鸿蒙版是否包含 heatmap 类型的任何公开说明。
- 未找到 `@wuyan/hm_chart` 在 HarmonyOS NEXT / API 12+ 的编译验证记录。
- 未找到 `@visactor/harmony-vchart` 热力图叠加位图的官方示例或社区案例。
- 未找到 ohpm 或 GitHub 上任何「通用矩阵热力图」三方库。

---

## 五、如果三方库都不合适 —— 自绘方案落地说明

**结论：三方库确实都不合适，走自绘。** 具体路线（按推荐顺序）：

### 路线 A（最简、最稳）：`fillRect` 逐格 × jet LUT
1. 预计算 256 项 jet LUT：`lut[v] = [r,g,b]`（v = 0..255）。
2. 主 `CanvasRenderingContext2D`：
   - `drawImage(faceBitmap, 0, 0, W, H)` 画底图；
   - `globalAlpha = 0.4`；
   - 双层 `for`（16×16）内 `fillStyle = rgb(lut[round(m[i*16+j]*255)])` + `fillRect(...)`；
   - `globalAlpha = 1`；
   - `setLineDash([6,4])` + `strokeRect` 画框；
   - `fillText` 画标注。
3. colorbar 单独用一个 ArkUI 组件（`LinearGradient` 背景 + 刻度 `Text`），不必画在 Canvas 上——**更简单、更好做无障碍和响应式**。

优点：~100 行，零风险，块状外观天然适合注意力图。
缺点：格块间是硬边（通常正是想要的）。

### 路线 B（平滑热力）：离屏灰度场 → 像素颜色映射
严格照抄官方论坛答复的结构：
1. `OffscreenCanvas(128,128)` + `offContext`；
2. 对 16×16 每格用 `createRadialGradient` 叠加灰度/alpha 场（或直接把 16×16 双线性插值到 128×128 写进 `ImageData.data[i+3]`）；
3. `getImageData` → 逐像素 `getColorMap(alpha/255)` 写 RGB（**alpha 在此处乘 0.4**）；
4. `putImageData` 到离屏 → `transferToImageBitmap()` → 主 canvas `drawImage` 叠加在底图之上。

优点：连续平滑，像真正的注意力热力图。
注意：`putImageData` 忽略 `globalAlpha`，透明度必须烘进像素 alpha。

### 路线 C（若必须用第三方）：`@visactor/harmony-vchart` POC
- `ohpm install @visactor/harmony-vchart`；
- 关掉 axes / legend / padding / background，用 heatmap spec 铺一个精确尺寸的网格；
- 若能在网格下方插入图片元素、并叠加 annotation，则可用；否则回路线 A/B。

### 与现有 `@ohos/mpchart` 3.0.30 共存
- 两者互不冲突：mpchart 走它自己的 `Canvas` 组件，你的热力图走另一个 `Canvas`（或 `Stack` 叠加）。
- 想「一个 Canvas 全包」也可以：把热力图绘制写在一个 `Canvas` 里，mpchart 的图表另放一个区域。
- **不要尝试给 mpchart 打补丁加 HeatmapChart**：导入表里连 renderer 基类都是内部结构，改动面大且会破坏后续 ohpm 升级。

---

## 六、决策建议（一句话版）

> **不要在 ohpm/GitHub 上继续找热力图库了——它不存在。**
> 用 ArkUI 官方 `Canvas` + `OffscreenCanvas` 自绘（估 200~400 行 ArkTS，零依赖、零包体积、可精确对齐底图像素）；
> 如果想要现成图表能力且愿意试错，唯一值得做的 POC 是 `@visactor/harmony-vchart`（唯一确认带 heatmap 的原生 ArkTS 库），
> 以及成本更低的一次试探 `@ibestservices/ucharts`（上游有 heatmap，鸿蒙版是否移植未公开）。
> **`@ohos/mpchart` 3.0.30 确认无 HeatmapChart，保持现状即可，不要指望它。**
