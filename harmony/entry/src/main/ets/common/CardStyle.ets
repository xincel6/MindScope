/**
 * CardStyle · 卡片视觉的**单一取值来源**（`AppCard` / `RippleCard` 共用）
 *
 * ────────────────── 当前视觉：灰底 + 白卡 + 极淡投影 ──────────────────
 * 页面背景 `#F2F3F7`，卡片白底 + 16vp 圆角 + 1px `divider` 描边 + 极淡投影。
 * 投影负责让白卡从灰底上浮起来（淡影的 alpha 写在颜色里，见 `shadow()`），
 * 描边负责兜住卡片与灰底的边界 —— 两层都很淡，少一层卡片就会显得"没收边"。
 *
 * ★ 投影不是删掉而是**开关可控**（`UiTheme.cardShadowEnabled`）：
 *   开关关掉时 `shadow()` 返回全零投影，等价于回到扁平风格，组件代码一行不用改。
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
 * ★ 投影色值是**故意**用 8 位 ARGB 的：`ShadowOptions` 没有 `opacity` 字段，
 *   淡影只能写进颜色自带的 alpha（`#141D2129`，alpha 0x14 ≈ 8%）。
 *   旧注释曾据此判过"8 位色值会让卡片整片不渲染"，但统计页的 `#0E000000` 一直正常出影，
 *   那次白屏的根因是同期被回滚的共享 `AttributeModifier`，不是色值位宽。
 */

import { UiTheme } from './UiTheme';

/** 卡片投影参数 · ArkUI `shadow()` 的入参形状（★ 没有 `opacity`，淡影由 `color` 的 alpha 表达） */
export interface CardShadowOptions {
  radius: number;
  color: string;
  offsetX: number;
  offsetY: number;
}

/** 卡片样式取值 · 全为静态，UI 直接引用 */
export class CardStyle {
  /**
   * 卡片投影参数 · 开关关掉时返回**全零投影**（等价于"没有投影"）
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
        offsetY: 0
      };
      return flat;
    }
    const options: CardShadowOptions = {
      radius: UiTheme.cardShadowRadius,
      color: UiTheme.cardShadowColor,
      offsetX: 0,
      offsetY: UiTheme.cardShadowOffsetY
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
   * 卡片描边色 · 与极淡投影配合：投影给"浮起"，描边给"收边"
   * ★ 用 `divider` 而不是更深的灰：灰底上已经有投影在表达层次，
   *   描边只负责在视觉边缘划一条线，再深就会把卡片框死。
   */
  public static borderColor(): string {
    return UiTheme.divider;
  }
}
