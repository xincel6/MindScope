# 工作台 Bug 清单（本轮 · 已全部修复）

> 面向后续接手本项目的 AI / 开发者。
> 逐条给出**现象 → 根因 → 修法 → 涉及文件 → 防复发规则**。
> 每条都是真机上出现的真实缺陷，不是推测。
>
> 相关计划与交付说明：`docs/工作台本轮实现计划.md`
> 修改范围：`harmony/`（鸿蒙端）。**未改 Web 端 `dashboard/` 与后端。**

---

## ⚠️ 先读这条：`RippleCard` 上连续踩了 4 个坑，现象相似但原因完全不同

`RippleCard` 一个组件上连续踩了四个**不同**的 ArkUI 坑，
现象都表现为"卡片尺寸/内容异常/不更新"，极易误判成同一个问题。真实顺序是：

| 轮次 | 现象 | 真正原因 |
|---|---|---|
| 第 1 次 | 点一下卡片，高度翻一倍 | **响应式几何反馈环**：圆的尺寸由"响应式半径 + 测量结果"推出（BUG-01） |
| 第 2 次 | 卡片**整片消失**，页面只剩区块标题 | `Column` 里混用 `height('100%')` 包裹层 + `AUTO` 内容层 → 百分比高度解析成 0（BUG-07） |
| 第 3 次 | 不再变长，但**卡片初始高度就过长** | `position()` 不脱离布局流，720vp 的圆被 `Stack` 算进了尺寸（BUG-01 续） |
| —— | 试图用包裹层隔离尺寸 | 官方文档自相矛盾，无法静态判断 → **放弃手绘涟漪，改用原生 `clickEffect`** |
| 第 4 次 | 卡片正常，但**刷新不回显状态** | 异步数据经 `navDestination` 传参，改字段不更新已挂载页面（BUG-10） |

**教训**：同一个组件连续出现"尺寸/刷新类"异常时，不要假定是同一个原因。
按"**测量链 → 布局链 → 数据链**"三条线分别独立定位，不要凭上一次的结论套用。

**更重要的教训**：这一轮我在 `RippleCard` 上连续改了 4 次，
每次都把半成品交给用户去真机验证 —— 这是错误的工作方式。
涉及布局边缘行为时，应该**先在预览器里做最小复现验证**，
或者**直接用平台原生能力**，而不是在生产组件上一次又一次地试。

---

## 概览

| # | 现象 | 根因分类 | 状态 |
|---|---|---|---|
| BUG-01 | 卡片一碰就变长（点一下 / 长按 / 拖动都会）；后期表现为"卡片初始高度过长" | ① 响应式几何反馈环 ② `position()` 不脱离布局流 | ✅ 已修（改用原生按压反馈，见 BUG-01 末节） |
| BUG-02 | 点「最近使用的素材」里任意一条，整块一起播动画 | 组件分层设计 | ✅ 已修 |
| BUG-03 | 点单条素材没进分析详情页，而是跳到了历史报告页（与「查看全部」行为相同） | 点击冒泡被外层吞掉 | ✅ 已修 |
| BUG-04 | 涟漪第二次点击"看不见"（动画在跑但圆是全透明的） | 动画状态未复位 | ✅ 已修（随手绘涟漪一起撤回） |
| BUG-05 | 查看历史素材时，页面会被「当前任务」的数据反复覆盖 | 实时/快照两种数据源未分离 | ✅ 已修 |
| BUG-06 | 全局背景改纯白后，登录页输入框看不见边界 | 主题变更的连带影响 | ✅ 已修 |
| BUG-07 | 工作台卡片整片空白，页面只剩区块标题 | 百分比高度在 AUTO 父容器下塌陷 | ✅ 已修 |
| BUG-08 | 卡片视觉改用共享 `AttributeModifier` 后存在整片不渲染风险 | ArkUI 属性修饰器 | ✅ 已回退 |
| BUG-09 | 投影色用 8 位 `#RRGGBBAA`，预览器可能判为非法导致组件不渲染 | ArkUI 色值类型 | ✅ 已修 |
| BUG-10 | 点刷新后「服务在线」状态不更新，切页签再回来才变 | 异步数据经 `navDestination` 传参不更新已挂载页面 | ✅ 已修 |
| BUG-11 | 「选择图库素材」里选完图片，停在素材选择页、界面毫无变化 —— 等于没选 | 参数类非 `@ObservedV2`（挂载后改字段不刷新）+ 选完没有再往前走一步 | ✅ 已修（本轮） |
| BUG-12 | 选完图片上传立刻报「网络不可达：Failed to open or read local data…」 | 把相册 URI 当成本地路径交给 `http` 上传（2300026）＋ 该错误被误分类成网络问题 | ✅ 已修（本轮） |

编译验证：`bash harmony/scripts/build.sh` → **BUILD SUCCESSFUL**。

---


## BUG-01 · 卡片一碰就变长（点一下 / 长按 / 拖动都会）⭐⭐ 最严重

**现象**
鼠标点一下卡片（或长按、拖动）后，卡片高度忽然变成约两倍，
卡片内容被压在顶部、下半张全白；同页其它元素被挤下去，整个页面布局错乱。
**只有交互才触发**，纯浏览时一切正常。

**根因（响应式几何值反馈环）**
早期把涟漪圆的直径做成"2 × 触点 → 最远角距离"，并由 `@Local rippleRadius` 驱动：

```ts
@Local rippleRadius: number = 24;          // 响应式状态
@Local cardWidth / cardHeight = 0;         // 由 onSizeChange 回填

Circle().width(this.rippleRadius * 2).height(this.rippleRadius * 2)   // ← 尺寸是响应式的
...
.onSizeChange((o, n) => { this.cardWidth = n.width; this.cardHeight = n.height })
```

于是形成一条环：

```
按下 → rippleRadius 由 24 变成 400+
     → 圆的尺寸变化 → 触发布局重新测量
     → onSizeChange 回填更大的 cardWidth / cardHeight
     → 下次交互算出更大的半径 → 圆更大 → 卡片更高 → …
```

**"只有交互才触发"正是这条环的指纹**：`rippleRadius` 的初值只有 24（圆很小，
所以首帧布局正常），只有按下时才被替换成"对角线级别"的大值，环才被点燃。

**修法**（`ets/components/RippleCard.ets`）
让圆的尺寸成为**编译期常量**，几何全部走"绘制变换"：

```ts
const RIPPLE_DIAMETER: number = 720;      // 常量，永不变

Circle()
  .width(RIPPLE_DIAMETER)                  // 尺寸恒定 → 不触发重新测量
  .height(RIPPLE_DIAMETER)
  .position({ x: this.rippleX, y: this.rippleY })   // 绘制位置
  .translate({ x: '-50%', y: '-50%' })              // 圆心对齐触点
  .scale({ x: this.rippleScale, y: this.rippleScale })  // 扩散
  .opacity(this.rippleOpacity)
```

