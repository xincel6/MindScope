/**
 * CardStyle · 卡片容器样式的**唯一定义处**（`AppCard` / `RippleCard` 共用）
 *
 * 为什么要有这个文件：卡片外观（白底 + 8vp 圆角 + 低强度投影）此前只写在 `AppCard` 里，
 * 本轮新增带涟漪的 `RippleCard` 后，若各写一份，将来调圆角或投影必然漏改一处。
 *
 * ★ ArkTS 里普通函数**不能**写 `.shadow()` 这类属性方法（属性方法只在 `build()` 的
 *   组件链上合法），所以要复用样式只能走官方的"属性修饰器"机制：
 *
 * ```ts
 * import { CommonModifier } from '@kit.ArkUI';
 * Column() { ... }
 *   .attributeModifier(CardStyle.modifier)     // ← 背景 / 圆角 / 投影一次到位
 * ```
 *
 * ★ 为什么用官方的 `CommonModifier` 而不是自己写一个类：
 *   自己写需要标注 `implements AttributeModifier<CommonAttribute>`，
 *   而这两个名字都是**全局环境声明**（`component/common.d.ts` 的 `declare`），
 *   并非 `@kit.ArkUI` 的导出成员，硬写会踩到"未定义类型"。官方 `CommonModifier`
 *   已经把这件事做完了，直接继承最稳。
 *
 * ★ 圆角之外的要求（如 `RippleCard` 还要 `.clip(true)`）留在调用方：
 *   `clip` 不属于"卡片盒模型"，塞进来会让所有卡片连投影一起被裁掉。
 */

import { CommonModifier } from '@kit.ArkUI';
import { UiTheme } from './UiTheme';

/** 卡片视觉属性 · 白底 + 圆角 + 低强度投影 */
class CardVisual extends CommonModifier {
  private readonly _radius: number;
  private readonly _background: string;

  /**
   * ★ 字段加 `_` 前缀是本工程约定：`radius` / `background` 等名字与
   *   `CommonAttribute` 的属性方法同名时可能触发编译期冲突。
   */
  constructor(radius: number, background: string) {
    super();
    this._radius = radius;
    this._background = background;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    instance.backgroundColor(this._background);
    instance.borderRadius(this._radius);
    instance.shadow({
      radius: UiTheme.cardShadowRadius,
      color: UiTheme.cardShadowColor,
      offsetX: 0,
      offsetY: UiTheme.cardShadowOffsetY
    });
  }
}

/** 卡片样式工具 · 全为静态只读，UI 直接引用 */
export class CardStyle {
  /** 标准卡片视觉（与 `AppCard` 完全一致） */
  public static readonly modifier: CardVisual =
    new CardVisual(UiTheme.cardRadius, UiTheme.cardBackground);
}
