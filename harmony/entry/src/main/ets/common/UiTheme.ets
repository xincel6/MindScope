/**
 * UiTheme · 表现层设计令牌（颜色 / 字号 / 间距 / 圆角）· **全工程唯一的视觉常量来源**
 *
 * 设计规范（本轮 UI 统一风格，逐条对应）：
 *   页面背景 #FFFFFF ｜ 卡片背景 #FFFFFF ｜ 主色 #0D9488 ｜ 辅助蓝 #0284C7
 *   正文 #1E3A5F ｜ 次要文字 #64748B
 *   - 卡片圆角 8vp
 *   - 页面标题 22vp，正文不小于 14vp，重要分数用大字号（32vp）
 *   - 少用大面积渐变（全工程不用渐变）
 *   - 不要同时使用太多颜色：本文件只给 3 个功能色（主色 / 辅助蓝 / 错误危险色），
 *     其余全部是中性灰阶。
 *
 * ★★ 两套"红"必须分清（本轮工作台新增，此前注释把两者混为一谈）：
 *   ① `danger`（#DC2626）—— **错误危险色**。只用于失败提示（网络失败、鉴权失败）。
 *   ② 严重度色阶 `#16a34a / #0284c7 / #d97706 / #dc2626` —— **数据表达色**。
 *      定义在 `types/constant.ts` 的 `UiConstant.severityMeta()`，按 BDI 四档取色，
 *      属于"把数据画出来"的一部分，可以大面积出现在进度条、图例、图表上。
 *   两者**语义不同**：一个是"出错了"，一个是"病情到这个档位了"，数值相同也不得互换引用。
 *   （工作台的严重度进度条用 ②，不要图省事去 import ①。）
 *
 * ★ 背景改纯白（用户本轮指定）：纯白背景下卡片与页面同色，层次**只能靠阴影和浅灰填充**区分，
 *   因此凡是要在卡片里"再嵌一层"的元素（输入框、缩略图底、进度条轨道），
 *   一律用 `fillSoft` / `divider` 描边或填底，不能只靠背景色差。
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

  /** 页面背景 · 用户本轮指定改为纯白 */
  public static readonly pageBackground: string = '#FFFFFF';

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

  /** 错误危险色 · **仅用于失败提示**（严重度色阶在 `UiConstant.severityMeta()`，两者勿混用） */
  public static readonly danger: string = '#DC2626';

  /**
   * 卡片点击涟漪色 · 主色 12% 透明度（ARGB：前两位是 alpha）
   * ★ 纯白背景下必须带透明度，否则涟漪会变成一块实心绿，看着像卡片被选中了。
   * ★ 当前仅作为**保留令牌**：手绘涟漪的方案已撤回（见 `BUG清单.md` BUG-01），
   *   按压反馈改用 ArkUI 原生 `clickEffect` + `cardPressTint`。
   */
  public static readonly ripple: string = '#1F0D9488';

  /**
   * 卡片**按下**时的底色 · 极淡的主色
   * ★ 与 `ripple` 的区别：这是整卡换底色（颜色属性，不影响布局），
   *   配合原生 `clickEffect` 一起表达"按下了"。
   */
  public static readonly cardPressTint: string = '#F2F8F7';

  /** 服务状态灯 · 已连接 */
  public static readonly statusOnline: string = '#16a34a';

  /** 服务状态灯 · 未连接（与严重度"重度"同色值，但语义是连接状态，不要互相引用） */
  public static readonly statusOffline: string = '#DC2626';


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

  /**
   * 卡片投影（低强度，符合"少用大面积效果"）
   *
   * ★ 色值必须是**6 位 `#RRGGBB`**：ArkUI `shadow()` 的 `color` 官方类型是 `ResourceColor`，
   *   文档示例都是 6 位；原先写 8 位（`#0F1E3A5F`，带 alpha）在预览器上会让卡片整片不渲染
   *   —— 属于"编译通过、运行白屏"的隐形坑。要弱化投影请调低 `cardShadowOpacity`，
   *   不要往色值里塞 alpha。
   */
  public static readonly cardShadowRadius: number = 10;
  public static readonly cardShadowColor: string = '#1E3A5F';
  public static readonly cardShadowOffsetY: number = 2;

  /** 卡片投影的不透明度（0–1）· 与 `cardShadowColor` 配合表达"很淡的一层影" */
  public static readonly cardShadowOpacity: number = 0.12;

  // ────────────────── 工作台专用尺寸 ──────────────────

  /** 进度条高度（严重度条 / 分析进度条共用） */
  public static readonly progressHeight: number = 8;

  /** 进度条圆角 · 取高度的一半，呈胶囊形 */
  public static readonly progressRadius: number = 4;

  /** 进度条轨道底色 */
  public static readonly progressTrack: string = '#EDF2F7';

  /** 最近素材缩略图边长 */
  public static readonly thumbSize: number = 56;

  /** 点击涟漪动画时长（毫秒）· 保留令牌（手绘涟漪已撤回，见 BUG清单 BUG-01） */
  public static readonly rippleDuration: number = 300;

  /** 涟漪终止透明度（涟漪色自带 alpha，这里只做"扩散即淡出"的收尾） */
  public static readonly rippleEndOpacity: number = 0;

  /** 卡片按压反馈的过渡时长（毫秒）· 比涟漪更短，手感才"跟手" */
  public static readonly pressDuration: number = 120;
}
