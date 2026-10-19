/**
 * RevealCard · 让**每个组件自己**按生命周期做「依次滑入 / 滑出」的转场
 *
 * ────────────────── 为什么要有这一层 ──────────────────
 * 由页面统一给每张卡套 `.translate()`（全局进度量重映射）的做法，本质是"在外面把整张卡平移"，
 * 卡片的 UI 本身没有自己的状态 —— 想改缩放、改高度、换内容都得回到页面里改，做不到"个性化"。
 *
 * 这个组件把动画**收进组件内部**：
 *   · `onAppear`  —— 挂载完成 → 启动自己的入场动画，延迟 = `order × stepMs`
 *   · `@Monitor('transit.exitClock')` —— 收到"开始离场"信号 → 启动自己的离场动画
 *   · 位移 / 上浮 / 缩放 / 透明度都是本组件自己的 `@Local`，页面完全不参与
 *
 * ────────────────── 去"僵硬"的四个关键设计（每一处都对应一个观感问题）──────────────────
 *   ① **入场分两条时间轴**：位移+缩放走 `cardMs`，透明度单独走 `cardMs × 0.7` 且略晚起步。
 *      合成一条的话"位移到位"和"完全透明"同时发生，观感像贴纸被推走；
 *      分开之后是"边滑边化"，层次自然。
 *   ② **入场拖尾**：位移距离按 `order` 递增（`CardTransit.travelOf`），后面的组件甩得更远，
 *      形成被"带走"的流动感；所有组件等距是最容易显机械的做法。
 *      —— 这条**只对入场成立**：离场要的是"整页滑出"，距离必须等距，见 `playOut`。
 *   ③ **纵深只在入场做**：入场 `scale 0.96 → 1` 且带 12vp 上浮；
 *      离场保持 `scale = 1` —— 整页平移时再叠缩放会读成"缩一下再飞走"。
 *      只有 X 轴平移会显得很平。
 *   ④ **曲线不做过冲**：入场用 easeOutExpo（`(0.16, 1, 0.3, 1)`），落位稳；
 *      过冲在 200ms 级的短时长里会被读成"抖一下"。
 *   ⑤ 相邻组件**重叠**（`stepMs / cardMs ≈ 0.46`）：仍有先后，但没有"一张张蹦"的停顿感。
 *
 * ────────────────── 为什么入场不能写在 `aboutToAppear` ──────────────────
 * `aboutToAppear` 在**首次 build 之前**执行，节点还没挂载，`animateTo` 改属性没有可动的东西。
 * 所以起始态在 `aboutToAppear` 里设（首帧就是"还没进来"的样子），动画在 `onAppear` 里启动。
 *
 * ────────────────── 为什么离场不能写在 `aboutToDisAppear` ──────────────────
 * `aboutToDisAppear` 触发时节点**已经在销毁流程里**，动画没有播放窗口。
 * 所以离场必须由页面**提前**发信号（`CardTransit.exitClock`），
 * 各组件收到信号后自己播完，页面再等 `CardTransit.sequenceMs(n)` 之后才真正换页。
 *
 * ────────────────── 列表类页面为什么需要 `_playEnter` / `_playExit` ──────────────────
 * 一级页签页面里的「固定块」（页头、筛选栏、统计卡）天然可以整块参与入场 + 离场；
 * 但**动态列表**不行：
 *   · 列表容器（骨架 / 空态 / 卡片列表都在里面）如果也播入场，会先整体滑一次，
 *     里面的每张卡片再各自错峰滑一次 → 两层位移与透明度叠加，观感是"抖一下再变淡"。
 *     所以容器 `_playEnter: false`，以终态出现，错峰完全交给卡片自己。
 *   · 列表里的卡如果也跟随 `exitClock` 逐张离场，几十张卡的启动时间会排到几秒之后，
 *     而窗口层只等 `sequenceMs(该页离场块数)` 就换页 —— 绝大多数卡还没动就被销毁。
 *     所以卡片 `_playExit: false`，离场由外层列表容器整块滑出（与"整页同速滑出"的既有设计一致）。
 *
 * ★ `@BuilderParam content` 必须给默认实现，否则不传尾随闭包时编译失败（同 AppCard）。
 */

import { CardTransit } from '../common/CardTransit';

