# 工作台 Bug 清单（本轮 · 已全部修复）

> 面向后续接手本项目的 AI / 开发者。
> 逐条给出**现象 → 根因 → 修法 → 涉及文件 → 防复发规则**。
> 每条都是真机上出现的真实缺陷，不是推测。
>
> 相关计划与交付说明：`docs/工作台本轮实现计划.md`
> 修改范围：`harmony/`（鸿蒙端）。**未改 Web 端 `dashboard/` 与后端。**

---

## 概览

| # | 现象 | 根因分类 | 状态 |
|---|---|---|---|
| BUG-01 | 点击卡片后卡片高度忽然变长一倍，页面布局错乱 | ArkUI 布局测量 | ✅ 已修 |
| BUG-02 | 点「最近使用的素材」里**任意一条**，整块一起播动画 | 组件分层设计 | ✅ 已修 |
| BUG-03 | 点单条素材没进分析详情页，而是跳到了历史报告页（与「查看全部」行为相同） | 点击冒泡被外层吞掉 | ✅ 已修 |
| BUG-04 | 涟漪第二次点击"看不见"（动画在跑但圆是全透明的） | 动画状态未复位 | ✅ 已修 |
| BUG-05 | 查看历史素材时，页面会被「当前任务」的数据反复覆盖 | 实时/快照两种数据源未分离 | ✅ 已修 |
| BUG-06 | 全局背景改纯白后，登录页输入框看不见边界 | 主题变更的连带影响 | ✅ 已修 |

编译验证：`bash harmony/scripts/build.sh` → **BUILD SUCCESSFUL**。

---

## BUG-01 · 点击卡片后卡片高度翻倍 ⭐ 最严重

**现象**
点击工作台的任一卡片后，卡片高度忽然变成原来约两倍，同页其它元素被挤下去，整个页面布局错乱。

**根因（ArkUI 布局测量规则）**
`RippleCard` 的涟漪是一个 `Circle`，它的直径按"保证盖满整卡"算出来：

```
直径 = 2 × 触点 → 最远角的距离 ≈ 2 × 卡片对角线 ≈ 卡片宽度的 2 倍
```

而这个圆是 `Stack` 的**直接子节点**。ArkUI 中 `Stack` 的尺寸 = **所有子节点尺寸的并集**，
所以圆的 2 倍宽度被算进了卡片尺寸 → 卡片被撑成一个约 2 倍宽的盒子，高度随宽高比翻倍。

`Circle.position({x, y})` 只是"相对父容器的定位偏移"，**并不会把节点从布局中摘出去**
（它不是 CSS 的 `position: absolute` 那种脱离文档流的语义）。

**修法**（`ets/components/RippleCard.ets`）
1. 给涟漪加一层**定尺 + 裁剪的容器**：

```ts
Column() {
  if (this.rippleRadius > 0) {
    Circle()
      .width(this.rippleRadius * 2)
      .height(this.rippleRadius * 2)
      .position({ x: this.rippleX - this.rippleRadius, y: this.rippleY - this.rippleRadius })
      .fill(UiTheme.ripple)
      .scale({ x: this.rippleScale, y: this.rippleScale })
      .opacity(this.rippleOpacity)
  }
}
.width('100%')          // ★ 尺寸由卡片决定，不被圆撑开
.height('100%')
.clip(true)             // ★ 圆的溢出部分裁掉
.hitTestBehavior(HitTestMode.None)   // ★ 涟漪绝不能拦住卡内按钮的点击
```

2. 卡片外层从 `Stack` 改成 `Row`：
   `Row` 的尺寸由**非绝对定位**的子节点（内容层）决定，涟漪层完全不参与测量。

**防复发规则**
> 凡是"装饰用、会画到父容器之外"的元素（涟漪、水波纹、光晕、动画粒子），
> **必须**放进一个 `width('100%') height('100%') clip(true)` 的容器里，
> 并且外层容器优先用 `Row`/`Column` 而非 `Stack`。
> 直接把它们当 `Stack` 子节点，一定会把父容器撑大。

---

## BUG-02 · 点单条素材，整块一起播动画

**现象**
期望"点哪一条，哪一条卡片播涟漪"；实际是**整个「最近使用的素材」区块**一起播动画。

**根因**
`RecentMediaSection` 的整块内容被包在**同一个 `RippleCard`** 里，
每条素材只是它内部的一行 —— 涟漪只有一个实例，自然表现为"整块一起动"。
这是组件分层的设计错误：**区块外壳与列表项被合并成了同一个交互单元**。