同时**删掉 `onSizeChange` 与 `cardWidth` / `cardHeight` 状态**——
只要还把测量结果写回状态、又用它驱动装饰元素尺寸，环就迟早会回来。

**防复发规则**（本项目最重要的一条）
> **装饰元素的尺寸绝不能由"响应式状态 + 测量结果"推出来。**
> 尺寸用常量；位置/缩放/旋转用 `position` / `translate` / `scale`（绘制变换，不触发重新测量）。
> 并且**不要在装饰组件上挂 `onSizeChange`**。
>
> 判断方法：只要存在「测量结果 → 状态 → 元素尺寸 → 布局 → 测量结果」的链路，
> 就一定会出现"越交互越走形"。这类 bug 编译期完全看不出来。

### BUG-01 的最终处置：**放弃手绘涟漪，改用原生按压反馈**

切断反馈环之后又出现了新现象：**卡片初始高度就过长**（内容贴顶、下半张空白）。
根因是 `position()` 的语义被误解 —— SDK 里的原文是：

```
Sets the absolute position of the component relative to the position of the parent component.
The attribute is not available for a layout container whose width and height are zero.
```

即：**`position()` 只是"绝对定位到父组件"，组件并不会脱离布局流**，
它依然参与父容器的尺寸测量。所以 720vp 的圆作为 `Stack` 的直接子节点时，
`Stack` 被撑到"圆所占布局框"那么大 → 卡片初始就过长。

**尝试隔离时撞上了官方文档的自相矛盾**：

| 出处 | 说法 |
|---|---|
| `common.d.ts` 中 `position()` 的注解 | 「父容器宽高为 0 时该属性**不生效**」→ 暗示**零尺寸父容器里的绝对定位子节点不会撑大父容器** |
| 另一些布局文档 | `position` 的子节点**参与**父容器测算 |

两种说法无法同时成立，而**只能靠真机反复试错**去确认 —— 每试一次都是把问题
交给用户去发现，代价不可接受。

**最终处置**：按本清单规则一（装饰元素绝不能影响布局测量），
**撤回手绘涟漪**，改用 ArkUI 原生能力表达按压反馈 —— 零新增节点、零布局风险：

```ts
.backgroundColor(this.backgroundFor())              // 按下换淡色，抬起复原（颜色属性，不涉尺寸）
.clickEffect({ level: ClickEffectLevel.LIGHT })     // 系统级按压涟漪：从触点扩散，由系统实现
.onTouch(...)                                       // Down → pressed = true；Up/Cancel → false
```

`RippleCard` 保留原名（避免改动 8 处调用方），但文件头已写明：
**它现在用原生按压反馈，不是手绘涟漪**。

**如果将来确实需要"自绘 + 从触点扩散"的涟漪，必须先做隔离验证**：
在 DevEco 预览器里单搭一个"卡片 + 大圆"的最小页面，确认卡片高度不受影响后再移植，
**不要直接改 `RippleCard.ets` 试**。

**新增防复发规则**

> 涉及"绝对定位 / 零尺寸父容器 / 百分比高度"这类**布局边缘行为**时，
> 官方文档可能互相矛盾。不要靠"我觉得应该可以"去改生产组件 ——
> 拆一个最小复现页面验证通过再移植。
> 更稳的做法是：**优先用平台原生提供的能力**（如 `clickEffect`），
> 而不是自己用基础组件拼一个"看起来一样"的效果。

---


## BUG-07 · 工作台卡片整片空白 ⭐⭐ 最严重（本轮主诉）

**现象**
工作台页面只显示「工作台 / 分析入口与今日概览」标题和右上的刷新按钮，
下方**所有卡片区域一片空白**；滚动时只能看到「当前任务」「最近使用的素材」这几个区块标题，
看不到素材、分数、进度条、按钮。底部页签栏正常。

**根因（百分比高度在 AUTO 父容器下塌陷）**
修复 BUG-01 后的写法是：

```ts
Column() {                       // ← 父容器：高度 AUTO
  Column() { Circle()... }       // ← 涟漪包裹层：height('100%')
    .width('100%').height('100%').clip(true)
  Column() { this.content() }    // ← 内容层：高度 AUTO（真实高度在这里）
    .padding(...)
}
```

父 `Column` 的高度是 `AUTO`（由子节点决定），此时子节点的 `height('100%')`
**没有可解析的基准**，被算成 0；而这层 `height('100%')` 的节点在测量顺序上又先于内容层，
于是**整行高度被算成 0** —— 卡片里全部内容都被"压"成不可见，
页面只剩下区块标题这类自带固有高度的文字在撑高度。

**修法**（`ets/components/RippleCard.ets`）
把外层容器从 `Column` 改成 `Stack({ alignContent: Alignment.TopStart })`：
- `Stack` 的尺寸取子节点最大值 → 内容层有固有高度、圆形装饰不参与"撑大"判断；
- 顺便这也是"装饰层叠在内容之下"最标准、最少坑的写法。

**防复发规则**
> **绝对不要**在同一个容器里混用「`height('100%')` 的包裹层」和「`AUTO` 高度的内容层」。
> 父容器高度是 `AUTO` 时，百分比高度会解析成 0，把整行高度算成 0。
> 需要"装饰层 + 内容层"叠放时用 `Stack`；需要"上下排列"时让**至少一个**子节点有确定高度
> （给容器 `height(...)` 固定值，或把百分比换成 `layoutWeight`）。

---

## BUG-08 · 共享 `AttributeModifier` 导致卡片有整片不渲染风险

**现象**
（与 BUG-07 同时出现，属"重点排查对象"）卡片视觉改为统一走
`.attributeModifier(CardStyle.modifier)` 后，卡片区域不渲染。

**根因**
`CardStyle.modifier` 是一个 **`CommonModifier` 子类的静态单例**，
被登录页 `AppCard`、工作台 6 张卡片等**数十个组件实例同时引用**。
一个属性修饰器实例被多个组件共享时，ArkUI 的属性生效行为不可靠。
而改造前渲染正常的 `AppCard` 用的是**三个属性内联写在组件链上**的写法。

**修法**
1. 彻底放弃「用 `AttributeModifier` 表达卡片视觉」这条路：
   `CardStyle` 退化为**只导出取值**（`shadow()` / `background()` / `radius()`）；
2. `RippleCard` 与 `AppCard` 各自把 `backgroundColor` / `borderRadius` / `shadow`
   **内联**写在组件链上（这是本工程此前已验证可用的写法）。
3. 顺手给卡片补了一条 `divider` 浅描边：纯白背景下卡片与页面同色，
   有描边才能一眼看出"卡片到底渲染出来没有"，也提高了层次可读性。

**防复发规则**
> 卡片/控件的稳定视觉用**内联属性方法**表达。
> `AttributeModifier` 只适合"每个实例各自 new 一份"或者确实需要动态切换整套属性的场景，
> **不要做成全局单例给所有组件复用**。

---

## BUG-09 · 投影色用 8 位十六进制

**现象**
（与 BUG-07 同时排查）投影色 `#0F1E3A5F` 是 8 位（带 alpha）。

