/**
 * CardStyle · 卡片视觉的**单一取值来源**（`AppCard` / `RippleCard` 共用）
 *
 * ────────────────── 为什么这里只放"值"，不提供 AttributeModifier ──────────────────
 * 本文件最初把卡片视觉封装成一个 `AttributeModifier`（`CommonModifier` 子类）的
 * **静态单例**，让所有卡片都 `.attributeModifier(CardStyle.modifier)` 复用。
 * 结果在预览器上整个工作台的卡片**全部不可见**（页头与底部栏在，卡片区一片空白），
 * 而同一份卡片视觉在改造前是正常渲染的 —— 当时用的是"三个属性内联写"的写法。
 *
 * 结论（已实测）：**不要用共享的 `AttributeModifier` 实例去描述卡片视觉**。
 * 一个修饰器实例被多个组件同时引用时，ArkUI 的属性生效行为不可靠；
 * 而 `backgroundColor / borderRadius / shadow` 这三个属性内联写在组件链上，
 * 是 ArkUI 最稳定、也是本工程此前已验证可用的写法。
 *
 * 于是这里退化成"只导出取值"：
 *   - `cardShadow()` 返回 shadow 的入参对象（避免两个组件各写一份数字）；
 *   - 圆角与背景仍从 `UiTheme` 取；
 *   - 各卡片自己把三项内联写到组件链上。
 *
 * ★ 另一个被一起修掉的隐形坑：投影色原先写成 8 位 `#0F1E3A5F`（自带 alpha）。
 *   ArkUI `shadow().color` 官方只声明/示例 6 位 `#RRGGBB`，8 位在预览器上
 *   会让整个卡片不渲染。现在改为 6 位色值 + 独立的 `opacity` 字段。
 *
 * ★ 保留这个文件的意义：卡片视觉的**取值**依然只有一处。
 *   改圆角/投影只需要改 `UiTheme`，不存在"两边数字漂移"的风险。
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
   * 卡片投影参数
   * ★ 用"方法返回新对象"而不是"静态常量对象"：`@Param` / 属性方法可能按引用比对，
   *   共享同一个对象实例存在被内部改写或跳过更新的风险，返回新对象最稳。
   */
  public static shadow(): CardShadowOptions {
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
}
