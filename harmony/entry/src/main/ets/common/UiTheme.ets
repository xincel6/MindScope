/**
 * UiTheme · 表现层设计令牌（颜色 / 字号 / 间距 / 圆角）· **全工程唯一的视觉常量来源**
 *
 * 设计规范（本轮 UI 统一风格，逐条对应）：
 *   页面背景 #F4F8FB ｜ 卡片背景 #FFFFFF ｜ 主色 #0D9488 ｜ 辅助蓝 #0284C7
 *   正文 #1E3A5F ｜ 次要文字 #64748B
 *   - 卡片圆角 8vp
 *   - 页面标题 22vp，正文不小于 14vp，重要分数用大字号（32vp）
 *   - 少用大面积渐变（全工程不用渐变）
 *   - 不要同时使用太多颜色：本文件只给 3 个功能色（主色 / 辅助蓝 / 危险色），
 *     其余全部是中性灰阶；危险色**只用于错误提示**，不做装饰。
 *
 * ★ 为什么单独一份而不是改 `types/constant.ts` 的 `UiConstant`：
 *   `UiConstant.primaryColor` 同时被 BDI 严重度分级色系（正常绿 / 轻度蓝 / 中度橙 / 重度红）引用，
 *   属"数据层展示常量"；本轮的设计色板是"页面框架色"，两者语义不同，混在一起会让严重度配色被误改。
 *
 * ★ ArkTS 规则：数字字面量默认单位是 vp，字体类属性（fontSize）默认单位是 fp。
 *   本文件用数字常量，不写字面量单位后缀（写 '22vp' 字符串要再解析，没必要）。
 *   ✔ 已避免的坑：静态字段不得与方法同名、静态字段不得叫 `name`。
 */

/** 表现层设计令牌 · 全为静态只读常量，UI 直接引用 */
export class UiTheme {
  // ────────────────── 颜色 ──────────────────

  /** 页面背景 */
  public static readonly pageBackground: string = '#F4F8FB';

  /** 卡片背景 */
  public static readonly cardBackground: string = '#FFFFFF';

  /** 主色（主按钮 / 选中态 / 主强调） */
  public static readonly primary: string = '#0D9488';

  /** 辅助蓝（次要按钮 / 文字链接 / 信息强调） */
  public static readonly accent: string = '#0284C7';

  /** 正文色 */
  public static readonly textPrimary: string = '#1E3A5F';

  /** 次要文字色（说明、占位符、未选中态） */
  public static readonly textSecondary: string = '#64748B';

  /** 危险色 · **仅用于错误提示** */
  public static readonly danger: string = '#DC2626';

  /** 中性分隔线 */
  public static readonly divider: string = '#E2E8F0';

  /** 浅色填充块（骨架屏、图标底） */
  public static readonly fillSoft: string = '#EDF2F7';

  // ────────────────── 圆角与间距 ──────────────────

  /** 卡片圆角（规范：8vp 左右） */
  public static readonly cardRadius: number = 8;

  /** 主按钮圆角 */
  public static readonly buttonRadius: number = 8;

  /** 品牌图标占位圆角 */
  public static readonly logoRadius: number = 20;

  /** 间距档位 */
  public static readonly gapXs: number = 4;
  public static readonly gapS: number = 8;
  public static readonly gapM: number = 12;
  public static readonly gapL: number = 16;
  public static readonly gapXl: number = 24;
  public static readonly gapXxl: number = 32;

  /** 页面左右安全边距 */
  public static readonly pagePadding: number = 20;

  // ────────────────── 字号（正文不小于 14） ──────────────────

  /** 页面标题 */
  public static readonly fontSizeTitle: number = 22;

  /** 卡片 / 区块标题 */
  public static readonly fontSizeSection: number = 16;

  /** 正文（规范下限） */
  public static readonly fontSizeBody: number = 14;

  /** 辅助说明（仅字段级标注使用，不承载正文信息） */
  public static readonly fontSizeCaption: number = 12;

  /** 重要分数 · 大字号 */
  public static readonly fontSizeMetric: number = 32;

  // ────────────────── 结构尺寸 ──────────────────

  /** 输入框与主按钮统一高度 */
  public static readonly controlHeight: number = 48;

  /** 品牌图标占位边长 */
  public static readonly logoSize: number = 96;

  /** 底部页签栏高度 */
  public static readonly tabBarHeight: number = 56;

  /** 占位页图标底圆直径 */
  public static readonly emptyIconSize: number = 72;

  /** 卡片默认内边距 */
  public static readonly cardPadding: number = 16;

  /** 卡片投影（低强度，符合"少用大面积效果"） */
  public static readonly cardShadowRadius: number = 8;
  public static readonly cardShadowColor: string = '#0F1E3A5F';
  public static readonly cardShadowOffsetY: number = 2;
}