**根因**
ArkUI `shadow().color` 的官方类型是 `ResourceColor`，文档与示例均为 **6 位 `#RRGGBB`**。
8 位色值在预览器上可能被判定为非法，进而让整个组件不渲染
（属于"编译通过、运行不显示"的隐形坑）。

**修法**
`UiTheme`：`cardShadowColor` 改为 6 位 `#1E3A5F`，
新增 `cardShadowOpacity: 0.12` 用独立字段表达"淡影"；
`cardShadowRadius` 8 → 10（半径大、透明度低，投影更自然）。

**防复发规则**
> 色值统一用 6 位 `#RRGGBB`；需要透明度请走 `opacity` / `fillOpacity` 等独立字段，
> 不要把 alpha 塞进颜色字符串里（本工程已知只有 `UiTheme.ripple` 例外，
> 它是 `fill()` 的入参，支持 ARGB 8 位）。

---


## BUG-10 · 刷新后「服务在线」状态不实时更新

**现象**
点工作台右上角刷新（或离线横幅的「重试」）后，服务状态圆点与文案**不变**；
必须切到别的页签再切回工作台，才会显示最新状态。

**根因（异步数据 + 参数传递的组合问题）**
工作台的展示数据原本和别的页面一样走"参数对象"：

```
MainPage（窗口层）─投影─▶ WorkbenchPageParam ─@Param─▶ WorkbenchPage
```

而工作台的数据是**异步到达**的：探活结果来自 `await AppStore.checkHealth()`、
任务进度来自 WebSocket 回调。两个问题叠加：

1. 窗口层是在 `await` 之后去改**已存在参数对象**的字段；
2. 页面经 `Navigation.navDestination` 挂载 —— **改参数字段不会让已挂载的页面
   重新收到新值**，只有整页重新创建（切页签再切回来）才会用上新值。

所以"切页签才更新"是这个问题的典型指纹。

**修法**（`ets/pages/WorkbenchPage.ets` + `ets/types/PageParams.ets` + `pages/MainPage.ets`）
工作台改为**直接订阅 `AppStore`**：
`AppStore` 是 `@ObservedV2` + `@Trace`，其字段变化**必定**触发依赖组件重绘，
这是 ArkUI 里最可靠的响应式路径，异步到达的值不会再丢。

- **读** → `@Computed get serverOnline()` 等，直接读 store；
- **写** → 仍走窗口层注入的回调（不碰路由栈、不发请求，纪律的核心保留）；
- `WorkbenchPageParam` 退化为"路由分发识别 + 携带回调"的载体（不再承载展示数据）。

**★ 这是本工程唯一一处刻意偏离"页面不 import store"纪律的地方**，
偏离理由已写在 `WorkbenchPage.ets` 文件头。其它页签的数据是"进页面时一次性拉取"的，
没有这个痛点，继续走参数契约。

**防复发规则**
> 页面数据若**异步到达**（探活、WebSocket、轮询），不要依赖"父组件改参数字段"来刷新 ——
> 让页面直接订阅 `@ObservedV2` / `@Trace` 的源对象，或用 `@ObservedV2` 的状态类承载。
> 反之，若数据是"进入页面时一次拿到"的静态投影，参数契约仍然是更好的选择
> （引用稳定、不整树重建）。

---

## BUG-11 · 「选择图库素材」选完图片后停在选择页，等于没选 ⭐⭐ 本轮主诉

**现象**
工作台点「选择素材」→ 进素材选择页 → 点卡片打开系统相册 → **选中一张图片** → 回到 App 后，
页面**一点变化都没有**：还是「尚未选择素材」、按钮还是「选择素材」，也没有进入分析详情页。
用户原话：**"等于没选"**。

**根因（两条叠加，任一条都足以让这一步看起来无效）**

### ① 参数类不是 `@ObservedV2`，页面挂载之后改字段不刷新

`MediaPickerPageParam` 是**普通 class**。`MediaPickerPage` 是 `@ComponentV2` + `@Param pageParam`，
由 `Navigation.navDestination` 挂载；而窗口层（`MainPage.pickMedia()`）是在
**`await` 系统选择器之后**才回填 `hasPicked / pickedName / pickedUri`。

ArkUI V2 的 `@Param` 只观察"父组件把一个**新值**传下来"这件事；
要让**对象字段的写入**被感知，该类必须是 `@ObservedV2`、字段必须是 `@Trace`。
于是选完图片后：预览不出现、按钮文案不变、连错误文案都不会显示 ——
屏幕上是**真的什么都没变**，看起来就像"选择没生效"。

> 这条和 **BUG-10 是同一条根因**。BUG-10 当时只给工作台开了
> "页面直接订阅 `AppStore`"的口子，**没有回头检查其它参数类** —— 这一页因此被漏掉。
> 教训不是"再修一次"，而是：**修一条根因时，要把同族的其它调用点一起过一遍。**

### ② 交互链路少了一跳：选完之后没有"继续往前"

计划 §3 / §6 的验收口径写的是「选一张图 → 上传成功 → **自动**进详情页」，
而实现是"选择素材"和"开始分析"两个按钮分两步走，第二步没有任何自动触发。
**即使把 ① 修好，用户选完仍然停在选择页**，只是按钮变成了「开始分析」—— 与验收口径不符。

**修法**

| 文件 | 改法 |
|---|---|
| `types/PageParams.ets` | `MediaPickerPageParam` 改 `@ObservedV2`；会被挂载后回填的字段标 `@Trace`（`hasPicked` / `pickedName` / `pickedIsVideo` / `pickedUri` / `uploading` / `errorMsg`）。回调与 `title` 保持普通字段（只写一次） |
| `pages/MediaPickerPage.ets` | `requestPick()` 在回调返回 `true`、且 `hasPicked` 已回填后**立刻**接着调 `submit()`（上传 → 进详情页）。主按钮保留为**上传失败后的重试入口** |
| `pages/MainPage.ets` | 上传成功后用 `replacePathByName` 把"选择页"**换成**详情页（原来用 `pushPathByName`，从详情页返回会回到选择页、对同一份素材再点一次「开始分析」＝重复上传）。同时清掉窗口层的 `picked`、加"正在上传就不重复上传"的短路、并显式写回 `detailParam.followLiveTask = true` |
| `pages/AnalysisDetailPage.ets` | 新增 `liveStatus`：实时模式从 `AppStore.currentTask()` 取状态，历史快照仍读参数（见下方"顺带修掉"） |

**顺带修掉（同族，跳转落点上必然被看到）**：详情页原本只读参数里的 `status`，
而窗口层的 `syncDetailParam()` 只在"切页签 / 点工作台卡片"时被调用 ——
**WS 收尾不会触发它**。所以分析跑完后，页面会一直停在「分析中」
（进度已 100%、分数已出来，标签还是分析中）。
现在实时模式改为订阅 `AppStore` 的 `@Trace` 字段，跑完自动变「已完成 / 分析失败」。

**防复发规则**

