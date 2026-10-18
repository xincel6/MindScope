> **归档说明**：本文是 2026-10-17 的原始交付说明，正文保留原貌，不再随代码更新。当前进度见 [鸿蒙端开发进度](../../鸿蒙端开发进度.md)，统一时间线见 [交付记录](../../交付记录.md)。

# 本轮交付说明 · UI 统一（增强对比度风格）＋ 统计三卡错峰修复

## 1. 本轮用户诉求

1. 统计页图表那套「增强对比度」风格**铺到所有界面**，形成统一 UI 风格。
2. **修复上一轮缺陷**：统计页三栏小卡（平均推理耗时 / 素材总数 / 重度占比）没有做错峰处理 → 没有入场动画。
3. **顶部区域能否变成下面区域的背景色？**

三条全部达成，第 3 条在第 1 条的做法里自然解决（见 §3）。

## 2. 决策记录

| 决策点 | 结论 |
|---|---|
| 统一力度 | **整套铺开**：浅灰底 + 白卡 + 16 圆角 + 极淡投影 + 深灰文字 |
| 渐变取舍 | **保留统计页核心卡渐变**，其余页面照此风格拉齐但不新增渐变 |
| 第 3 条诉求的实质 | 顶部白带 = 页面根背景 `pageBackground(#FFFFFF)` 透上来，与内容区 `#F2F3F7` 形成分界（基线截图 `ui-before1.jpeg`，分界 y≈90px）。改全局令牌即可消除，无需碰窗口/系统栏 API |
| 底部页签图标 | 单字（析/库/报/统/我）当图标在真机上读起来像乱码 → 改为**标签文字 + 选中态薄荷胶囊底**（额外修复项） |

## 3. 设计令牌变更

| 令牌 | 旧值 | 新值 |
|---|---|---|
| `pageBackground` | `#FFFFFF` | `#F2F3F7` |
| `textPrimary` | `#1E3A5F` | `#1D2129` |
| `textSecondary` | `#64748B` | `#4E5969` |
| `divider` | `#E2E8F0` | `#E5E6EB` |
| `fillSoft` | `#EDF2F7` | `#E9EDF3` |
| `cardRadius` | `8` | `16` |
| `buttonRadius` | `8` | `12` |
| `cardShadowEnabled` | `false` | `true` |
| `cardShadowRadius` / `OffsetY` | `10` / `2` | `14` / `3` |
| `cardShadowColor` | `#1E3A5F` | `#141D2129`（8 位 ARGB ≈ 8% alpha） |
| `cardShadowOpacity` | `0.12` | **删除** |
| `progressTrack` | `#EDF2F7` | `#E9EDF3`（与 fillSoft 同值） |
| `skeletonFill` | — | **新增** `#DCE3EC` |
| `start_window_background` / `page_background` | `#FFFFFF` | `#F2F3F7` |

### 顺带修掉的真 bug：投影的 `opacity` 字段一直是无效的

`CardStyle.shadow()` 原先把 `opacity` 塞进 `.shadow({...})`，但 ArkUI 的 `ShadowOptions` **没有 opacity 字段**，该值一直被运行时忽略 —— "极淡投影"从未真正变淡，开关一开就是满强度黑影。现改为把 alpha 写进色值（`#141D2129`）并从 `CardShadowOptions` 删除无效字段。

历史上"8 位 shadow 色会让卡片整片不渲染"的结论**本轮被真机证伪**：`#141D2129` 装机后卡片正常渲染（`ui-w1a.jpeg`）。当年白屏的真因是共享 `AttributeModifier` 实例。

## 4. 错峰动画缺陷：根因与修法

**根因**：三张小卡在 `Row` 里靠 `.layoutWeight(1)` 均分宽度，而 `RevealCard` 外层 `Column` 不带布局权重 —— **一包就破均分**，上一轮只能裸放，于是这一排没有入场动画。

**修法**：
- `RevealCard` 新增 `@Param _weight`，外层 Column 挂 `.layoutWeight(this._weight)`（默认 0 = 行为不变）；
- 三张卡各包 `RevealCard({ order: 2|3|4, _weight: 1 })`，权重由外层承担，卡内 `.layoutWeight(1)` 换成 `.width('100%')` 填满槽位；
- 全页 order 重排为 0..6（页头/核心卡/三小卡/环形图/折线卡），`CardTransit.CARDS_STATS` 3 → **7**；
- 动画参数（`cardMs 240` / `stepMs 110`）一行未动。

**真机证据**：`_materials/_verify/burst4.jpeg` 截在入场中段 —— 页头已就位、核心卡与第 1 张小卡已淡入、第 2 张更淡偏移更大、第 3 张尚未出现且槽位已预留（无布局跳动）。三个槽位始终等宽。

## 5. 各页改造要点

