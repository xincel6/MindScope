/**
 * RippleCard · **通用可点击卡片**（统一卡片视觉 + 从触点扩散的点击涟漪）
 *
 * 本轮工作台的所有卡片都走这一个组件，好处是：
 *   ① 卡片外观只有一处定义（`common/CardStyle.ets`），不会各处漂移；
 *   ② 点击动画只实现一次，新卡片自动获得同一手感；
 *   ③ 页面只需传"数据 + 回调"，不需要关心动画怎么做。
 *
 * 用法：
 * ```ts
 * RippleCard({ onTap: () => { ... } }) {
 *   Text('卡片内容')
 * }
 * ```
 *
 * ────────────────── 涟漪是怎么实现的 ──────────────────
 * 1. `Stack` 底层放一个圆（半径 = 卡片对角线，保证放大后铺满整卡）；
 * 2. `onTouch(Down)` 取触点**相对本组件**的坐标，把圆挪到该点；
 * 3. `animateTo` 让圆的 `scale 0 → 1`（扩散）、`opacity 1 → 0`（淡出）；
 * 4. 卡片自身 `.clip(true)` + 圆角 → 涟漪被裁成圆角矩形，不会溢出卡片。
 *
 * 起始态"半径 0 但可见"在视觉上等于什么都没有（零面积画不出东西），
 * 所以不需要额外的"先隐藏再出现"处理 —— 每帧动画都在 `animateTo` 的闭包里
 * 先给值再触发，减少闪烁。
 *
 * ────────────────── 已知边界 ──────────────────
 * ● 涟漪挂在 `TouchType.Down`，导航动作挂在 `onClick`：两者互不干扰，
 *   所以滚动列表里快速滑动不会误触发点击。
 * ● 卡片**内部**的独立控件（如 `Button`）会自己消费掉点击事件，
 *   此时父卡片拿不到 `onClick`（这是 ArkUI 的冒泡规则，符合直觉：
 *   点按钮只应触发按钮）。因此"按钮和整卡做同一件事"的卡片，
 *   建议只给按钮挂动作，或让按钮的 `onClick` 与 `onTap` 指向同一个处理函数。
 */

import { CardStyle } from '../common/CardStyle';
import { UiTheme } from '../common/UiTheme';

@ComponentV2
export struct RippleCard {
  /** 点击整卡的回调 · 不传则卡片只播放动画、不产生动作 */
  @Param onTap: () => void = () => {};

  /**
   * 卡片内边距
   * ★ 名字带 `_`：`padding` 是 ArkUI 自定义组件的系统属性方法名，同名成员会编译失败。
   */
  @Param _padding: number = UiTheme.cardPadding;

  /**
   * 是否响应点击（false 时既不播动画也不回调）
   * 用于"不可点的展示卡片"（空态、区块外壳、只读信息卡）。
   *
   * ★ 名字必须带 `_`：`enabled` 是 ArkUI 自定义组件的**系统属性方法名**
   *   （`CommonAttribute.enabled(value: boolean)`），同名成员会报
   *   "Property 'enabled' in type 'RippleCard' is not assignable to the same property
   *    in base type 'CustomComponent'"。本工程约定：与系统属性同名的入参一律加 `_`。
   */
  @Param _enabled: boolean = true;

  /**
   * 是否显示点击涟漪（true 时按下即播，不依赖 `_enabled`）
   *
   * ★ 与 `_enabled` 的分工：`_enabled` 管"要不要触发动作"，
   *   `_clickable` 管"要不要播动画"。
   * ★ 名字不能叫 `clickable`：那同样是 `CommonMethod` 上的系统属性方法名，会编译失败。
   * ★ 区块外壳（如「最近使用的素材」整块）必须传 `_clickable: false`，
   *   否则会抢走内部单条卡片的点击 —— 本轮修掉的一个 bug。
   */
  @Param _clickable: boolean = true;

  /** 卡片圆角 · 默认沿用主题 */
  @Param _radius: number = UiTheme.cardRadius;

  /** 卡片内容（用尾随闭包传入） */
  @BuilderParam content: () => void = this.emptyContent;

  // ────────────────── 涟漪本地状态（纯动画状态，不属于业务数据）──────────────────

  /** 本次涟漪的圆心 X（相对卡片左上角） */
  @Local rippleX: number = 0;

  /** 本次涟漪的圆心 Y */
  @Local rippleY: number = 0;

  /** 圆心到最远角的距离 · 即涟漪圆的半径上限 */
  @Local rippleRadius: number = 0;

  /** 0 → 1 的扩散进度 */
  @Local rippleScale: number = 0;

  /** 1 → 0 的淡出进度 */
  @Local rippleOpacity: number = 0;

  /** 卡片实际尺寸（由 onSizeChange 回填，用于算涟漪半径） */
  @Local cardWidth: number = 0;
  @Local cardHeight: number = 0;

  @Builder
  emptyContent() {
    Row().width('100%').height(0)
  }