> **要问一句：给参数对象赋值的那一行，是在页面 `NavDestination` 挂载之后执行的吗？**
> - 是（系统选择器 / 网络返回 / 异步回调之后才回填）→ 该类必须 `@ObservedV2`、字段必须 `@Trace`；
> - 否（push 之前写一次、挂载后不再变）→ 保持普通 class，**不要**顺手加装饰器。
>
> 这一类缺陷的共同指纹是：**"操作没生效"，但既不报错、日志也一切正常**。
> 排查时不要从"系统选择器是不是没返回"查起，先查"数据到底写进了什么对象"。

> 另一条：**任何"多步骤交互"（选 → 传 → 跳）都要明确定义"哪一步是自动推进的"**。
> 验收口径里写了"自动进详情页"，实现就必须有对应的自动调用；否则用户会在中途停下，
> 并把"停下的那一屏"当成"没反应"。

---

## BUG-12 · 选完图片后上传立刻报「网络不可达：Failed to open or read local data…」⭐⭐ 本轮主诉之二

**现象**（BUG-11 修好之后，选择页能正常显示预览了，但马上冒出一条红字）

```
网络不可达：Failed to open or read local data from the file or application。
请确认服务端已启动且手机与电脑同一局域网。
```

**根因（把"相册 URI"当成了"本地文件路径"）**

`MediaPicker.pickOne()` 拿到的是 `file://media/Photo/12/IMG_xxx/IMG_20261016_183531.jpg` ——
这是**媒体库 provider 的 URI**，不是文件系统路径。而上传走的是

```ts
const form: http.MultiFormData = { name, contentType, remoteFileName, filePath: file.filePath };
```

`@ohos.net.http` 的 `filePath` 只认真实路径（或应用沙箱路径），拿 provider URI 去 open
就会抛 **2300026 "Failed to open or read local data from the file or application"**
（见 SDK `@ohos.net.http.d.ts` 的错误码表）。

也就是说：**请求连正文都没读出来，一个字节都没发给服务端**。
更糟的是 `ApiError.toApiError()` 把不认识的码一律当"网络类"处理，
于是这条本地文件错误被写成「网络不可达……请确认服务端已启动」，
把排查方向整体带偏到了后端 —— 用户真以为是自己没重启服务端。

> ★ 这条错误的**上一轮注释本身就是错的**：`MediaPicker.ets` 文件头曾写着
> "`multiFormDataList[].filePath` 可以直接吃这个 URI，不需要先拷贝进沙箱"。
> 那是一条**从未在真机上跑过**的推断，被当成事实写进了注释，还被下一个接手者当依据。
> 教训：**没跑通过的链路，不要在注释里写"可以"**，要写"未验证"。

**修法**

| 文件 | 改法 |
|---|---|
| `common/MediaPicker.ets` | 新增 `stageToCache()`：选完立刻 `fs.open(uri, READ_ONLY)` → `fs.copyFile` 到 `<cacheDir>/picked/<原文件名>`，把**沙箱路径**作为 `uploadPath` 返回；新增 `attachContext()` 收一次应用上下文（拿 `cacheDir`） |
| `types/model.ts` | `PickedMediaModel` 新增 `uploadPath`（上传专用），`uri` 退化为"只用于 `Image` 预览" |
| `pages/MainPage.ets` | 上传用 `media.uploadPath`；为空时直接给"无法读取所选素材，请重新选择"，**不再**把读不到的文件丢给网络层 |
| `common/AppBootstrap.ets` | 启动时 `MediaPicker.attachContext(context)` 注入上下文 |
| `network/ApiError.ets` | 补 2300025 / **2300026** 的准确文案（"无法读取要上传的本地文件…"），不再一律说成"网络不可达" |

**为什么用异步 fs**：视频素材可能几十上百 MB，`copyFileSync` 会把 UI 线程卡住；
这里用 `await fs.copyFile(...)`，拷完才回填"已选素材"。

**防复发规则**

> **系统选择器（相册 / 文件）返回的 URI 一律视为"provider URI"，不是文件路径。**
> 任何要把选中的文件交给"只接受路径"的 API（`http` 上传、`request` 上传、拷贝、压缩……）之前，
> **必须先 `fs.copyFile` 到应用沙箱**，再把沙箱路径交出去。
>
> **看到 2300026 / "Failed to open or read local data"，先怀疑路径，不要怀疑网络。**
> 这类错误的共同指纹是：**报错信息里出现的是"本地文件"，却被打上了"网络不可达"的标签**。
> 错误分类表（`ApiError`）必须随新踩到的系统错误码同步更新，否则下次还会带偏方向。

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

> **后续更新（分析页实装轮 · 本轮）**：`followLiveTask` 这个开关已被**删除**。
> 它虽然是当时正确的修法，但只解决了"参数不被覆盖"，没解决"数据从哪来"：
> 历史素材的逐帧数据**根本不存在**，页面只能拿"全局最新一帧"顶替 —— 那正是 BUG-14。
> 现在改为「按 `mediaId` 归档的分析会话」提供数据（`AppStore.analysisSessionOf(mediaId)`），
> 参数里只放素材元信息与报告回落值。
> **结论（比原来那条更普适）**：多数据源页面要按**数据身份**（mediaId）取数，
> 而不是靠一个布尔开关分流，更不要用"全局最新"兜底。

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

## 给下一位接手者的五条硬规则

1. **装饰元素的尺寸必须是常量**；位置/缩放走 `position` / `translate` / `scale`。
   **绝不要**让"测量结果 → 状态 → 元素尺寸"形成链路，也不要在装饰组件上挂 `onSizeChange`。
   如果做不到，就**直接用平台原生能力**（如 `clickEffect`）而不是自己拼一个。
   （BUG-01，本项目最贵的一条教训）
2. **不要让"百分比高度的包裹层"和"AUTO 高度的内容层"同处一个容器** ——
   父容器 AUTO 时百分比高度会算成 0，整行高度变 0、内容整片不可见。（BUG-07）
3. **异步到达的数据不要依赖"父组件改参数字段"刷新** ——
   让页面直接订阅 `@ObservedV2` / `@Trace` 的源对象。（BUG-10）
   **推论（BUG-11）**：如果确实要经参数传，那个参数类**本身**必须 `@ObservedV2`、字段必须 `@Trace`，
   否则"页面挂载后再回填字段"等于没写。判断方法只有一个：
   **给字段赋值的那一行，是不是在页面 `NavDestination` 挂载之后执行的？**
4. **卡片/控件视觉用内联属性方法**；`AttributeModifier` 不要做全局单例复用。（BUG-08）
   色值一律 6 位 `#RRGGBB`，透明度走独立字段。（BUG-09）
5. **列表与列表项分两层交互单元**，动画与点击下沉到每一项；
   重放动画要把所有动画属性一起复位；
   **多数据源页面按"数据身份"（如 mediaId）取数，不要用布尔开关分流，
   更不要用一个"全局最新"兜底。**（BUG-02 / 03 / 04 / 05 / 14）

