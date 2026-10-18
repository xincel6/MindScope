/**
 * RippleCard · **通用可点击卡片**（统一卡片视觉 + 原生按压反馈）
 *
 * 本轮工作台的所有卡片都走这一个组件，好处是：
 *   ① 卡片外观的**取值**只有一处（`common/CardStyle.ets`），不会各处漂移；
 *   ② 按压反馈只实现一次，新卡片自动获得同一手感；
 *   ③ 页面只需传"数据 + 回调"，不需要关心交互怎么做。
 *
 * 用法（同一套按压语言，区别只在"画不画底色"和"松手跳不跳转"）：
 * ```ts
 * // ① 可点击卡片：按下去有反馈，松手执行 onTap
 * RippleCard({ onTap: () => { ... } }) { Text('卡片内容') }
 *
 * // ② 有反馈但不跳转（统计页的卡片）：自己画底色，只借反馈
 * RippleCard({ _enabled: false, _clickable: true, _pressScale: 0.98, _padding: 0 }) { ... }
 *
 * // ③ 自带背景（渐变卡）：壳子一点不画，只借反馈
 * RippleCard({ _transparent: true, _enabled: false, _clickable: true, _pressScale: 0.985, _padding: 0 }) { ... }
 * ```
 *
 * ══════════════════════════════════════════════════════════════════
 *  ★★ 为什么这里是"整卡按压反馈"而不是"从触点扩散的自绘涟漪"
 * ══════════════════════════════════════════════════════════════════
 * 这个组件为了让涟漪"从手指按下的位置扩散"，连续踩了四个坑（详见根目录 `BUG清单.md`）：
 *
 *   1. 圆由**响应式状态**驱动尺寸 + 用 `onSizeChange` 回填卡片尺寸
 *      → 形成「测量 → 状态 → 尺寸 → 布局 → 测量」的反馈环，越点越走形；
 *   2. `Column` 里混用 `height('100%')` 包裹层与 `AUTO` 内容层
 *      → 百分比高度解析成 0，卡片整片不可见；
 *   3. 圆作为 `Stack` 的**直接子节点**（即使用 `position()`）
 *      → 它仍参与父容器测量，卡片被撑到"圆所占布局框"那么大，初始就过长；
 *   4. 试图用包裹层隔离这个尺寸时，**官方文档自相矛盾**：
 *      `position()` 的注解写 "The attribute is not available for a layout container whose
 *      width and height are zero"，即"零尺寸父容器里的绝对定位子节点不生效"；
 *      而另一处文档又说 `position` 的子节点"参与父容器测算"。两者无法同时成立，
 *      只能靠真机反复试错 —— 代价太高，且每次都直接把问题交给用户去发现。
 *
 * **结论：按本项目《BUG清单.md》规则一，装饰元素绝不能影响布局测量。
 * 与其不断试探边缘行为，不如改用 ArkUI 原生提供的按压反馈：零新增节点、零布局风险。**
 *
 * 现在的实现（两条都是原生能力，不新增任何节点）：
 *   · `.clickEffect({ level: ClickEffectLevel.LIGHT })` —— 系统级按压涟漪（点哪扩散到哪）；
 *   · `@Local pressed` + `.backgroundColor()` + `animateTo` —— 整卡轻微着色（按下变深、抬起复原）。
 *
 * ★ 如果将来确实需要"自绘、从触点扩散"的涟漪，请先做**隔离验证**：
 *   在 DevEco 预览器里单独搭一个"卡片 + 大圆"的最小页面，确认卡片高度不受影响后，
 *   再往本组件里移植；不要直接在本文件上试。
 *
 * ────────────────── 已知边界 ──────────────────
 * ● 按压反馈挂在 `TouchType.Down`，导航动作挂在 `onClick`：两者互不干扰，
 *   所以滚动列表里快速滑动不会误触发点击。
 * ● 卡片**内部**的独立控件（如 `Button`）会自己消费掉点击事件，
 *   此时父卡片拿不到 `onClick`（符合直觉：点按钮只应触发按钮）。
 *   因此"按钮与整卡做同一件事"的卡片，让两处 `onClick` 指向同一个处理函数即可。
 * ● **按压反馈的判据只有 `_clickable`**，`_enabled` 只决定"松手是否触发 onTap"。
 *   两者拆开之后才能表达"按下去有反馈、但不跳转"这种组合（统计页的卡片需要）。
 *   纯展示卡片传 `_clickable: false`：保持纯白、不缩放，行为与本轮扩展前完全一致。
 */