| 页面/组件 | 改动 |
|---|---|
| `common/UiTheme.ets` | 上表全部令牌；统计页专用令牌保留但已不被消费 |
| `common/CardStyle.ets` | 投影真正生效；`CardShadowOptions` 删无效 `opacity` |
| `components/RevealCard.ets` | 新增 `_weight`，动画逻辑未动 |
| `components/AppCard/RippleCard` | 仅过期注释 |
| `components/SkeletonView / PlaceholderView` | 骨架块与空态图标底改 `skeletonFill`（灰底上可见） |
| `pages/StatsPage.ets` | 三卡错峰；order 0..6；私有视觉令牌全部收敛到全局；核心卡渐变保留 |
| `pages/MainPage.ets` | 页签栏去图标改文字+胶囊；槽位点击区仍为整槽 |
| `pages/LoginPage / RegisterPage` | 输入框底 `pageBackground`→`fillSoft` 并去掉双重描边 |
| `pages/MediaLibrary / Reports` | 空态由裸浮改为白卡承托（否则 `fillSoft` 图标底会消失在灰页底上） |
| `pages/ProfilePage` | 退出登录文字色 `textPrimary`→`danger` |
| `pages/MediaPicker / AnalysisDetail` | 进度条显式传 `trackColor`；逐帧缩略格底改 `fillSoft` |
| `components/charts/**` | **零改动**（11 个组件 mtime 可查；残余硬编码全属数据表达色，按纪律不动） |

## 6. 验收

| 检查项 | 结果 | 证据 |
|---|---|---|
| ArkTS 构建 | ✅ BUILD SUCCESSFUL（两波各一次） | `harmony/_build.log` |
| 卡片是否因 8 位投影色消失 | ✅ 正常 | `ui-w1a.jpeg` |
| 顶部白带是否消除 | ✅ 状态栏与页底同色 | `ui-w1-stats.jpeg` / `v2-workbench.jpeg` |
| `layoutWeight` 是否破布局 | ✅ 三卡等宽、动画中不重排 | `v2-stats-settled.jpeg` / `burst4.jpeg` |
| 错峰动画是否真的生效 | ✅ 截到逐张递进的中间态 | `burst4.jpeg` |
| 五页一致性 | ✅ 灰底/白卡/16 圆角/投影/页签胶囊 | `v2-workbench / v2-media / v2-reports / v2-stats / v2-profile .jpeg` |
| 旧色与私有令牌残留 | ✅ 代码引用 0 处（仅 UiTheme 里 4 个已无人消费的定义，见 §7） | grep |
| 饼图是否回归 | ✅ 完整圆环（初次截图疑似缺角，实为 `animateY(800ms)` 扇区动画截帧，静置后复验通过） | `v2-stats-settled.jpeg` |

**未做目视验收的部分**：登录/注册页。本轮改动只涉及输入框填充与注释，且目视验收需要登出（会清掉本机登录态与业务缓存），故仅做代码复审 + 编译验证。如需确认，请手动登出查看，或下一轮我单独用临时账号走一遍。

## 7. 已知项 / 遗留

1. `UiTheme` 里 `statsPageBg / statsCardRadius / statsTextPrimary / statsTextRegular / statsShadow*` 等 16 个统计页专用常量**已无人消费**，目前保留未删（删除属独立小清理，避免在本轮动锁定文件）。
2. `MainSkeleton` 是死组件（无引用）。
3. `RegisterPage` 的 Logo 传 `_size: 72`，与登录页主题默认（96/20）不同，而注释写着"与登录页一致"—— 属版式细节，本轮纪律不允许顺手改版式，故留待下轮定夺。
4. 页签胶囊左右内边距取 `gapS(8)` 而非任务书初定的 16：5 等分槽放不下"历史报告"（4 字 ≈56vp + 32 内边距 > 槽宽 81vp），照搬会被回夹截断。真机截图已验证不截断。
5. `CurrentTaskCard` 首帧缩略图有 1px 描边、`RecentMediaSection` 没有 —— 历史遗留的风格不一致。

## 8. 操作踩坑记录（供后续轮次）

- 设备侧截图写文件用 `/data/local/tmp/x.jpeg`，回传必须用 **`//data/local/tmp/x.jpeg`**（双斜杠）；否则 hdc 把源路径当 Windows 相对路径解析到 `E:/Git/...`。
- 重装 HAP 后屏幕会自动休眠，`aa start` 会报"检查开发者模式"（实为锁屏），需 `power-shell wakeup` + `uitest uiInput swipe` 解锁。
- `pwsh` 工具的文件沙箱**不允许子进程（hdc）写盘、也不允许 New-Item 建目录**；已存在目录内用 Git Bash 通道回传可用。
- 图表入场动画（`animateY(800ms)`）会干扰截图判读：切页签后至少等 3~4s 再抓，否则会误判成"图表画坏了"。