### 工作方式上的规则（比技术规则更重要）

6. **涉及布局边缘行为（绝对定位 / 零尺寸父容器 / 百分比高度）时，
   先在 DevEco 预览器做最小复现验证**，不要在正在使用的生产组件上反复试。
7. **优先用平台原生能力**。自己用基础组件拼一个"看起来一样"的效果，
   往往要付出远超预期的边界成本。
8. **不要把半成品交给用户去真机验证**。这一轮 `RippleCard` 连改 4 次、
   每次都要用户截图反馈 —— 正确做法是先在本地把可能性收敛到 1 种。
9. **用户说"操作没生效"时，先查"数据写进了什么对象"，再查"系统能力是不是没返回"。**
   BUG-11 里系统选择器其实**正常返回了**，是参数对象不可观察 + 链路少一跳，
   两处叠在一起让整条操作看起来完全无效 —— 而它**不报错、日志也正常**。
   这类"静默失效"必须先怀疑 Reactivity，不要一上来就怀疑系统 API。
10. **系统选择器给的 URI 不是文件路径**；交给"只接受路径"的 API 之前必须先拷进沙箱。（BUG-12）
   顺带：**没在真机上跑通过的链路，不要在注释里写"可以直接用"** ——
   那条错误注释正是 BUG-12 的源头。

---

## 尚未验证（需要真机确认）

编译与打包已通过（`BUILD SUCCESSFUL`），但以下运行时行为必须真机复核：

1. **卡片高度是否恒定**（点一下 / 长按 / 拖动都不该变化），且**初始高度正常**（BUG-01 最终验证点）；
2. 按压时是否看到原生涟漪 + 整卡轻微着色；抬起后底色是否复原；
3. **点右上角刷新：服务圆点与文案是否立刻变化**（BUG-10 验证点，不需要切页签）；
4. 点「最近使用的素材」单条：进入**该素材**的分析详情页（不是历史报告页）；
5. 点「查看全部」：仍然切到历史报告页签；
6. 从详情页返回工作台，「当前任务」是否仍在推进（后台分析未中断）；
7. 历史快照模式下不出现「取消分析」按钮；
8. 不可点的展示卡片（空态、区块外壳）按下时**不应**出现着色（避免"有反馈却没反应"的误导）。

### BUG-11 / BUG-12 的验证点（必须在**有相册素材的真机**上做，模拟器相册为空跑不了）

9. 工作台「选择素材」→ 选择页 → 点卡片 → 系统相册 → 选一张图 →
   **页面立刻出现「已选素材」预览**（不再毫无反应），随后自动上传并**跳到分析详情页**；
10. 上传中能看到「正在上传到服务端…」；**服务端没起时**现在应提示
    「无法连接到服务端（检查后端是否已启动…）」，而**不再**是那条 `Failed to open or read local data`；
11. 从分析详情页按返回 → **回到工作台**（不是回到选择页），且「当前任务」在推进；
12. 详情页状态标签会从「分析中」自动变成「已完成」/「分析失败」（不需要切页签）；
13. 选到**不在白名单**的格式（如 `.heic`）时，选择页要明确提示"暂不支持 .heic 格式"，而不是静默无反应；
14. 上传成功后服务端 `media_assets` 里能查到这条素材，名字是原文件名（如 `IMG_20261016_183531.jpg`）。

---

# 分析页实装轮 · 新增缺陷（BUG-13 / 14 / 15）

> 本轮目标：把「分析详情页」从半成品做成完整页面，并修掉用户实测到的三个缺陷。
> 涉及文件：`harmony/entry/src/main/ets/**`（端上）、`dashboard/backend/services/frame_processor.py`
> 与 `dashboard/src/components/right-panel/EmotionCurve.vue`（跨端一致性）。
> 交付说明：`docs/本轮交付说明-分析页实装.md`。离线守卫：`harmony/scripts/test-analysis-detail.mjs`。

## BUG-13 · 一张图片被服务端推成"10 帧"，退出再看又只剩 1 帧

**现象**
上传一张图片分析，帧数显示 10、逐帧列表铺满 10 格；返回工作台再从「最近使用的素材」点回来，
同样的素材变成"1 帧"。用户由此**分不清图片和视频**。

**根因（两处，缺一不可）**
1. 服务端 `services/frame_processor.py::_process_image` 为了让网页端曲线"有点可画"，
   把同一次推理的结果**重复推 10 帧**（10 步循环 + 每帧 `sleep(0.2)`）——
   图片本来只有一次推理，这是**伪造帧数**。
2. 端上没有"图片 = 单帧"的语义：帧数、逐帧列表、曲线都按"收到几帧算几帧"渲染，
   于是同一个素材在不同路径下呈现不同帧数。

**修法**
1. 服务端：图片路径**只推 1 帧**（`frame_id=1, progress=1.0`），删掉 10 步循环。
2. 端上：`AnalysisChartModel.resolveFrames()/displayFrameCount()` 按**素材类型**归一 ——
   图片永远最多 1 帧、帧数文案恒为 1（即使服务端仍推了 10 条重复帧）。
3. 网页端 `EmotionCurve.vue` 同步：单点数据画成**水平直线**并加一句说明。

**涉及文件**
`dashboard/backend/services/frame_processor.py`、`components/charts/AnalysisChartModel.ets`、
`pages/AnalysisDetailPage.ets`、`components/charts/EmotionCurveCard.ets`、
`dashboard/src/components/right-panel/EmotionCurve.vue`

**防复发规则**
> **不要为了"让图看起来有内容"而伪造数据条数。**
> 一条样本就画一个样本该有的图（单帧 → 直线 + 刻度尺），不要凑点。
> 服务端推什么、端上画什么，必须以**素材本身的物理事实**（图片=一次推理，视频=N 帧）为准。

---

## BUG-14 · 换个素材重新分析后，所有历史素材的热力图都变成"最近那个人" ⭐⭐ 本轮主诉

**现象**
先后上传并分析素材 A、B 之后，从「最近使用的素材」分别打开 A 和 B，
**两个页面显示的都是 B 的人脸与注意力热力图**；即"后上传的素材覆盖了之前的"。

**根因**
`components/charts/HeatmapViewModel.buildHeatmapView()` 有第五个参数 `lastFrame`，
语义是"当前会话里最近的一帧"，并在**没有本素材逐帧数据**时回退成 `frames = [lastFrame]`：

```ts
// 旧代码（已删）
if (lastFrame !== null && hasHeat(lastFrame)) {
  return { frames: [lastFrame], heatmap: lastFrame.heatmapData, source: HeatSource.snapshot };
}
```

而当时的分析结果**只有一份全局缓冲**：`AnalysisStateHolder.start()` 第一件事就是
`reset()` 把 `frameHistory` / `scoreHistory` 清空。于是：
- 历史素材页**从来没有自己的帧**，必然走这条兜底；
- 兜底取的是 `AppStore.analysisLastFrame` —— **与所看素材无关的全局最新一帧**；
- 结果：所有素材都显示最近分析的那个人的结果。顺带还解释了"回来只剩 1 帧"（BUG-13 的另一半）。

