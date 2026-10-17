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
   * 危险提示的**浅底**（本轮新增 · 登录失败弹窗底色）
   * ★ 与 `danger` 的分工：`danger` 是文字/描边的前景色，它是"一条淡红底"，
   *   用来让弹窗在一屏白底上被认出"这是警告"，但不刺眼。
   */
  public static readonly dangerSoft: string = '#FEF2F2';

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

  /** 重要分数 · 大字号（分析详情页的 hero 分数） */
  public static readonly fontSizeMetric: number = 32;

  /**
   * 卡片内的关键数值（工作台「当前任务」的 BDI 分数）
   * ★ 卡片里还要放首帧照片和进度条，直接上 32 会把卡片撑高，取 24 作中间档。
   */
  public static readonly fontSizeCardMetric: number = 24;

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
   *
   * ★★ `cardShadowEnabled` 是**投影总开关**，当前为 false（扁平风格）。
   *   用户明确要求"去掉卡片的 3D 效果"。下面的半径/色值/位移/透明度全部保留，
   *   需要恢复立体感时把开关置 true 即可 —— 不要删这些令牌。
   */
  public static readonly cardShadowEnabled: boolean = false;

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

  /**
   * 工作台「当前任务」卡片里**首帧照片**的边长
   * ★ 比列表缩略图大一点：它是这张卡片里唯一的图像，太小就认不出人脸。
   */
  public static readonly taskThumbSize: number = 64;

  /** 点击涟漪动画时长（毫秒）· 保留令牌（手绘涟漪已撤回，见 BUG清单 BUG-01） */
  public static readonly rippleDuration: number = 300;

  /** 涟漪终止透明度（涟漪色自带 alpha，这里只做"扩散即淡出"的收尾） */
  public static readonly rippleEndOpacity: number = 0;

  /** 卡片按压反馈的过渡时长（毫秒）· 比涟漪更短，手感才"跟手" */
  public static readonly pressDuration: number = 120;

  // ────────────────── 开屏页（本轮新增）──────────────────

  /**
   * 开屏页图标边长
   * ★ 比登录页的 96 大一号：开屏时屏幕上只有这一个元素，太小会显得"页面没加载完"。
   */
  public static readonly splashLogoSize: number = 112;

  /** 开屏页图标圆角 · 与边长同比放大（96→20 的比例） */
  public static readonly splashLogoRadius: number = 24;

  /** 开屏页产品名 "MindScope" 字号 */
  public static readonly fontSizeSplashTitle: number = 30;

  /**
   * 开屏页最短展示时长（毫秒）
   * ★ 为什么需要：引导流程在缓存命中时可能 200ms 就结束，
   *   不留一个下限的话开屏页只会闪一下（比不显示更难看）。
   */
  public static readonly splashMinDurationMs: number = 1100;

  // ────────────────── 失败弹窗（本轮新增）──────────────────

  /** 弹窗右侧圆角 · 左侧贴屏幕边缘所以是直角（0），见 `AuthAlert` */
  public static readonly alertRadius: number = 10;

  /** 弹窗左侧"撞击条"宽度（危险色竖条） */
  public static readonly alertAccentWidth: number = 4;

  /** 弹窗距页面顶部的距离 · 让它落在输入框之上、又不贴死状态栏 */
  public static readonly alertOffsetTop: number = 8;
}