@ComponentV2
export struct RevealCard {
  /**
   * 本组件在本页转场里的出场顺序（0 起，必须唯一且连续）
   *
   * ★ **条件块可以取小数**：例如工作台的离线横幅只在下线时出现，位置夹在页头(0)
   *   与 hero(1) 之间。若给它整数 1，就得把后面所有卡整体 +1，在线时还会凭空多等
   *   一个 `stepMs`（切页签的离场等待也会被 `CARDS_*` 一起拉长）。取 0.5 只让它自己
   *   在 `0.5 × stepMs` 处错峰，其余卡的节拍与常量都不动；小数位同样必须唯一。
   */
  @Param order: number = 0;

  /**
   * 主轴权重 · 0 = 不参与均分（默认，等价于加这一层之前的行为）
   *
   * ★ 为什么必须有它：页面里"几张等宽小卡靠 `.layoutWeight(1)` 均分"的那一排，
   *   一包上 `RevealCard` 就会破掉均分 —— 因为动画卡的外层 `Column` 没有权重，
   *   于是那一排只能裸着放，也就永远拿不到入场动画。把权重透传到外层 Column，
   *   页面才能在 `Row` 里写 `RevealCard({ order: 2, _weight: 1 })` 既保住均分又有动画。
   * ★ `layoutWeight` 只在**主轴**方向有意义，所以只在 `Row` 里传 `_weight`；
   *   纵向堆叠里传了不会出错，但也不会有效果。
   * ★ 名字带 `_`：本工程约定，与系统属性方法可能重名的入参一律加前缀。
   */
  @Param _weight: number = 0;

  /**
   * 是否播放**入场**动画 · 默认 true（等价于加这两个参数之前的行为）
   *
   * ★ 谁需要传 false：**动态列表的外层容器**。它只负责离场（整块滑出），
   *   入场交给里面每张卡片自己错峰；若容器也播入场，会和卡片的动画叠成两层。
   * ★ 传 false 时字段初始化为终态（位移 0 / 缩放 1 / 不透明 1），首帧就是"已在位"。
   */
  @Param _playEnter: boolean = true;

  /**
   * 是否跟随页面的「开始离场」信号 · 默认 true
   *
   * ★ 谁需要传 false：**动态列表里的每一张卡**（历史报告卡、素材卡）。
   *   它们只在入场时按列表下标错峰；离场若也逐张延迟，启动时间会排到几秒后，
   *   窗口层的等待只有 `sequenceMs(卡片块数)`，来不及演完就换页，反而更乱。
   *   离场统一交给外层列表容器（`_playEnter: false` 的那一层）整体滑出。
   */
  @Param _playExit: boolean = true;

  /**
   * 本组件独占的动画模型引用
   * ★ 必须是 `@Local`：只有组件自己持有的被装饰引用上的 `@Trace` 字段才会被追踪，
   *   直接写 `CardTransit.get().exitClock` 在 `@Monitor` 里是收不到信号的。
   */
  @Local transit: CardTransit = CardTransit.get();

  /** 横向位移（vp）· 起始在屏幕外侧，入场后回到 0 */
  @Local shift: number = 0;

  /** 纵向偏移（vp）· 入场从略下方浮上来，避免只有单一横向语言 */
  @Local shiftY: number = 0;

  /** 缩放 · 做出纵深（入 0.96→1，离 1→0.94） */
  @Local scaleVal: number = 1;