**修法**
1. 数据层改为「**按 mediaId 归档的会话**」：`AnalysisSessionModel`（frames / scores /
   状态 / 分数 / VLM 文本），存于 `AnalysisState.sessions`（`@Trace`，整体替换引用）。
   `start()` 只重置 **live 指针** 与"该素材自己那一条"，其它素材的结果原样保留；
   同一素材再次分析 = 覆盖它自己那一条。
2. **删除 `lastFrame` 兜底**：`buildHeatmapView(frames, sampleFrames, focusedIndex, isLive)`
   只画调用方按 mediaId 解析好的帧；取不到就空 → 页面显示"本机未保留逐帧数据"。
3. 详情页唯一取数入口：`AppStore.analysisSessionOf(pageParam.mediaId)`。
4. 没有会话时的出口：`AnalysisDetailPageParam.onReanalyze` →「重新分析该素材」
   （页面因 `analysisLiveMediaId === mediaId` 变真而自动切到实时数据，不必重新入栈）。

**涉及文件**
`types/model.ts`、`types/storeState.ets`、`store/AnalysisStateHolder.ets`、`store/AppStore.ets`、
`components/charts/HeatmapViewModel.ets`、`components/charts/AnalysisChartModel.ets`、
`types/PageParams.ets`、`pages/MainPage.ets`、`pages/AnalysisDetailPage.ets`

**防复发规则**
> **任何"取不到就回退到全局最新"的兜底，都会把 A 数据画到 B 的界面上。**
> 兜底只能回退到"同一身份的更粗粒度数据"（例如同一素材的报告分数），
> 绝不能回退到"全局最近的另一条记录"。
> 数据层就该存"每条身份自己的结果"，而不是一份全局最近值。

---

## BUG-15 · 分析跑完了，档位标签与「智能解读」永远不出现

**现象**
上传素材 → 详情页开始分析 → 分数与进度在动，但**档位中文标签（正常/轻度/…）一直是空的**；
VLM 文本解读也在分析完成后依然不显示。

**根因**
详情页的档位标签、档位颜色、VLM 文本都从**页面参数**读
（`pageParam.severityLabel / severityColor / vlmText`），而这些字段由窗口层的
`MainPage.syncDetailParam()` 从 `AppStore` 抄写。该方法**只在"切页签 / 入栈"时被调用**，
WebSocket 收帧与 `done` 都不会触发它（文件头那句"WS 每来一帧都会走到这里"与实际不符）。
入栈那一刻分数还是 0 → `severityLabel` 留空 → 之后**再没有任何时机**把它填上。

**修法**
1. **删除 `syncDetailParam()` 与参数里的这些实时字段**（连同 `followLiveTask`）。
2. 页面实时数据全部从 `@Trace` 会话读：
   `AppStore.analysisSessionOf(mediaId)` → 状态 / 进度 / 分数 / 帧 / VLM；
   档位由**分数现算**（`severityMetaOf()`，`BdiThreshold` + `UiConstant` 单一口径），
   不再从参数读快照值。
3. 参数里只保留"入栈那一刻就确定"的信息：素材名 / 类型 / 报告分数 / 报告时间 + 回调。

**涉及文件**
`types/PageParams.ets`、`pages/MainPage.ets`、`pages/AnalysisDetailPage.ets`、
`components/charts/AnalysisChartModel.ets`

**防复发规则**
> **异步到达的数据不要经"页面参数"这条单向管道传递**（与 BUG-10/BUG-11 同根）：
> 参数是"入栈那一刻的快照"，而分析结果是**持续到达**的。
> 判断方法：这段数据在页面挂载**之后**还会不会变？会 → 必须走 `@ObservedV2` + `@Trace` 的源对象。

---

## 本轮验证清单（编译/离线已过，运行时需真机）

已确认：
- `node harmony/scripts/test-analysis-detail.mjs` → PASS（含 A/B 素材不串台、图片恒 1 帧的回归守卫）
- `node harmony/scripts/test-heatmap-strip.mjs` → PASS（含"不得跨素材兜底"的源码级守卫）
- `bash harmony/scripts/build.sh` → `BUILD SUCCESSFUL`（`CompileArkTS` 7.3s，HAP 已重新产出）
- `npx vue-tsc --noEmit -p tsconfig.app.json` → 本轮改动的 `EmotionCurve.vue` **0 error**
  （仓库里另有 5 个**历史遗留**的 TS 报错文件，与本轮无关，未动）

待真机确认：
1. 传一张图片 → 徽标「图片」、**1 帧**、情绪曲线是**水平直线**、严重度是**刻度尺**；
2. 返回后分别从「当前任务」和「最近使用的素材」再进入 → 仍是同一张脸、同一热力图、仍是 1 帧；
3. 传一段视频 → N 帧、可横滑、情绪曲线是折线、严重度是**帧级环形分布**（环心「N 帧」）；
4. 先分析 A 再分析 B，然后分别打开 A / B → **各自显示自己的人脸与热力图**（BUG-14 验证点）；
5. 打开本轮之前分析过的历史素材（本机无会话）→ 报告分数 + 「本机未保留逐帧数据」+
   「重新分析该素材」；点后页面应自动开始出帧；
6. 分析完成后档位标签与「智能解读」**自行出现**（BUG-15 验证点，不需要切页签）。

---

# 工作台二次打磨轮 · 新增缺陷（BUG-19）

> 本轮改动见 `docs/本轮交付说明-工作台二次打磨.md`。
> 需求只有两条：① 在线提示删掉，只在离线时提示「无法连接服务器」；
> ② 「当前任务」上移，并附首帧照片 + 表示 BDI 的进度条。
> 实施中踩到 1 个**编译通过、截图才能发现**的响应式缺陷，记在这里。

## BUG-19 · 当前任务卡片里"照片/档位标签/档位色/BDI 进度条"停在创建那一刻，只有分数在实时更新

**现象**
给「当前任务」卡片加首帧照片与 BDI 进度条后，真机截图显示一张**自相矛盾**的卡片：

| 元素 | 显示结果 | 正确答案 |
|---|---|---|
| 素材名 / 状态「已完成」/ 状态圆点 | 正常 | ✔ |
| BDI 分数 `11.7` | 正常（会随分析推进变化） | ✔ |
| **档位标签「正常」** | **不显示** | 应该显示 |
| **分数颜色** | **中性灰 `#64748b`** | 应该是档位绿 `#16a34a` |
| **BDI 进度条填充** | **空的（0%）** | 应该约 18.6% |
| **首帧照片** | 显示的是**媒体缩略图**（分值 0 时的回落图） | 应该是首帧对齐人脸 |

同一张卡片里"一半新、一半旧"，且分数正确、其余全错 —— 极易误判成"数据没传到组件"。

**根因（`@Builder` 参数是按值传递的）**
最初的写法把整个任务对象交给 builder：

