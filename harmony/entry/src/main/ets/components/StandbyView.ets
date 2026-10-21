/**
 * StandbyView · **待机页**（用户进到 App 看到的第一个界面）
 *
 * 它在两个阶段出现：
 *   ① 冷启动引导中（`Index.phase === ''`）—— 就是"加载待机页"本体；
 *   ② 已登录冷启动、即将切到主界面时，作为覆盖层淡出（见 `Index` 的 `bootCoverVisible`）。
 *
 * ══════════════════ 这一页为什么长这样 ══════════════════
 * 整屏只有"图标 + 名字 + 一句状态"，因为它的唯一职责是**让等待看起来是在进行**：
 *   · 图标按 `UiTheme.heroTop` 落在屏幕偏上，**不是居中** —— 居中会让整屏显得空，
 *     而偏上正好给下面留出"即将盖上来的白色表单层"的位置（见 `LoginPage`）；
 *   · 状态行贴底并做很慢的呼吸（1.1s 一个来回），提示"还在动"；
 *   · 底色与应用图标同源的青绿渐变，图标本身是同一张图里抠出来的白色标记，
 *     所以冷启动时"启动图标 → 待机页"几乎是无缝的。
 *
 * ★ 这一页不做任何数据判断：文案与是否该走了都由窗口层（`Index`）决定。
 */
import { curves } from '@kit.ArkUI';
import { UiTheme } from '../common/UiTheme';
import { BrandBackdrop } from './BrandBackdrop';
import { BrandHero } from './BrandHero';

/** 呼吸一个来回的时长（ms）· 慢到不像"卡住的闪烁"，快到来得及看到两次 */
const BREATH_MS: number = 1100;

@ComponentV2
export struct StandbyView {
  /** 状态行文案（"正在启动…" / "正在准备数据…"） */
  @Param statusText: string = '正在启动…';

  /**
   * 图标的"长大"倍数 · 由窗口层驱动（1 → 1/`heroLogoStart`）
   *
   * ★ 待机页停留时是 1（图标只画 `heroLogoStart` 那一档，152 × 0.84 ≈ 128vp）；
   *   `Index` 决定要进登录页时，用一段动画把它推到 `1 / heroLogoStart`，
   *   图标就在**待机页上**原地长大到登录页的尺寸 —— 用户要的"先放大、再盖上"。
   */
  @Param growScale: number = 1;

  /** 整块内容的淡入值（入场用） */
  @Local contentOpacity: number = 0;

  /** 图标的入场缩放（0.96 → 1） */
  @Local logoScale: number = 0.96;

  /** 状态行的呼吸透明度 */
  @Local statusOpacity: number = 1;

  /** 呼吸定时器 · 离开页面时必须清掉，否则会在已销毁的组件上继续跑 */
  private breathTimer: number = -1;

  aboutToAppear(): void {
    // 入场：图标从 0.96 轻轻撑到 1、内容整体淡入。时长刻意短于待机最短时长，
    // 保证"该走了"的时候它已经稳稳停住，不会在切走的一瞬间还在动。
    this.getUIContext().animateTo({
      duration: 420,
      curve: curves.springMotion(0.42, 0.68)
    }, (): void => {
      this.contentOpacity = 1;
      this.logoScale = 1;
    });

    // 状态行呼吸：只动 opacity（不触发重排），看起来像"还在处理"
    this.breathTimer = setInterval((): void => {
      const next: number = this.statusOpacity > 0.8 ? 0.4 : 1;
      this.getUIContext().animateTo({ duration: BREATH_MS * 0.8, curve: Curve.EaseInOut }, (): void => {
        this.statusOpacity = next;
      });
    }, BREATH_MS);
  }

  aboutToDisappear(): void {
    if (this.breathTimer >= 0) {
      clearInterval(this.breathTimer);
      this.breathTimer = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      BrandBackdrop()

      Column() {
        Column() {
          BrandHero({
            logoWidth: UiTheme.heroLogoWidth,
            // ★ 三个乘数各管一段时间：
            //   logoScale   入场 0.96 → 1（只在前 420ms）
            //   growScale   窗口层要进登录页时 1 → 1/0.84（"长大"）
            //   heroLogoStart 待机页的基础比例 0.84（登录页是 1）
            logoScale: this.logoScale * this.growScale * UiTheme.heroLogoStart
          })
        }
        .width('100%')
        .margin({ top: UiTheme.heroTop })
        .opacity(this.contentOpacity)

        Blank()

        Text(this.statusText)
          .fontSize(UiTheme.standbyStatusSize)
          .fontColor(UiTheme.onBrandMuted)
          .opacity(this.contentOpacity * this.statusOpacity)
          .margin({ bottom: UiTheme.standbyStatusBottom })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