  /** 触点 → 启动一次涟漪 */
  private startRipple(x: number, y: number): void {
    this.rippleX = x;
    this.rippleY = y;
    this.rippleRadius = this.diagonalTo(x, y);

    const duration: number = UiTheme.rippleDuration;
    const curve: Curve = Curve.EaseOut;

    // ★ 每次点击都先把圆"瞬间"收回触点、并恢复到满透明度（duration: 0 的 animateTo）。
    //   少了这一步会有一个隐形的 bug：上一轮动画把 opacity 留在了 0，
    //   于是第二次点击的圆是"全透明"的 —— 动画在跑，但用户什么也看不见。
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.rippleScale = 0;
      this.rippleOpacity = 1;
    });

    // 扩散：0 → 1（圆心不动，用 scale 放大）；同时淡出：1 → 0
    this.getUIContext().animateTo({ duration: duration, curve: curve }, () => {
      this.rippleScale = 1;
      this.rippleOpacity = UiTheme.rippleEndOpacity;
    });
  }

  /**
   * 触点 → 卡片最远角的距离
   * ★ 取"最远角"而不是"最近边"：这样圆扩散到 scale = 1 时必定盖满整卡，
   *   不会出现"手指点在角落、涟漪还没铺满就结束"的情况。
   * ★ 尺寸还没测量出来时（首帧）用兜底值，保证至少能画出一个可见的圆。
   */
  private diagonalTo(x: number, y: number): number {
    const w: number = this.cardWidth > 0 ? this.cardWidth : 240;
    const h: number = this.cardHeight > 0 ? this.cardHeight : 120;
    const dx: number = Math.max(x, w - x);
    const dy: number = Math.max(y, h - y);
    const distance: number = Math.sqrt(dx * dx + dy * dy);
    return distance > 0 ? distance : 1;
  }

  /**
   * 涟漪层 · **固定尺寸 + 裁剪**的容器，里面才是圆
   *
   * ★★ 这层容器就是本轮 bug 的修复点（卡片点击后高度翻倍）：
   *   涟漪圆的直径是"2 × 对角线"（约两倍卡宽），如果它直接作为 Stack 的子节点，
   *   **它的尺寸会参与外层 Stack 的测量** —— Stack 的宽高取所有子节点的并集，
   *   于是卡片被圆撑成了一个约 2 倍宽的盒子，高度也跟着翻倍。
   *   把圆放进一个 `width('100%') height('100%')` 且 `clip(true)` 的容器后：
   *     · 容器尺寸完全由卡片决定（100% 而非内容撑开）→ 不再参与"撑大"；
   *     · 圆的溢出部分被容器裁掉（配合 style 的 clip）→ 视觉仍然正常。
   *   这是 ArkUI 布局的一条通用纪律：**要给绝对定位的装饰元素加一层定尺裁剪壳**。
   *
   * ★ 容器 `hitTestBehavior(HitTestMode.None)`：涟漪只是画出来的东西，
   *   绝不能拦住卡片内按钮（如「选择素材」）的点击。
   */
  @Builder
  rippleLayer() {
    Column() {
      if (this.rippleRadius > 0) {
        Circle()
          .width(this.rippleRadius * 2)
          .height(this.rippleRadius * 2)
          // 让圆心正好落在触点上：圆左上角 = 触点 - 半径
          .position({ x: this.rippleX - this.rippleRadius, y: this.rippleY - this.rippleRadius })
          .fill(UiTheme.ripple)
          .scale({ x: this.rippleScale, y: this.rippleScale })
          .opacity(this.rippleOpacity)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    // ★ 外层用 Row 而不是 Stack：Row 的尺寸由"非绝对定位"的子节点（内容层）决定，
    //   绝对定位的涟漪层不会影响它。Stack 会让所有子节点共同决定尺寸，风险更大。
    Row() {
      // ① 涟漪层（定尺 + 裁剪，不参与测量）
      this.rippleLayer()

      // ② 内容层（决定卡片真实高度）
      Column() {
        this.content()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this._padding)
    }
    .width('100%')
    .attributeModifier(CardStyle.modifier)
    .borderRadius(this._radius)
    // 裁剪：涟漪被限制在圆角矩形内，不会糊到卡片外面
    .clip(true)
    .onSizeChange((oldValue: SizeOptions, newValue: SizeOptions) => {
      // 宽高都可能是 string | number，这里只认数字形态，其余忽略（百分比宽度最终也会给出数字）
      const w: number | undefined = newValue.width as number | undefined;
      const h: number | undefined = newValue.height as number | undefined;
      if (typeof w === 'number' && w > 0) {
        this.cardWidth = w;
      }
      if (typeof h === 'number' && h > 0) {
        this.cardHeight = h;
      }
    })
    .onTouch((event: TouchEvent) => {
      if (!this._clickable || event.type !== TouchType.Down) {
        return;
      }
      const touch: TouchObject = event.touches[0];
      if (touch === undefined || touch === null) {
        return;
      }
      this.startRipple(touch.x, touch.y);
    })
    .onClick(() => {
      if (!this._enabled) {
        return;
      }
      this.onTap();
    })
  }
}
