/**
 * CardTransit · 页签切换的**共享节拍器**（只发信号，不搬 UI）
 *
 * ────────────────── 设计思路（按"组件自己管自己"）──────────────────
 * 每个组件（卡片）**在自己的生命周期里**决定怎么动、什么时候动：
 *
 *   · 入场：组件挂载后 `onAppear` 里启动自己的 `animateTo`，
 *     延迟 = `序号 × stepMs` ⇒ 第 0 个先动、第 1 个紧跟着、第 2 个再跟上……
 *   · 离场：监听本模型的 `exitClock`，信号一来各组件按自己的序号延迟启动离场动画。
 *
 * 所以本文件**不参与任何 UI 位移**，它只提供三样东西：
 *   ① 节拍参数（单个组件时长 / 相邻间隔 / 位移距离）
 *   ② 两条曲线（入场带轻微过冲 = 阻尼感；离场「慢—快—慢」加速离开）
 *   ③ 一个"开始离场"的信号 `exitClock` 与方向 `dir`
 *
 * ────────────────── 为什么不用一个全局进度量去算每张卡的位置 ──────────────────
 * 那种做法（`prog` 0→1 再按序号重映射）本质是**在外面把整张卡平移**，
 * 卡片的 UI 本身没有"自己的状态"。改成每个组件持有自己的 `@Local shift/alpha`
 * 之后：组件想改成缩放、变高、换内容都只改自己的代码，页面完全不用动。
 *
 * ────────────────── 关于时长的坑（实测）──────────────────
 * `curves.interpolatingSpring(...)` 的真实时长由曲线自身收敛决定，
 * `animateTo` 里的 `duration` 对它**无效**（把 duration 从 500 改到 2000，速度不变）。
 * 而"一个一个来"必须能精确排出时间表，所以这里用**显式时长的贝塞尔曲线**。
 * 想要纯弹簧手感就换 `curveIn/curveOut` 的实现，代价是时长不可控。
 */

import { curves } from '@kit.ArkUI';

@ObservedV2
export class CardTransit {
  private static shared: CardTransit | null = null;

  /**
   * 取全局实例
   * ★ 组件里必须用 `@Local transit: CardTransit = CardTransit.get();` 持有它，
   *   否则 `@Monitor` / `@Trace` 不会生效（详见 components/RevealCard.ets 注释）。
   */
  static get(): CardTransit {
    if (CardTransit.shared === null) {
      CardTransit.shared = new CardTransit();
    }
    return CardTransit.shared;
  }

  /**
   * 单个组件自己那段动画的时长（毫秒）· **想整体调快调慢，先调这个**
   *
   * ★ 关键关系：`总时长 = cardMs + stepMs × (组件数 - 1)`
   *   所以「让单卡动作更从容」和「让整体不变慢」可以同时做到 ——
   *   **拉长 cardMs、同时让 stepMs 明显小于 cardMs（即加大重叠）** 即可。
   *
   * ★ 速度手感速查（以 4 个组件为例）：
   *   cardMs / stepMs = 170 / 170 → 单相 740ms（严格串行，一顿一顿，显僵硬）
   *   cardMs / stepMs = 120 / 110 → 单相 510ms（上一版：快但每卡 120ms，像"闪一下"）
   *   cardMs / stepMs = 240 / 110 → 单相 570ms（**当前**：单卡 240ms 够稳，重叠 54%，顺滑）
   *   cardMs / stepMs = 260 / 70  → 单相 470ms（重叠 73%，最接近"波浪"，最快）
   *
   * ★ 经验值：`stepMs / cardMs` 落在 **0.4 ~ 0.55** 最顺滑；
   *   接近 1.0 就是严格串行（会有"停顿感"），小于 0.3 会读成"一起动"。
   */
  static readonly cardMs: number = 240;

  /**
   * 相邻两个组件之间的启动间隔（毫秒）
   * ★ 明显小于 `cardMs` ⇒ 相邻组件动作重叠，衔接顺滑（当前 110 / 240 ≈ 46% 重叠）
   */
  static readonly stepMs: number = 110;

  /** 单个组件横向滑动的基准距离（vp）· **入场用**，实际距离还会按序号做拖尾放大，见 `travelOf` */
  static readonly travel: number = 96;

  /** 拖尾系数：序号每 +1，位移距离多这么多比例（0 = 所有组件走同样远，会显得机械）· **入场用** */
  static readonly trail: number = 0.12;

  /**
   * 离场横向位移（vp）· **所有 order 都用这同一个绝对值**，方向由调用方乘上 `dir`
   *
   * ★ 为什么不用 `travelOf(order)`：`travelOf` 是给**入场**用的拖尾递增
   *   （后序组件滑得更远，形成"被带走"的流动感，见其注释）。
   *   离场若也按序号递增，各卡滑走的速度与终点都不同，整页会被横向撕成碎片；
   *   离场要的是"整页像一块板一起滑出视口"，所以距离必须与序号无关。
   * ★ 为什么是 420：真机屏宽约 373vp，小于屏宽的距离都会让卡片"还没走出视口就已经淡没"，
   *   用户看到的只有"内容消失 → 整页空白 → 新页淡入"，根本看不到位移。
   *   取大于屏宽的绝对值，才能保证透明度收在"已经滑出屏幕"之后。
   */
  static readonly exitTravel: number = 420;

  /**
   * 离场缩放终值 · **当前离场已不使用**（`playOut` 里保持 scale = 1，理由见该函数注释）；
   * 这是对外暴露的转场令牌，删除属于契约变更，不在本轮范围内。
   */
  static readonly scaleOut: number = 0.94;

