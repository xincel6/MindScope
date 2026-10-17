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
 *   ① **动作分两条时间轴**：位移+缩放走 `cardMs`，透明度单独走 `cardMs × 0.7` 且略晚起步。
 *      合成一条的话"位移到位"和"完全透明"同时发生，观感像贴纸被推走；
 *      分开之后是"边滑边化"，层次自然。
 *   ② **拖尾**：位移距离按 `order` 递增（`CardTransit.travelOf`），后面的组件甩得更远，
 *      形成被"带走"的流动感；所有组件等距是最容易显机械的做法。
 *   ③ **纵深**：入场 `scale 0.96 → 1` 且带 12vp 上浮；离场 `1 → 0.94`。
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
 * ★ `@BuilderParam content` 必须给默认实现，否则不传尾随闭包时编译失败（同 AppCard）。
 */

import { CardTransit } from '../common/CardTransit';

@ComponentV2
export struct RevealCard {
  /** 本组件在本页转场里的出场顺序（0 起，必须唯一且连续） */
  @Param order: number = 0;

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

  /** 离场 · 同样两条时间轴；方向由页面给出的 `dir` 决定 */
  private playOut(): void {
    const delay: number = this.order * CardTransit.stepMs;
    const direction: number = this.transit.dir;

    this.getUIContext().animateTo({
      duration: CardTransit.cardMs,
      delay: delay,
      curve: CardTransit.curveOut()
    }, () => {
      this.shift = direction * CardTransit.travelOf(this.order);
      this.scaleVal = CardTransit.scaleOut;
    });

    this.getUIContext().animateTo({
      duration: CardTransit.cardMs * 0.75,
      delay: delay,
      curve: CardTransit.curveFade()
    }, () => {
      this.alpha = 0;
    });
  }

  /** 页面发来"开始离场"信号（`CardTransit.exitClock` 自增） */
  @Monitor('transit.exitClock')
  onExitSignal(): void {
    this.playOut();
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .translate({ x: this.shift, y: this.shiftY })
    .scale({ x: this.scaleVal, y: this.scaleVal })
    .opacity(this.alpha)
    .onAppear(() => {
      this.playIn();
    })
  }
}
