/**
 * UiTheme · 表现层设计令牌（颜色 / 字号 / 间距 / 圆角）· **全工程唯一的视觉常量来源**
 *
 * 设计规范（本轮 UI 统一风格，逐条对应）：
 *   页面背景 #F2F3F7 ｜ 卡片背景 #FFFFFF ｜ 主色 #0D9488 ｜ 辅助蓝 #0284C7
 *   正文 #1D2129 ｜ 次要文字 #4E5969
 *   - 卡片圆角 16vp
 *   - 页面标题 22vp，正文不小于 14vp，重要分数用大字号（32vp）
 *   - 少用大面积渐变（全局令牌里不放渐变；统计页核心卡那条浅薄荷渐变是唯一例外）
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
 * ★ 层次靠三件套（用户本轮指定，已从统计页提升为全局）：**浅灰页底 + 纯白卡片 + 极淡投影**。
 *   投影负责让白卡从灰底上浮起来，但卡片内部"再嵌一层"的元素（输入框、缩略图底、进度条轨道）
 *   没有投影可用，一律用 `fillSoft` / `divider` 描边或填底 —— 白底白块仍然看不出来。
 *   ★ 所以 `fillSoft` 必须与 `pageBackground` **明显可区分**：页底已经比纯白深一档，
 *     两者靠得太近，灰底上的浅填充就会"消失"。
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

  /** 页面背景 · 浅灰（白卡片要浮得起来，页底就不能也是白的） */
  public static readonly pageBackground: string = '#F2F3F7';

  /** 卡片背景 */
  public static readonly cardBackground: string = '#FFFFFF';

  /** 主色（主按钮 / 选中态 / 主强调） */
  public static readonly primary: string = '#0D9488';

  /** 辅助蓝（次要按钮 / 文字链接 / 信息强调） */
  public static readonly accent: string = '#0284C7';

  /** 正文色 · 中性深灰（原深蓝灰在灰底上偏冷，中性黑对比度更高也更干净） */
  public static readonly textPrimary: string = '#1D2129';

  /** 次要文字色（说明、占位符、未选中态） */
  public static readonly textSecondary: string = '#4E5969';

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
  public static readonly divider: string = '#E5E6EB';

  /** 浅色填充块（输入框底 / 缩略图底 / 进度条轨道）· 必须与 `pageBackground` 明显可区分 */
  public static readonly fillSoft: string = '#E9EDF3';

  /**
   * 骨架块与空态图标底的填充 · 比 `fillSoft` 再深一档
   *
   * ★ 为什么不复用 `fillSoft`：`fillSoft`(#E9EDF3) 与页底 `pageBackground`(#F2F3F7)
   *   的对比度只有约 1.06:1 —— 而骨架块/空态图标底是**直接坐在页底上**的（不像缩略图
   *   那样嵌在白卡里），复用 `fillSoft` 会让加载态看起来就是一页空白（基座实测已复现）。
   *   这一档在灰页底上辨得出来，又仍浅于白卡，被放进卡片里也不会变成深色补丁。
   */
  public static readonly skeletonFill: string = '#DCE3EC';

  // ────────────────── 圆角与间距 ──────────────────

  /** 卡片圆角（16vp · 与统计页一致，大圆角让白卡更"软"） */
  public static readonly cardRadius: number = 16;

  /** 主按钮圆角（12vp · 只比卡片小一号，按钮不应看着像卡片） */
  public static readonly buttonRadius: number = 12;

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

  /** 重要分数 · 大字号（工作台分析区 hero 的分数） */
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

  /**
   * 底部页签栏高度
   *
   * ★ 从 56 提到 64：本轮页签从"纯文字"改成"图标在上、文字在下"，
   *   竖直方向要装下 胶囊 28 + 间距 4 + 14fp 行高约 20 = 52；56 只剩 2vp 余量，
   *   文字换行或字重一变就会顶到栏边。
   */
  public static readonly tabBarHeight: number = 64;

  /** 底部页签图标边长 · 24 网格的图标缩到 22，与 14fp 标签并排后一栏仍是标准高度 */
  public static readonly tabIconSize: number = 22;

  /**
   * 选中态"图标胶囊"的宽 / 高（Material 3 导航栏写法：底色只罩图标，不罩文字）
   * ★ 56×28 对 22×22 的图标：四周留出内边距，底色块才不像"把图标贴了张色纸"。
   * ★ 圆角取高度一半即胶囊形（与进度条同一套取法）。
   */
  public static readonly tabIconPillWidth: number = 56;
  public static readonly tabIconPillHeight: number = 28;

  /** 占位页图标底圆直径 */
  public static readonly emptyIconSize: number = 72;

  /** 卡片默认内边距 */
  public static readonly cardPadding: number = 16;

  /**
   * 卡片投影（极淡 · 只负责让白卡从灰底上"浮"起来）
   *
   * ★ 淡影做进**颜色**里，不靠 opacity：ArkUI 的 `ShadowOptions` 根本没有 `opacity` 字段，
   *   过去那个 `cardShadowOpacity` 一直被运行时忽略 —— 开关一开就是满强度黑影。
   *   现在用 8 位 ARGB `#141D2129`（alpha 0x14 ≈ 8%）。
   *
   * ★ 旧注释记过"8 位色值会让卡片整片不渲染"，但统计页的 `statsShadowColor`（`#0E000000`）
   *   就是 8 位 ARGB 且投影正常，可见那次白屏的根因不在此（同期被回滚的共享
   *   `AttributeModifier` 才是，见 `CardStyle.ets` 顶部）。本轮据此改用 8 位 ARGB。
   *
   * ★★ `cardShadowEnabled` 是**投影总开关**，当前为 true。
   *   想一键回到扁平风格就置 false（`CardStyle.shadow()` 返回全零投影），
   *   不要删下面的半径/色值/位移令牌。
   */
  public static readonly cardShadowEnabled: boolean = true;

  public static readonly cardShadowRadius: number = 14;
  public static readonly cardShadowColor: string = '#141D2129';
  public static readonly cardShadowOffsetY: number = 3;

  // ────────────────── 工作台专用尺寸 ──────────────────

  /** 进度条高度（严重度条 / 分析进度条共用） */
  public static readonly progressHeight: number = 8;

  /** 进度条圆角 · 取高度的一半，呈胶囊形 */
  public static readonly progressRadius: number = 4;

  /** 进度条轨道底色 · 与 `fillSoft` 同值（同一张卡里不能出现两种浅填充） */
  public static readonly progressTrack: string = '#E9EDF3';

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

  // ────────────────── 品牌 / 待机页 / 登录页（2026-10-21 待机页与登录页重构）──────────────────

  /**
   * 品牌标记的宽高比（`media/brand_mark.png` 原图 885 x 727 ≈ 1.217）
   * ★ 只给宽度、高度用 `aspectRatio` 推：换 logo 时不必同时改两处数字，
   *   父容器再窄也不会把标记压扁。
   */
  public static readonly brandMarkAspect: number = 1.217;

  /**
   * 品牌底色（直接从应用图标本身取色）
   * ★ 待机页整屏就是这层竖向渐变：标记图是从图标里抠出来的白色部分，
   *   把它铺回同色底，屏幕上看到的就是启动图标本身 —— 这是"图标即品牌"的那一步。
   */
  public static readonly brandStart: string = '#22B49C';
  public static readonly brandEnd: string = '#0C7A69';

  /** 品牌色上的文字与次级元素 */
  public static readonly onBrand: string = '#FFFFFF';
  public static readonly onBrandMuted: string = '#CCF2EA';
  public static readonly onBrandLine: string = '#33FFFFFF';

  /**
   * 品牌区（图标 + "MindScope" + 产品名）
   * ★★ 待机页与登录页**必须共用这一组数字**：转场时图标是从待机页原位
   *    "长"成登录页那一份的，任何一边差 1vp，用户就能看见图标跳一下。
   */
  public static readonly heroLogoWidth: number = 152;
  public static readonly heroTitleSize: number = 26;
  public static readonly heroProductSize: number = 14;
  /** 品牌区顶边（待机页固定在这里；登录页从同一个位置起、入场末尾再上提） */
  public static readonly heroTop: number = 156;
  /**
   * 品牌区"上提"后的顶边（登录页入场最后一拍的终点）
   *
   * ★ 用户要求：「动画的最后让白屏向上拉动，让图标上移」。位移量 = 156 - 96 = 60vp，
   *   与白层上提量一致 —— 品牌区与白层**整体上移**，两者之间的间距保持不变，
   *   所以看起来是"整页被往上提了一格"，而不是间距被压扁。
   */
  public static readonly heroTopLifted: number = 96;
  /**
   * 待机页图标的起始比例：登录页 = 1（`heroLogoWidth` = 152 的实尺寸），
   * 待机页 = 0.84（约 128）
   *
   * ★ 用户要的"图标慢慢放大直到与登录页相同"就落在这一个数字上：待机页显示 0.84，
   *   切页前由 `Index.releaseStandby` 在**待机页上**先放大到 1，随后白层才盖上来。
   * ★ 两页共用同一个**布局盒**（`heroLogoWidth`），只缩画出来的图形 ——
   *   这样图标是"就地长大"，下面的 MindScope/产品名纹丝不动，转场看不出接缝。
   * ★ 0.84 而不是更小的值：待机页单独停留时图标要**够大**（实测 0.76 时用户反馈太小）。
   */
  public static readonly heroLogoStart: number = 0.84;
  /** 图标放大 + 白层上滑的总时长 */
  public static readonly heroEnterMs: number = 520;

  /** 待机页底部状态行（"正在准备…"） */
  public static readonly standbyStatusSize: number = 14;
  public static readonly standbyStatusBottom: number = 104;

  /**
   * 待机页最短展示时长（毫秒）
   * ★ 缓存命中时引导 200ms 就结束了，不留一个下限的话待机页只会闪一下（比不显示更难看）。
   */
  public static readonly standbyMinDurationMs: number = 700;

  /** 登录页白色表单层的顶边 · 落在品牌区下方（品牌区底边约 340） */
  public static readonly loginSheetTop: number = 372;
  /**
   * 白层"上提"后的顶边（登录页入场最后一拍的终点）
   *
   * ★ 与 `heroTopLifted` 同位移（372 → 312，也是 60vp）：白层顶边往上走 60vp，
   *   表单区就凭空多出 60vp —— 原来"对半分"的观感被打破，白层占到屏幕约 2/3。
   * ★ 注意：这里改的是**白层在布局里的顶边**（占位 `Row` 的高度），不是 translate。
   *   用 translate 的话底边会跟着抬起、露出 60vp 的青绿。
   */
  public static readonly loginSheetTopLifted: number = 312;
  /** 白层顶部圆角 · 比卡片的 16 更大，才像"从下面盖上来的抽屉" */
  public static readonly loginSheetRadius: number = 28;
  /** 登录页标题字号 */
  public static readonly loginTitleSize: number = 24;
  /** 白层上滑入场的时长 */
  public static readonly sheetEnterMs: number = 460;
  /** 入场末尾"整页上提"的时长 · 比上滑短一档，收尾要干净 */
  public static readonly sheetLiftMs: number = 420;

  // ────────────────── 失败弹窗（本轮新增）──────────────────

  /** 弹窗右侧圆角 · 左侧贴屏幕边缘所以是直角（0），见 `AuthAlert` */
  public static readonly alertRadius: number = 10;

  /** 弹窗左侧"撞击条"宽度（危险色竖条） */
  public static readonly alertAccentWidth: number = 4;

  /** 弹窗距页面顶部的距离 · 让它落在输入框之上、又不贴死状态栏 */
  public static readonly alertOffsetTop: number = 8;
  // ────────────────── 统计页专用（2026-10-17 · 仅本页消费，不改动上方任何全局值） ──────────────────

  /**
   * 统计页图表色板（回归 UI 统一风格后的中性化版本）
   *
   * ★ 语义顺序固定：正常 / 轻度 / 中度 / 重度，由 StatsMapper 保证，
   *   本数组只负责"画出来"，与数据层 `UiConstant.severityMeta()` 的取值互不替代。
   * ★ 取值在原有色相上略降饱和，避免四个高饱和色并排把页面拉成仪表盘。
   */
  public static readonly severityPieColors: string[] = ['#17B26A', '#2E6BE6', '#F79009', '#F04438'];

  /** 折线阈值线色板（index 与 19 / 28 一一对应） */
  public static readonly chartThresholdColors: string[] = ['#2E6BE6', '#F79009'];

  /** 统计页强调色（折线 / 核心数字）· 与主色同族的绿，用于"数据"而非"交互" */
  public static readonly statAccent: string = '#17B26A';

  /** 图例标签色 */
  public static readonly legendLabelColor: string = '#4E5969';

  /** 图表横向网格线 */
  public static readonly chartGrid: string = '#E5E6EB';

  /** 折线下方渐变面积 · 顶 / 底（rgba 形式，mpchart 需要 #AARRGGBB） */
  public static readonly chartLineFillTop: string = '#2617B26A';
  public static readonly chartLineFillBottom: string = '#0017B26A';

  /** 核心指标卡浅底（不用渐变，纯色浅底 + 描边表达层级） */
  public static readonly kpiHeroTint: string = '#F0FDF9';
  public static readonly kpiHeroBorder: string = '#CCFBF1';

  /** 统计页左右内边距 */
  public static readonly statsPagePadding: number = 16;

  /** 坐标轴刻度 / 环心副文字 / 小单位（11） */
  public static readonly fontSizeAxis: number = 11;

  /** 环心核心数字（28 / 700） */
  public static readonly fontSizeChartCenter: number = 28;

  /** 数字后缀单位（次 / ms · 13） */
  public static readonly fontSizeUnit: number = 13;

  /** 小卡数字后缀单位（10 · 三卡并排时防挤压） */
  public static readonly fontSizeUnitSmall: number = 10;

  /** 环形图：外径 152（半径 76）/ 环宽 16 / 内径 60 */
  public static readonly pieOuterRadius: number = 76;
  public static readonly pieRingWidth: number = 16;
  public static readonly pieInnerRadius: number = 60;

  /** 环形图绘制高度 = 152 + mpchart 内部固定扣减 36（见 SeverityPieChart 注释） */
  public static readonly pieHeight: number = 188;

  /** 扇区间隙 */
  public static readonly pieSliceSpace: number = 3;

  /** 图例色块 10×10 / 圆角 3 / 单项定宽 132 */
  public static readonly legendDotSize: number = 10;
  public static readonly legendDotRadius: number = 3;
  public static readonly legendItemWidth: number = 132;

  /** 折线：线宽 2.5 / 数据点半径 4 / 白心半径 2 / 绘制高度 232 */
  public static readonly lineWidth: number = 2.5;
  public static readonly linePointRadius: number = 4;
  public static readonly linePointHoleRadius: number = 2;
  public static readonly lineHeight: number = 232;

  /** 横向网格虚线节奏 */
  public static readonly chartGridDashLength: number = 4;
  public static readonly chartGridDashSpace: number = 4;

  /** KPI 大卡 / 小卡高度与内边距 */
  public static readonly kpiHeroHeight: number = 106;
  public static readonly kpiSmallHeight: number = 78;
  public static readonly kpiSmallPadding: number = 12;

  // ── 统计页专用（图表 / 版式取值 · 已不是一套"独立视觉体系"）──
  //
  // 统计页原来的"浅灰底 + 16 圆角 + 极淡投影 + 白卡"现已**提升为全局风格**
  // （见文件上方的 pageBackground / cardRadius / cardShadow*），所以本区块里的背景、
  // 圆角、投影半径与外层同值，属过渡期重复，待各页接入完成后收敛。
  // 仍然只属于本页的是：图表色板、字号、饼图 / 折线 / 图例 / 卡高这些版式尺寸，
  // 以及核心卡那条浅薄荷渐变（全局不放渐变，本页是唯一例外）。

  /** 统计页页面背景（比全局纯白深一档，让白卡片浮起来） */
  public static readonly statsPageBg: string = '#F2F3F7';

  /** 统计页卡片圆角（16 · 大于全局 8） */
  public static readonly statsCardRadius: number = 16;

  /** 统计页页头标题字号（26 · 大于全局 22，拉开层级） */
  public static readonly statsTitleSize: number = 26;

  /** 统计页一级 / 二级文字色（中性灰阶，比全局的深蓝灰更"数据化"） */
  public static readonly statsTextPrimary: string = '#1D2129';
  public static readonly statsTextRegular: string = '#4E5969';

  /** 统计页卡片投影（大扩散低透明度 · 只在统计页卡片上手动挂） */
  public static readonly statsShadowRadius: number = 14;
  public static readonly statsShadowColor: string = '#0E000000';
  public static readonly statsShadowOffsetY: number = 3;

  /** 统计页核心卡渐变（浅薄荷 → 白 · 135°） */
  public static readonly kpiGradientStart: string = '#E8F6EF';
  public static readonly kpiGradientEnd: string = '#FFFFFF';
}