import { CardStyle, CardShadowOptions } from '../common/CardStyle';
import { UiTheme } from '../common/UiTheme';

/**
 * 全透明色（8 位 ARGB · alpha = 0）
 * ★ 为什么需要它：ArkUI 的属性链无法"按条件不写某个属性"，`_transparent` 的
 *   "不画底色/描边"只能表达成"画一个看不见的"。放模块级常量是因为 ArkTS 的
 *   `struct` 不允许声明静态成员。
 */
const TRANSPARENT_COLOR: string = '#00000000';

@ComponentV2
export struct RippleCard {
  /** 点击整卡的回调 · 不传则卡片只播放反馈、不产生动作 */
  @Param onTap: () => void = () => {};

  /**
   * 卡片内边距
   * ★ 名字带 `_`：`padding` 是 ArkUI 自定义组件的系统属性方法名，同名成员会编译失败。
   */
  @Param _padding: number = UiTheme.cardPadding;

  /**
   * 是否触发 `onTap` 动作
   * ★ 名字必须带 `_`：`enabled` 是 ArkUI 自定义组件的**系统属性方法名**
   *   （`CommonAttribute.enabled(value: boolean)`），同名成员会报
   *   "Property 'enabled' ... is not assignable to the same property in base type
   *    'CustomComponent'"。本工程约定：与系统属性同名的入参一律加 `_`。
   */
  @Param _enabled: boolean = true;

  /**
   * 是否播放按压反馈（与 `_enabled` 解耦）
   * ★ 名字不能叫 `clickable`：那同样是 `CommonMethod` 上的系统属性方法名。
   */
  @Param _clickable: boolean = true;

  /** 卡片圆角 · 默认沿用主题 */
  @Param _radius: number = UiTheme.cardRadius;

  /**
   * 按压时的底色 · 默认取主题里的淡色
   * 需要"按下不换色"时传 `UiTheme.cardBackground`，或者干脆传 `_clickable: false`
   * （后者连缩放一起关掉，纯展示卡片用这条路）。
   */
  @Param _pressColor: string = UiTheme.cardPressTint;

  /**
   * 只当"纯交互壳"：不画底色 / 描边 / 投影，供**自带背景**的卡片（如统计页渐变卡）包一层。
   * ★ 默认 false = 现在所有调用方的观感零变化。
   * ★ ArkUI 没有"不设置属性"的写法，所以"跳过"是靠下面把取值换成
   *   **全透明色 + 零投影**实现的 —— 属性链不能按条件拼接（build 里没有语句块）。
   */
  @Param _transparent: boolean = false;

  /**
   * 按下时缩到的比例（抬起回到 1）· 默认 1 = 不缩放，现有调用方不受影响
   * ★ 缩放是**渲染变换**，不参与任何布局测量，不会让卡片在自己那一格里挤出空隙。
   */
  @Param _pressScale: number = 1;

  /** 卡片内容（用尾随闭包传入） */
  @BuilderParam content: () => void = this.emptyContent;

  // ────────────────── 本地交互状态（纯视觉，不参与任何测量）──────────────────

  /**
   * 是否处于按下态
   * ★ 它只驱动 `backgroundColor` 与 `scale` 两个**渲染属性**，绝不改变任何尺寸 ——
   *   这正是"装饰状态绝不能驱动尺寸"这条规则的落地方式。
   */
  @Local pressed: boolean = false;

  @Builder
  emptyContent() {
    Row().width('100%').height(0)
  }

