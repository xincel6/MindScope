/**
 * CardStyle · 卡片视觉的**单一取值来源**（`AppCard` / `RippleCard` 共用）
 *
 * ────────────────── 当前视觉：扁平（无投影）──────────────────
 * 用户明确要求"去掉卡片的 3D 效果"，所以卡片现在**没有投影**，只有
 * 白底 + 8vp 圆角 + 1px `divider` 描边。
 *
 * ★ **描边必须保留**：页面背景已被改为纯白，卡片也是白色。
 *   一旦去掉投影又没有描边，卡片就与页面完全融为一体、看不出边界。
 *   扁平化之后，描边是唯一的层次表达手段。
 *
 * ★ 投影不是删掉而是**开关关掉**（`UiTheme.cardShadowEnabled = false`），
 *   想恢复立体感只需把那个开关置 true，不用改任何组件代码。
 *
 * ────────────────── 为什么这里只放"值"，不提供 AttributeModifier ──────────────────
 * 本文件曾把卡片视觉封装成一个 `AttributeModifier`（`CommonModifier` 子类）的
 * **静态单例**，让所有卡片都 `.attributeModifier(CardStyle.modifier)` 复用。
 * 结果整个工作台的卡片**全部不可见**（页头与底部栏在，卡片区一片空白），
 * 而同一份卡片视觉在改造前是正常渲染的 —— 当时用的是"属性内联写"的写法。
 *
 * 结论（已实测）：**不要用共享的 `AttributeModifier` 实例去描述卡片视觉**。
 * 一个修饰器实例被多个组件同时引用时，ArkUI 的属性生效行为不可靠；
 * 而 `backgroundColor / borderRadius / shadow` 内联写在组件链上，
 * 是 ArkUI 最稳定、也是本工程此前已验证可用的写法。
 *
 * 于是这里只导出"取值"，各卡片自己把属性内联写到组件链上。
 *
 * ★ 另一个被一起修掉的隐形坑：投影色原先写成 8 位 `#0F1E3A5F`（自带 alpha）。
 *   ArkUI `shadow().color` 官方只声明/示例 6 位 `#RRGGBB`，8 位在预览器上
 *   会让整个卡片不渲染。现在改为 6 位色值 + 独立的 `opacity` 字段。
 */

import { UiTheme } from './UiTheme';

/** 卡片投影参数 · ArkUI `shadow()` 的入参形状 */
export interface CardShadowOptions {
  radius: number;
  color: string;
  offsetX: number;
  offsetY: number;
  /** 不透明度 0–1 · 用它表达"淡影"，不要往 color 里塞 alpha（见 UiTheme 注释） */
  opacity: number;
}

/** 卡片样式取值 · 全为静态，UI 直接引用 */
export class CardStyle {
  /**
   * 卡片投影参数 · 扁平模式下返回**全零投影**（等价于"没有投影"）
   *
   * ★ 用"方法返回新对象"而不是"静态常量对象"：属性方法可能按引用比对，
   *   共享同一个对象实例存在被内部改写或跳过更新的风险，返回新对象最稳。
   * ★ 为什么用"零投影"而不是在组件里 `if` 掉 `.shadow()`：
   *   `build()` 的属性链不能按条件拼接，返回零值是最少分支的写法，
   *   仍然是内联一个属性方法，不引入任何布局风险。
   */
  public static shadow(): CardShadowOptions {
    if (!UiTheme.cardShadowEnabled) {
      const flat: CardShadowOptions = {
        radius: 0,
        color: UiTheme.cardShadowColor,
        offsetX: 0,
        offsetY: 0,
        opacity: 0
      };
      return flat;
    }
    const options: CardShadowOptions = {
      radius: UiTheme.cardShadowRadius,
      color: UiTheme.cardShadowColor,
      offsetX: 0,
      offsetY: UiTheme.cardShadowOffsetY,
      opacity: UiTheme.cardShadowOpacity
    };
    return options;
  }

  /** 卡片背景色（取自主题，保证与页面其它地方一致） */
  public static background(): string {
    return UiTheme.cardBackground;
  }

  /** 卡片圆角（取自主题） */
  public static radius(): number {
    return UiTheme.cardRadius;
  }

  /**
   * 卡片描边色 · 扁平化后这是唯一的层次表达手段（原因见文件头）
   * ★ 用 `divider` 而不是更深的灰：扁平风格要克制，描边只负责"划出边界"。
   */
  public static borderColor(): string {
    return UiTheme.divider;
  }
}