  /** 入场时的缩放起始值 */
  static readonly scaleIn: number = 0.96;

  /** 入场时的纵向起始偏移（vp）· 轻微上浮，避免只有单一横向语言 */
  static readonly riseY: number = 12;

  /**
   * 工作台（主页）：页头 0 / 本次评估 hero 1 / 开始评估 2 / 热力图 3 /
   * 情绪曲线 4 / 严重度分布 5 / 智能解读 6
   * ★ 「最近使用的素材」区块已按用户要求删除，所以最大序号从 7 收敛到 6。
   *   必须与该页里 `RevealCard({ order })` 的**最大序号 + 1** 一致：
   *   3~6 号卡在没有查看目标时不渲染，但 order 固定不变，所以这里始终按 7 算。
   *   少算一个，最后一个组件的动画会被换页切在尾巴上。
   */
  static readonly CARDS_WORKBENCH: number = 7;

  /**
   * 统计页：页头 0 / 核心卡 1 / 三张 KPI 小卡 2·3·4 / 环形图 5 / 折线 6
   * ★ 必须与该页里 `RevealCard({ order })` 的**个数**一致（序号唯一且从 0 连续）：
   *   少算一个，最后一个组件的动画会被换页切在尾巴上。
   */
  static readonly CARDS_STATS: number = 7;

  /**
   * 历史报告页：页头 0 / 筛选栏 1 / 列表区整块 2
   *
   * ★ 列表里的每张报告卡**不计入**这里：它们只播入场（各自按列表下标错峰），
   *   离场由列表区整块承担（卡片 `_playExit: false`）。若把卡片数量算进来，
   *   几十张卡会让等待时间膨胀到几秒，切页签会明显卡住。
   */
  static readonly CARDS_REPORTS: number = 3;

  static readonly CARDS_PLACEHOLDER: number = 2;

  /**
   * 素材库页的**目标**转场位：页头+上传 0 / 筛选+Tab 1（素材网格是滚动内容，不参与转场）
   *
   * ★ 当前页面尚未挂 `RevealCard`，`MainPage.cardCountOf()` 仍走 `CARDS_PLACEHOLDER`（同为 2）；
   *   等页面接入逐块动画后，再把 `cardCountOf()` 改为返回本常量。
   */
  static readonly CARDS_MEDIA: number = 2;

  static readonly CARDS_PROFILE: number = 3;

  /** "开始离场"信号 · 每次切页签自增一次，各组件监听它 */
  @Trace exitClock: number = 0;

  /** 方向：-1 = 向左离场（往右边的页签切），+1 = 向右离场 */
  @Trace dir: number = -1;

  /**
   * 入场曲线 · easeOutExpo（`cubic-bezier(0.16, 1, 0.3, 1)`）
   *
   * ★ 为什么不用带过冲的曲线：过冲（y>1）在 120~240ms 这种短时长里会被读成"抖一下"，
   *   而 easeOutExpo 的减速段极长、落位极稳，是"顺滑"最直接的来源。
   *   想要回弹感就把 y1 调到 >1（如 `(0.16, 1.18, 0.36, 1)`），代价是会显得"弹"。
   */
  static curveIn(): ICurve {
    return curves.cubicBezierCurve(0.16, 1.0, 0.3, 1.0);
  }

  /**
   * 离场曲线 · ease-in（慢起、加速离开）
   * 与入场的"快起慢收"形成反向节奏，来回切换时不会两边都是同一种缓动。
   */
  static curveOut(): ICurve {
    return curves.cubicBezierCurve(0.45, 0.0, 0.8, 0.25);
  }

  /** 透明度曲线 · 平滑且不过冲（透明度过冲会被截断，看起来像闪） */
  static curveFade(): ICurve {
    return curves.cubicBezierCurve(0.4, 0.0, 0.6, 1.0);
  }

  /**
   * 某个序号的组件实际要滑多远（拖尾：越靠后的组件滑得略远）
   *
   * ★ 为什么要有它：所有组件走同样距离时，整组动作像"流水线"；
   *   让后序组件距离递增，视觉上会形成"被带走"的流动感，是去掉机械感的关键一步。
   * ★ **只给入场用**：离场是整页滑出视口，必须等距，走 `exitTravel`。
   *
   * @param order 组件序号
   * @returns vp 距离（恒为正数，方向由调用方乘上 `dir`）
   */
  static travelOf(order: number): number {
    return CardTransit.travel * (1 + CardTransit.trail * order);
  }

  /**
   * 一波转场需要等多久（从发信号到最后一个组件演完）
   *
   * ★ 数值上刚好等于"最后一个组件（`order = count - 1`）真正演完"的时刻 + 40ms 余量：
   *   它的位移从 `(count-1) × stepMs` 起跑、跑满 `cardMs` ⇒ 结束于 `cardMs + stepMs × (count-1)`；
   *   透明度延后 `cardMs × 0.62` 起、跑 `cardMs × 0.38` ⇒ 同样结束于那一刻。
   *   所以末尾的 +40 是**纯余量**而不是补偿，页面按它等，换页正好落在最后一张卡滑出屏幕之后。
   *
   * @param count 该页组件个数
   * @returns 毫秒；含 40ms 余量，避免换页切在动画尾巴上
   */
  static sequenceMs(count: number): number {
    const n: number = count < 1 ? 1 : count;
    return CardTransit.cardMs + CardTransit.stepMs * (n - 1) + 40;
  }
}