```ts
// ✘ 错误写法
@Builder
taskCard(task: CurrentTaskModel) { /* 全部用 task.xxx */ }

build() {
  if (this.task !== null) { this.taskCard(this.task) }   // 只在首次构建时求值
}
```

`this.taskCard(this.task)` 里的 `this.task` 只在**首次构建**时被读一次，对象按值传进 builder。
之后 `@Param task` 换成新对象时，ArkUI V2 只会重算**直接依赖响应式变量**的表达式：

- `Text(this.scoreText)` —— `scoreText` 是组件上的 `@Computed`，依赖 `this.task` → **会更新**；
- `if (task.severityLabel.length > 0)` / `.fontColor(task.severityColor)` /
  `ProgressBar({ ratio: task.scoreRatio })` —— 读的是 builder 内部那个**局部参数** `task`，
  不在任何响应式依赖链上 → **永远停在首次构建的值**。

两个后果叠在一起：
1. 首帧照片与档位色/标签/进度条 = 首次构建时的值（此时还没收到帧，分数 0 → 回落到缩略图、
   空标签、中性色、空进度条）；
2. 分数却跟着 `@Computed` 更新 → 看起来"数据只到了一半"。

> 这与 BUG-10 / BUG-15 是**同一族**问题：都不是"数据没来"，而是**数据来了但没人通知 UI**。
> 只是这次的断点在 `@Builder` 参数上，不在路由参数上。

**修法**
本组件的纪律：**`@Builder` 一律不带参数**，所有取值都从组件上的 `@Computed` getter 读。

```ts
// ✔ 正确写法（CurrentTaskCard 现行结构）
@Computed get firstFrameUrl(): string { ... }
@Computed get severityLabel(): string { ... }
@Computed get severityColor(): string { ... }
@Computed get severityRatio(): number { ... }

@Builder
firstFrame() { /* 只读 this.firstFrameUrl / this.mediaGlyph */ }

@Builder
taskCard() { /* 只读 this.*，ProgressBar({ ratio: this.severityRatio }) */ }

build() {
  if (this.hasTask) { this.taskCard() } else { this.emptyCard() }
}
```

于是照片、档位、进度条、分数走**同一条响应式路径**，不会再出现"一半新一半旧"。
（同一轮里「最近使用的素材」用的是 `ForEach` + builder 参数，但数组换引用时整段会被重建，
所以那里不受影响 —— 判断标准是"这段子树会不会被重新创建"，而不是"有没有用参数"。）

**涉及文件**
`components/workbench/CurrentTaskCard.ets`（重写为无参 builder + `@Computed` 取值）

**防复发规则**
> **`@Builder` 不要接业务参数。** 需要随状态变化的值，一律先做成组件上的 `@Computed`，
> builder 里只写 `this.xxx`。
> 自查方法：如果 builder 的参数来自 `@State/@Local/@Param`，且值会**在页面挂载后变化**，
> 就必须改成无参 + `@Computed`（或交给 `ForEach` 用新数组重建）。
> 另外：这类问题 `CompileArkTS` 一定不报错，**只能靠真机截图**发现
> —— 所以本轮的验收方式是"装机 → 截图 → 逐元素对色"，不是"编译通过就算完"。

---

## 本轮验证方式（真机/模拟器实测，不是推测）

模拟器 1316×2832（API 23），装机后按下面三步走，并**逐元素比对像素颜色**
（`#16a34a` 绿 = 档位色、`#EDF2F7` 灰 = 进度条轨道）：

| # | 操作 | 期望 | 结果 |
|---|---|---|---|
| 1 | 冷启动进工作台（服务端在线） | **没有任何服务状态元素**、无服务器地址；「当前任务」在「开始新的辅助评估」上方 | ✅ 见 `_materials/_verify/v2_online.jpeg` |
| 2 | 历史报告 → 某素材 → 「重新分析该素材」→ 返回工作台 | 卡片有**首帧照片**、`11.7`（绿）、「正常」、BDI 进度条填充约 18.6%、状态「已完成」 | ✅ 见 `_materials/_verify/v2_task.jpeg`（BUG-19 修复后的样子） |
| 3 | 把 `ApiConfig.host` 临时改成不可达地址后冷启动 | 顶部出现**红点 +「无法连接服务器」+「重试」**，**不显示服务器地址**；本地缓存内容照常显示 | ✅ 见 `_materials/_verify/v2_offline2.jpeg`（验证后已改回 `100.122.178.113`） |

> 第 3 步的地址改动是**临时**的，验证后已还原；`git status` 里 `ApiConfig.ets` 无改动。
> 模拟器 non-root（`uid=2000(shell)`），`svc wifi/data` 与 `ifconfig eth0 down` 都无权执行，
> 所以"断网"只能从**代码侧指向不可达地址**这条唯一途径造出来。

---

# 登录重构 / 开屏页 / 我的页 · 本轮新增（BUG-20 / 21 / 22）

> 需求与交付：`我的页面搭建方案prompt.md`、`docs/本轮交付说明-登录重构与我的页.md`。
> 本轮**不是**"照着需求画界面"就完事：三条缺陷全部是装机实测跑出来的，
> 两条只有真机才看得见（BUG-20 的按钮卡死、BUG-22 的白屏）。

## 先说结论：用户报的"一直提示密码错误"，不是 bug

后端 `routers/auth.py:64` 对"用户不存在"和"密码错"返回**同一个** 401
（`detail=用户名或密码错误`），所以界面上永远只能看到同一句话。经对服务端直接实测：

| 用户名 | 密码 | 结果 |
|---|---|---|
| `xincell` | `712098opa` | 200（id=12） |
| `xincell` | `712098op` | 401 |
| `xincell1013` | `712098opa` | 200（id=8） |
| `xincell1013` | `712098op` | 401 |

**正确密码是 `712098opa`，少输末尾的 `a` 就必然 401。** 服务端匹配、JWT、`/me` 全链路正常。

同类排查以后请直接用脚本（不必再猜）：

```bash
node harmony/scripts/check-login.mjs <用户名> <密码> [http://host:port]
# 退出码：0 成功 / 1 账号密码不匹配 / 2 服务端不可达 / 3 其它
```

> 顺带确认：仓库里的 `dashboard/backend/depression.db`（8 用户 / 126 报告）与
> 服务器上那份库（≥13 用户 / 140 报告）**不是同一份**。
> 用本机 `启动-仅本机.bat` 起的后端注册的账号，拿到 Tailscale 服务器上登录必然 401 ——
> 这是"密码绝对没错却一直报错"的第二种常见成因，所以本轮在登录页底部**常驻显示服务端地址**。

**防复发规则**
> 界面上说"用户名或密码错误"时，先回答"服务端到底有没有回应"。
> 服务端**回应了** 401 → 查账号密码/账号归属（哪台服务器注册的）；
> 请求**没到** → 查地址与网络。两者混在一起就会像这次一样反复试密码。
> 本轮已把这条判据做进界面（`AuthFailKind` + 弹窗第三行诊断行）。