  /** 不透明度 */
  @Local alpha: number = 0;

  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
    Row().width('100%').height(0)
  }

  /** 起始态：首帧就渲染成"还没进来"的样子（此时节点还没上树，不能在这里播动画） */
  aboutToAppear(): void {
    // 容器（列表外层）不参与入场：直接以终态出现，错峰交给里面每张卡自己
    if (!this._playEnter) {
      this.shift = 0;
      this.shiftY = 0;
      this.scaleVal = 1;
      this.alpha = 1;
      return;
    }
    this.shift = -CardTransit.get().dir * CardTransit.travelOf(this.order);
    this.shiftY = CardTransit.riseY;
    this.scaleVal = CardTransit.scaleIn;
    this.alpha = 0;
  }

  /**
   * 入场 · 两条时间轴并行
   * ① 主运动（位移 + 上浮 + 缩放）：时长 `cardMs`
   * ② 透明度：更短并略晚起步 → "边滑边显"，而不是位移与淡入同时收尾
   */
  private playIn(): void {
    const delay: number = this.order * CardTransit.stepMs;

    this.getUIContext().animateTo({
      duration: CardTransit.cardMs,
      delay: delay,
      curve: CardTransit.curveIn()
    }, () => {
      this.shift = 0;
      this.shiftY = 0;
      this.scaleVal = 1;
    });

    this.getUIContext().animateTo({
      duration: CardTransit.cardMs * 0.7,
      delay: delay + CardTransit.cardMs * 0.15,
      curve: CardTransit.curveFade()
    }, () => {
      this.alpha = 1;
    });
  }

  /**
   * 离场 · "**整页同速滑出，滑到屏外的那一刻才换页**"；方向由页面给出的 `dir` 决定
   *
   * ★ 距离用 `exitTravel`（绝对值，所有 order 相同）而不是 `travelOf(order)`：
   *   离场时各卡若按序号递增距离，滑走的速度和终点都不一样，整页会被横向撕开；
   *   同一距离让整页像一块板滑出，位移才"看得见"。拖尾递增只保留在入场。
   * ★ 时长仍是 `cardMs`、延迟仍是 `order × stepMs`：保留与入场对称的"反向波浪"，
   *   而不是所有卡同时起跑（那会像整页瞬间被抽走，丢掉层次）。
   * ★ 缩放不动（保持 1）：整页平移的同时再缩小，会读成"缩一下再飞走"。
   * ★ 透明度**只在线尾收**：延迟 `0.62 × cardMs`、时长 `0.38 × cardMs`，
   *   前 62% 的行程完全不透明 —— 用户先实实在在看到整页在动，
   *   最后 38% 才淡出，并且与位移在同一时刻收尾（0.62 + 0.38 = 1 个 cardMs）。
   *   旧实现是"0 延迟就开始淡出、75% 时长淡完"，卡片还没走开就已经没了，
   *   观感退化成"内容先消失 → 整页空白 → 新页淡入"，这就是空白死区的来源。
   */
  private playOut(): void {
    const delay: number = this.order * CardTransit.stepMs;
    const direction: number = this.transit.dir;

    this.getUIContext().animateTo({
      duration: CardTransit.cardMs,
      delay: delay,
      curve: CardTransit.curveOut()
    }, () => {
      this.shift = direction * CardTransit.exitTravel;
      this.scaleVal = 1;
    });

    this.getUIContext().animateTo({
      duration: CardTransit.cardMs * 0.38,
      delay: delay + CardTransit.cardMs * 0.62,
      curve: CardTransit.curveFade()
    }, () => {
      this.alpha = 0;
    });
  }

  /**
   * 页面发来"开始离场"信号（`CardTransit.exitClock` 自增）
   *
   * ★★ 必须**推迟一帧**再启动动画（真机实测，2026-10-17 本轮定位）
   *   `@Monitor` 是在 MainPage 修改 `exitClock` 的**同一次状态更新中同步回调**的。
   *   在这一刻直接调 `animateTo`，动画会被这次更新吃掉 —— 属性**直接跳到终值**：
   *   卡片瞬移到 `exitTravel` 外、透明度瞬变 0，整页"啪"一下消失，
   *   离场动画等于不存在。证据：慢放 4 倍后连拍 5 帧仍全是空白页；
   *   推迟一帧后同样的连拍立刻抓到整页正在左移的中间帧。
   *   16ms 对 `sequenceMs` 的 40ms 余量无影响，换页时机不用改。
   */
  @Monitor('transit.exitClock')
  onExitSignal(): void {
    // 列表项不跟页面离场：它们的离场由外层容器整块负责（理由见 `_playExit` 注释）
    if (!this._playExit) {
      return;
    }
    setTimeout(() => {
      this.playOut();
    }, 16);
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .translate({ x: this.shift, y: this.shiftY })
    .scale({ x: this.scaleVal, y: this.scaleVal })
    .opacity(this.alpha)
    // 权重透传给外层 Column：0 是合法值（不参与均分），不必写条件分支
    .layoutWeight(this._weight)
    .onAppear(() => {
      if (this._playEnter) {
        this.playIn();
      }
    })
  }
}