**修法**（`ets/components/workbench/RecentMediaSection.ets`）
- 区块外壳**不再是可点卡片**：标题行是普通 `Row`，列表项各自独立；
- 每一条素材各是一张**独立的 `RippleCard`**（`ForEach` 内渲染），
  涟漪因此天然只在被点的那一行内扩散；
- 空态卡片显式关闭点击与动画：`RippleCard({ _enabled: false, _clickable: false })`。

同时给 `RippleCard` 新增参数，把"要不要触发动作"和"要不要播动画"解耦：

| 参数 | 含义 |
|---|---|
| `_enabled` | 是否触发 `onTap` 动作 |
| `_clickable` | 是否播放涟漪动画 |

**防复发规则**
> "列表"与"列表项"必须是**两层独立的交互单元**。
> 容器只负责布局，交互与动画一律下沉到每一项。
> 需要"整块不可点"时，用 `_clickable: false` / `_enabled: false` 显式关掉，
> 而不是把列表项塞进一张大卡片里。

---

## BUG-03 · 点单条素材却跳到了历史报告页（与「查看全部」相同）⭐ 逻辑 bug

**现象**
点「最近使用的素材」里的某一条，跳转到了**历史报告页签**，和点「查看全部」的表现一模一样；
期望是进入该素材的分析详情页。

**根因**
两个问题叠加：
1. **点击冒泡**：BUG-02 里那层"包裹整块的可点卡片"存在时，
   点列表项会先冒泡到外层卡片，触发外层的 `onTap`；
2. **外层回调接错了动作**：窗口层把外层 `onTap` 映射成了 `onViewAll`（切历史报告页签），
   而列表项自己的 `onSelect` 反而没机会执行。

也就是说：`onSelectRecent` 的实现当时写的是 `this.pushTab(MainTab.reports)` —— 与"查看全部"完全重复。

**修法**
1. （随 BUG-02）外层不再是可点卡片，冒泡路径消失，每一条的 `onTap` 才会真正生效；
2. `MainPage.openRecentDetail(mediaId)` 新增：按该素材的**报告快照**打开分析详情页；
3. `WorkbenchPageParam.onSelectRecent` 接到 `openRecentDetail`，
   **不再**切到历史报告页签。

**防复发规则**
> 嵌套可点区域时，先问清楚"这一层点击到底绑定了什么动作"。
> 同一个回调被映射到两个语义不同的动作（`onSelectRecent` 与 `onViewAll` 都变成切页签），
> 是很容易漏掉的一类复制粘贴缺陷 —— 写回调映射时逐条对照控件语义。

---

## BUG-04 · 涟漪第二次点击"看不见"

**现象**
同一张卡片点第二次时，动画似乎在跑（点击有响应），但看不到任何视觉反馈。

**根因**
第一次动画把 `opacity` 从 `1` 动画到了 `0`（`UiTheme.rippleEndOpacity`）。
第二次点击时只把 `scale` 复位成 `0`，**没有把 `opacity` 复位回 `1`**，
于是新圆从"完全透明"开始扩散 —— 全程不可见。
（早期版本用 `ripplePlayed` 标志给"首次点击"跳过复位，反而让首次点击正常、后续点击异常。）

**修法**（`ets/components/RippleCard.ets`）
每次点击都先做一次 `duration: 0` 的瞬时复位，把 `scale` 和 `opacity` 一起归位：

```ts
this.getUIContext().animateTo({ duration: 0 }, () => {
  this.rippleScale = 0;
  this.rippleOpacity = 1;     // ★ 关键：透明度也要复位
});
this.getUIContext().animateTo({ duration: UiTheme.rippleDuration, curve: Curve.EaseOut }, () => {
  this.rippleScale = 1;
  this.rippleOpacity = UiTheme.rippleEndOpacity;
});
```

**防复发规则**
> 重放一段动画前，必须把**动画涉及的全部属性**（scale / opacity / rotate / translate…）
> 一起复位。只复位其中一个，就会出现"动画在跑但看不见"这类最难查的缺陷。

---

## BUG-05 · 查看历史素材时数据被「当前任务」覆盖

**现象**
（与 BUG-03 同源）从「最近使用的素材」进入详情页后，页面内容会被当前正在跑的任务反复改写。