---

## BUG-20 · 登录失败后按钮永远停在「登录中…」、输入框全部禁用 ⭐⭐ 真机才看得见

**现象**
输错密码点「登录」，服务端返回 401 后：错误弹窗正常出现、错误文案也正常，
但**主按钮文案一直停在「登录中…」**、两个输入框全部变灰不可输入。整个登录页等于卡死。

**根因（`loading` 没有复位）**
`AuthStore.login()` 的失败路径原本走 `handleFailure()`，而这一轮给 `handleFailure()` 加了
"失败分类"之后，误把里面**唯一的 `endLoadErr(...)` 调用换成了只写 `errorMsg` 的 `markFail()`**：

```ts
// ✘ 改坏之后
private handleFailure(err: Object) {
  this.markFail(kind, apiErr.code, apiErr.message);   // 只写 errorMsg
  ...
}
// ✔ 正确
private handleFailure(err: Object) {
  this.endLoadErr(apiErr.message);   // ★ 它才是把 loading 置回 false 的那一行
  this.failKind = kind;
  ...
}
```

`endLoadErr()` 是 `BaseStore` 里唯一负责 `loading = false` 的地方。绕过它，
`AuthStore.loading` 就永远是 true → 页面 `busy` 永远为 true → 按钮文案「登录中…」+ 全部禁用。

**为什么编译和静态检查都发现不了**：状态机不报错、网络请求正常、hilog 里一切正常
（确实打印了 `鉴权失败 · [credentials/401]`）。**只能靠真机截图看按钮文案**。

**修法**
失败路径统一先 `endLoadErr(message)`，再记 `failKind` / `failStatus`；
本地校验失败（`markFail`）也走同一条，避免出现第二条"忘记复位 loading"的岔路。
另外每次新尝试开始时 `clearFail()`，避免"旧标题配新文案"。

**防复发规则**
> **动 `BaseStore` 的那对 `beginLoad` / `endLoadOk|endLoadErr` 时，先确认 succeed 与 fail
> 两条路都调到了"收尾"的那一个。** 只写 `errorMsg` 不算收尾，`loading` 会一直挂着。
> 判据：任何一条 `beginLoad()` 之后，必定有且只有一次 `endLoadOk()` 或 `endLoadErr()`。

---

## BUG-21 · 登录页的错误文案不出现（挂载后回填的字段"等于没写"）⭐⭐ 与 BUG-11 同根

**现象**
登录失败后弹窗正常，但**输入框下方那行红色错误文案是空的**；
切换页签 / 重新进页面之后它才"忽然"出现。

**根因（参数类不可观察）**
`LoginPageParam` / `RegisterPageParam` 是**普通 class**，而窗口层是在
`await AuthStore.login(...)` **之后**才回填 `authBusy / authError / ...` 的 ——
那时登录页早就挂载好了。ArkUI V2 的 `@Param` 只观察"父组件传下来一个新值"这件事，
**对象内部字段的写入**必须靠 `@ObservedV2` + `@Trace` 才能被感知。

上一版 `PageParams.ets` 的注释里写着一条**错误结论**：
"登录/注册参数类的字段都是 push 之前写一次，所以不要给它们加装饰器"。
这条注释本身就是 BUG-11 的复现条件。

**修法**
`LoginPageParam` / `RegisterPageParam` 改 `@ObservedV2`；
**挂载后会被回填**的字段（`authBusy` / `authError` / `authErrorTitle` / `authErrorHint` /
`retryMessage` / `retrying` / `serverLabel`）标 `@Trace`；
回调与"push 前写一次"的字段保持普通字段（不给每次写入白挂观察者）。

**防复发规则**
> 判断标准只有一条（BUG-11 立的规矩，本轮再次被它咬到）：
> **给字段赋值的那一行，是在页面 `NavDestination` 挂载之后执行的吗？** 是 → 必须可观察。
> 推论：**"参数只在入栈前写一次"这种说法必须逐字段核对，不能整类打包下结论。**
> 登录页是反例的典型：它的"入栈"发生在冷启动，而"填值"发生在之后每一次点登录。

---

## BUG-22 · 登录页按系统返回键 → 整屏纯白（像应用卡死）

**现象**
在登录页按返回键，界面变成**一整屏纯白**（只剩状态栏）。没有报错、进程也还活着。

**根因**
登录页是登录流（`Navigation(this.loginStack)`）里的**唯一页面**。返回键把它弹出后
栈为空，`Navigation` 就露出自己的**根内容** —— 而 `Index.authStage()` 里的根内容
只是一个占位的空 `Column`（当初是为了"栈意外为空"时不崩，本身就假设走不到）。

**修法**
1. 登录页的 `NavDestination.onBackPressed(() => true)`：登录页是登录流的根，
   **消费**返回事件，不允许被弹掉（注册页不拦截，返回键照常回到登录页）。
2. 根内容加"自愈"：`Column().onAppear(() => { if (this.loginStack.size() === 0) this.resetLoginStack(); })`
   —— 万一将来还有别的路径把栈清空，这段一露出来就把登录页压回去，而不是留一块白屏。

**防复发规则**
> **"栈意外为空时的兜底画面"不能是空白页。** 兜底要么自愈（重新入栈），
> 要么给用户一个明确的出口；纯色空 `Column` 在真机上与"应用死了"无法区分。
> 另外：`Navigation.onBackPressed` 只存在于 `NavDestination` 上（`Navigation` 没有），
> 拦截根页面返回键要写在分发器的 `NavDestination` 上。

---

## 本轮验证记录（模拟器 1316×2832 API 23，装机实测）

| # | 操作 | 期望 | 结果 |
|---|---|---|---|
| 1 | 冷启动 | 系统启动窗口 → 开屏页（图标 + `MindScope`）→ 淡出到登录页 | ✅ `_materials/_verify/splash_new.jpeg` |
| 2 | 错密码登录 | 弹窗从左侧弹入、撞在左屏、停在输入框之上；行内红字同时出现；按钮**回到「登录」**且可再点 | ✅ `alert_flying.jpeg` / `alert_fixed.jpeg`（BUG-20/21 验证点） |
| 3 | 正确密码登录 | 进入工作台，媒体 15 条 / 报告 140 条 / 统计全部拉取成功 | ✅ `login_ok.jpeg` |
| 4 | 我的页签 | 账户卡（头像首字 + 用户名 + 邮箱）+ 四行信息（账号 ID / 注册日期 / 服务端 / 版本）+ 退出登录 | ✅ `profile_new.jpeg` |
| 5 | 点退出登录 → 确认 | 二次确认弹层 → 清令牌清缓存 → **回到登录页**（不是注册页） | ✅ `confirm_new2.jpeg` / `back_before.jpeg` |
| 6 | 登录页按返回键 | 仍是登录页（不再白屏） | ✅ `back_after.jpeg`（BUG-22 验证点） |

编译：`bash harmony/scripts/build.sh` → `BUILD SUCCESSFUL`（`CompileArkTS` 真跑）。


