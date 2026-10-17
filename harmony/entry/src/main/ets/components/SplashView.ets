/**
 * SplashView · **开屏页**（本轮新增）
 *
 * 需求原话：「还需要一个开屏页面，刚进入应用加载的时候要弹出这个页面，
 * 留下一个图标占位下面一行字是 MindScope」。所以本页只有两个元素：
 *   ① 品牌图标占位（`LogoPlaceholder`，换真图标只改那一个文件）
 *   ② 一行产品名 `MindScope`
 *
 * ────────────────── 与"启动窗口"的关系（两级开屏，看起来是一级）──────────────────
 * ```
 * ① 系统启动窗口：module.json5 的 startWindowIcon / startWindowBackground
 *                  → 冷启动第一帧，由系统画，ArkUI 还没起来
 * ② 本组件（开屏页）：UI 起来后覆盖在最上层，等引导完成再淡出
 * ```
 * 两级底色都取 `#FFFFFF`（`UiTheme.pageBackground`），所以用户看到的是
 * "图标 → 图标 + 名字 → 登录页"的连续过程，中间不会闪别的颜色。
 *
 * ★ 时长由宿主决定：`pages/Index.ets` 保证它至少显示
 *   `UiTheme.splashMinDurationMs`，否则缓存命中时只会闪一下（比不显示还难看）。
 *
 * ★ 动画纪律（与 `AuthAlert` 一致）：只动 `opacity` / `scale` / `translate`，
 *   不碰任何尺寸，所以不会牵动布局测量，也不会出现 BUG-01 那类反馈环。
 */

import { curves } from '@kit.ArkUI';
import { UiTheme } from '../common/UiTheme';
import { LogoPlaceholder } from './LogoPlaceholder';

/** 产品名淡入的延时（ms）· 让"图标先落地、名字再跟上来" */
const TITLE_DELAY_MS: number = 170;

/** 产品名淡入时长（ms） */
const TITLE_FADE_MS: number = 420;

@ComponentV2
export struct SplashView {
  // ── 动画状态（transform / opacity，不参与布局）──
  @Local logoScale: number = 0.86;
  @Local logoOpacity: number = 0;
  @Local titleOpacity: number = 0;
  @Local titleOffsetY: number = 14;

  private timers: number[] = [];

  aboutToAppear(): void {
    // ① 图标：弹簧放大 + 淡入（"弹"一下落地，与全局的弹性语言一致）
    this.getUIContext().animateTo({ curve: curves.springMotion(0.5, 0.52) }, (): void => {
      this.logoScale = 1;
      this.logoOpacity = 1;
    });

    // ② 产品名：稍晚一点淡入并上浮到位
    const id: number = setTimeout((): void => {
      this.getUIContext().animateTo({ duration: TITLE_FADE_MS, curve: Curve.EaseOut }, (): void => {
        this.titleOpacity = 1;
        this.titleOffsetY = 0;
      });
    }, TITLE_DELAY_MS);
    this.timers.push(id);
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.timers.length; i++) {
      clearTimeout(this.timers[i]);
    }
    this.timers = [];
  }

  build() {
    Column({ space: UiTheme.gapXl }) {
      LogoPlaceholder({ _size: UiTheme.splashLogoSize, radius: UiTheme.splashLogoRadius })
        .scale({ x: this.logoScale, y: this.logoScale })
        .opacity(this.logoOpacity)

      Text('MindScope')
        .fontSize(UiTheme.fontSizeSplashTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(UiTheme.textPrimary)
        .letterSpacing(1)
        .translate({ y: this.titleOffsetY })
        .opacity(this.titleOpacity)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(UiTheme.pageBackground)
  }
}
