/**
 * RippleCard · **通用可点击卡片**（统一卡片视觉 + 原生按压反馈）
 *
 * 本轮工作台的所有卡片都走这一个组件，好处是：
 *   ① 卡片外观的**取值**只有一处（`common/CardStyle.ets`），不会各处漂移；
 *   ② 按压反馈只实现一次，新卡片自动获得同一手感；
 *   ③ 页面只需传"数据 + 回调"，不需要关心交互怎么做。
 *
 * 用法：
 * ```ts
 * RippleCard({ onTap: () => { ... } }) {
 *   Text('卡片内容')
 * }
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
 * ● 可点击的卡片会得到一个很淡的按压底色；不可点的展示卡片保持纯白
 *   （用 `PressTint.none` 覆写 `_pressColor`）。
 */

import { CardStyle } from '../common/CardStyle';
import { UiTheme } from '../common/UiTheme';

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
   * 需要"按下不换色"时传 `UiTheme.cardBackground`（不可点的展示卡片就是这么做的）。
   */
  @Param _pressColor: string = UiTheme.cardPressTint;

  /** 卡片内容（用尾随闭包传入） */
  @BuilderParam content: () => void = this.emptyContent;

  // ────────────────── 本地交互状态（纯视觉，不参与任何测量）──────────────────

  /**
   * 是否处于按下态
   * ★ 它只影响 `backgroundColor`（一个**颜色**属性），不会改变任何尺寸 ——
   *   这正是"装饰状态绝不能驱动尺寸"这条规则的落地方式。
   */
  @Local pressed: boolean = false;

  @Builder
  emptyContent() {
    Row().width('100%').height(0)
  }

  /**
   * 按下 / 抬起时的底色（按下着色，抬起恢复卡片白底）
   * ★ 条件里带 `_enabled`：只有"真的有动作"的卡片才着色。
   *   空态、区块外壳、只读信息卡（`_enabled: false`）保持纯白，不会出现
   *   "按下去有反馈、松手却没反应"的误导。
   */
  private backgroundFor(): string {
    if (this.pressed && this._clickable && this._enabled) {
      return this._pressColor;
    }
    return CardStyle.background();
  }

  /**
   * 切换按下态并做颜色过渡
   * ★ `animateTo` 只包住一次颜色赋值：颜色变化不触发布局，只会走渲染层合成。
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
    // ★ 卡片视觉三项**内联**写在组件链上（不要抽成共享的 AttributeModifier，
    //   原因见 common/CardStyle.ets 顶部说明：共享修饰器实例会导致卡片整片不渲染）
    .backgroundColor(this.backgroundFor())
    .borderRadius(this._radius)
    .border({ width: 1, color: UiTheme.divider })
    .shadow(CardStyle.shadow())
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