  /**
   * 按下 / 抬起时的底色（按下着色，抬起恢复卡片白底）
   *
   * ★ 判据只有 `_clickable`，**不再看 `_enabled`**：
   *   `_enabled` 表达的是"松手要不要执行 onTap"，`_clickable` 表达的是"有没有按压反馈"。
   *   统计页的卡片要的正是"按下去有反馈、松手不跳转"，旧判据拼不出这个组合。
   * ★ 这对现有调用方是安全的：工程里传 `_clickable: false` 的卡片
   *   （各页空态卡、分析区只读卡）同时也传了 `_enabled: false`，着色结果与改造前逐字相同。
   * ★ 透明壳态下**任何状态都不画底色**：卡片自带背景（渐变），壳子再涂一层淡色
   *   会在圆角边缘露出与渐变不搭的补丁。它的反馈交给缩放与系统涟漪。
   * ★ 这里不再重复判断 `_clickable`：`pressed` 只可能被 `onTouch` 置为 true，
   *   而那里已经把不可点的卡片直接 return 掉了 —— 判据只保留一处，不会两处漂移。
   */
  private backgroundFor(): string {
    if (this._transparent) {
      return TRANSPARENT_COLOR;
    }
    if (this.pressed) {
      return this._pressColor;
    }
    return CardStyle.background();
  }

  /** 描边宽度 · 透明壳态没有底色，再画 1px 收边就成了"有框没面"的怪卡片 */
  private borderWidthFor(): number {
    return this._transparent ? 0 : 1;
  }

  /** 描边颜色 · 宽度为 0 时一并给透明色，避免任何实现细节上残留一条线 */
  private borderColorFor(): string {
    return this._transparent ? TRANSPARENT_COLOR : CardStyle.borderColor();
  }

  /**
   * 投影 · 透明壳态返回**零投影**（与 `CardStyle.shadow()` 关闭开关时同一种写法）
   * ★ 不在属性链里写 if：`build()` 只能内联表达式，"跳过属性"统一表达成"零值取值"。
   */
  private shadowFor(): CardShadowOptions {
    if (!this._transparent) {
      return CardStyle.shadow();
    }
    const none: CardShadowOptions = {
      radius: 0,
      color: UiTheme.cardShadowColor,
      offsetX: 0,
      offsetY: 0
    };
    return none;
  }

  /**
   * 当前的缩放比例（按下缩到 `_pressScale`，其余时刻 1）
   * ★ 判据与底色一致：只认 `_clickable`，所以"有反馈不跳转"的卡片同样会缩。
   */
  private scaleFor(): number {
    if (this.pressed) {
      return this._pressScale;
    }
    return 1;
  }

  /**
   * 切换按下态并做过渡（颜色 + 缩放，同一个 `animateTo` 里一起走，反馈不会脱节）
   * ★ 被改的两个属性都不触发布局，只会走渲染层合成。
   */
  private setPressed(next: boolean): void {
    if (this.pressed === next) {
      return;
    }
    this.getUIContext().animateTo({ duration: UiTheme.pressDuration, curve: Curve.EaseOut }, () => {
      this.pressed = next;
    });
  }

  build() {
    // ★ 整个卡片就是**一层内容容器**：不再有装饰层，也就不存在任何尺寸被撑大的可能。
    //   卡片尺寸完全由 `content()` 与 `_padding` 决定。
    Column() {
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(this._padding)
    // ★ 卡片视觉**内联**写在组件链上（不要抽成共享的 AttributeModifier，
    //   原因见 common/CardStyle.ets 顶部说明：共享修饰器实例会导致卡片整片不渲染）
    // ★ 透明壳态不是"跳过属性"，而是把取值换成"什么都不画"：
    //   build() 的属性链不能按条件拼接，只能靠取值表达（同 CardStyle.shadow() 的关开关做法）。
    .backgroundColor(this.backgroundFor())
    .borderRadius(this._radius)
    // 灰底白卡：极淡投影负责"浮起"，1px 描边负责"收边"（见 common/CardStyle.ets）
    .border({ width: this.borderWidthFor(), color: this.borderColorFor() })
    .shadow(this.shadowFor())
    // 按下轻微缩到 `_pressScale`：只改渲染变换，不参与布局测量（同 RevealCard 的入场缩放）
    .scale({ x: this.scaleFor(), y: this.scaleFor() })
    // 系统级按压反馈：涟漪从触点扩散，且完全由系统实现，不影响布局
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onTouch((event: TouchEvent) => {
      if (!this._clickable) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.setPressed(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setPressed(false);
      }
    })
    .onClick(() => {
      if (!this._enabled) {
        return;
      }
      this.onTap();
    })
  }
}