**根因**
`AnalysisDetailPage` 是二级页面，它的参数由 `MainPage.syncDetailParam()` 每次都投影"当前任务"。
但"最近使用的素材"点进来的素材**不一定**是当前任务 —— 它可能是几天前分析过的另一段素材。
单一数据源 + 无条件覆盖 = 用户在看好 A，页面被改写成 B。

**修法**
1. `AnalysisDetailPageParam` 新增 `followLiveTask: boolean`：
   - `true`（默认）→ 从「当前任务」进入：进度/分数随 WS 实时刷新；
   - `false` → 从「最近使用的素材」进入：参数是**冻结快照**。
2. `MainPage.syncDetailParam()` 首行判断 `if (!param.followLiveTask) return;`，
   不再覆盖快照。
3. `AnalysisDetailPage` 在快照模式下：
   - 顶部说明改为"这是该素材最近一次分析的报告快照"；
   - **不显示**「取消分析」按钮（没有可取消的会话）。

**防复发规则**
> 一个页面若可能由**多个数据源**进入（实时会话 / 历史记录 / 深链），
> 参数里必须有字段显式声明"当前是哪一种"，并让每次自动同步先判断它。
> 否则"自动刷新"就会变成"自动覆盖用户正在看的内容"。

---

## BUG-06 · 全局背景改纯白后输入框看不见边界

**现象**
按需求把 `UiTheme.pageBackground` 改成纯白 `#FFFFFF` 后，登录页的输入框与卡片同色，
只剩 placeholder 文字，看不出输入框的范围。

**根因**
输入框原本靠"浅灰页面背景 + 纯白卡片"的色差来界定边界。
背景变纯白后这个色差消失 —— 属于**主题变更的连带影响**，不是单独一个组件的 bug。

**修法**
登录页两个 `TextInput` 补一条浅灰描边：
`.borderWidth(1).borderColor(UiTheme.divider)`，背景显式设为 `cardBackground`。

**防复发规则**
> 改全局设计令牌（背景色、圆角、字号）后，要专门走查"靠色差表达边界"的元素：
> 输入框、分隔线、缩略图底、进度条轨道。
> 本工程已在 `UiTheme.ets` 顶部写明一条纪律：
> **纯白背景下，卡片内嵌元素一律用 `fillSoft` / `divider` 描边或填底，不能只靠背景色差。**

---

## 附：本轮同时修掉的编译期问题（非运行时 bug，但容易被误判成 bug）

| 报错 | 原因 | 修法 |
|---|---|---|
| `Property 'enabled' in type 'RippleCard' is not assignable to ... CustomComponent` | `enabled` 是 ArkUI **系统属性方法名** | 改名 `_enabled`（同理 `_clickable` / `_padding` / `_radius`） |
| `Could not resolve "../common/UiTheme"` | `components/common/` 比 `components/` 深一层 | 改 `../../common/UiTheme` |
| `Module '"../types/Index"' has no exported member 'UploadFileSpec'` | 它定义在 `network/HttpClient.ets` | 改 import 来源 |
| `Duplicate identifier 'lastUploaded'` | 字段声明写了两次 | 删掉重复那份 |
| `es2abc ... spawn EPERM` / `spawn java ENOENT` | 构建环境问题，**不是代码问题** | 见 `harmony/scripts/build.sh` 顶部注释 |

---

## 给下一位接手者的三条硬规则

1. **装饰性溢出元素必须包定尺裁剪壳**（`width('100%') height('100%') clip(true)`），
   外层别用 `Stack`。（BUG-01）
2. **列表与列表项分两层交互单元**，动画与点击一律下沉到每一项。（BUG-02 / BUG-03）
3. **重放动画要把所有动画属性一起复位**；
   **多数据源页面要有 `followLiveTask` 这类显式开关**。（BUG-04 / BUG-05）

---

## 尚未验证（需要真机确认）

编译与打包已通过（`BUILD SUCCESSFUL`），但以下运行时行为需要真机复核：

1. 点击各卡片：高度不再变化，涟漪从**手指按下的位置**扩散；
2. 连续点同一张卡片两次：两次都能看到涟漪；
3. 点「最近使用的素材」单条：进入**该素材**的分析详情页（不是历史报告页）；
4. 点「查看全部」：仍然切到历史报告页签；
5. 从详情页返回工作台，「当前任务」是否仍在推进（后台分析未中断）；
6. 历史快照模式下不出现「取消分析」按钮。
