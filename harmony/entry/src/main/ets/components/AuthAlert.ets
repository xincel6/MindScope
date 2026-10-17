/**
 * AuthAlert · **登录/注册失败的弹性警告弹窗**（本轮新增）
 *
 * 需求原话：「在输入框之上弹出了一个警告弹窗，警告弹窗需要做出弹性的动画，
 * 凭空出现撞击在左边的屏幕上」。
 *
 * 于是这个横幅的动画被拆成 4 段（顺序即物理直觉）：
 * ```
 *  ① 凭空出现   屏幕左侧之外（x = -480vp）+ 全透明
 *  ② 撞上来     弹簧曲线（springMotion）把 x 拉到 0、透明度拉到 1
 *              —— 弹簧过冲自己就会产生"撞上去"的弹性
 *  ③ 撞击挤压   x 轴拉长 1.05 / y 轴压扁 0.90（缩放中心钉在左边缘，所以不会离开屏幕边）
 *  ④ 落定       形变回 1.0，贴住左边缘不动
 * ```
 *
 * ★ 四条实现纪律（本工程踩过的坑，见根目录 `BUG清单.md`）：
 *   1. **只动 transform / opacity**（`translate` / `scale` / `opacity`），
 *      绝不让动画驱动**尺寸**，也不挂 `onSizeChange` —— 否则就是 BUG-01 那种
 *      「测量 → 状态 → 尺寸 → 布局 → 测量」的反馈环。
 *   2. **不要在一个 AUTO 高度的容器里放 `height('100%')` 的子节点**（BUG-07）：
 *      左侧"撞击条"因此没有做成独立的 `Row`，而是直接用 `border-left` 表达
 *      —— 零新增节点、高度自动跟随内容。
 *   3. **重放前把所有动画属性一起复位**（BUG-04）：重复登录失败时页面用
 *      "卸载再挂载"的方式重放，`aboutToAppear` 第一件事就是瞬时（duration 0）归位，
 *      避免"第二次弹窗看不见"。
 *   4. **弹窗不占布局**：宿主页面把它放在 `Stack` 顶层，`translate` 位移不参与排版，
 *      弹出/收起都不会推动输入框。
 *
 * ★ 它是**纯展示组件**：文案全部来自参数（页面/窗口层给），自己不判断错误类型。
 */

import { curves } from '@kit.ArkUI';
import { UiTheme } from '../common/UiTheme';

/** 起始位置：屏幕左侧之外（远大于任何手机宽度，保证"凭空出现"而不是"滑一小段"） */
const OFF_SCREEN_LEFT: number = -480;

/** 撞击瞬间的形变幅度 */
const IMPACT_SCALE_X: number = 1.05;
const IMPACT_SCALE_Y: number = 0.90;

/** 撞到屏幕边之后、开始挤压的时间点（ms）· 与弹簧到位的时间大致对齐 */
const IMPACT_DELAY_MS: number = 170;

/** 挤压之后开始落定的时间点（ms） */
const SETTLE_DELAY_MS: number = 300;

/** 收起动画时长（ms） */
const EXIT_DURATION_MS: number = 220;

/** 关键数值圆圈直径 */
const BADGE_SIZE: number = 18;

@ComponentV2
export struct AuthAlert {
  /** 标题 · 如「登录失败」「无法连接服务端」 */
  @Param title: string = '登录失败';

  /** 主文案 · 服务端 `detail` 或本地校验提示 */
  @Param message: string = '';

  /** 诊断行 · 由窗口层拼好（服务端是否回应 / 该往哪查），空串则不显示 */
  @Param hint: string = '';

  /** 自动收起时长（毫秒）· 0 表示不自动收起（点了才收） */
  @Param autoDismissMs: number = 5200;

  /** 收起完成回调 · 宿主页面在这里把本组件卸载 */
  @Param onClose: () => void = () => {};

  // ── 动画状态：全部是 transform / opacity，不参与布局测量 ──
  @Local offsetX: number = OFF_SCREEN_LEFT;
  @Local alertOpacity: number = 0;
  @Local squashX: number = 1;
  @Local squashY: number = 1;

  /** 延时任务句柄 · 卸载时必须全部清掉，否则回调会打到已销毁的组件上 */
  private timers: number[] = [];

  /** 是否已在收起（防止自动收起与点击收起重复触发） */
  private closing: boolean = false;

  // ══════════════════ 生命周期 ══════════════════

  aboutToAppear(): void {
    this.playEnter();
    if (this.autoDismissMs > 0) {
      this.later((): void => {
        this.startExit();
      }, this.autoDismissMs);
    }
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  // ══════════════════ 动画 ══════════════════

  /** 弹入：复位 → 弹簧撞入 → 撞击挤压 → 落定 */
  private playEnter(): void {
    // ① 瞬时复位（duration: 0）· 所有动画属性一起归位，重放才不会"看不见"
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      this.offsetX = OFF_SCREEN_LEFT;
      this.alertOpacity = 0;
      this.squashX = 1;
      this.squashY = 1;
    });

    // ② 撞上来：弹簧曲线，阻尼 0.55 会明显过冲一次 —— "弹性"就来自这里
    this.getUIContext().animateTo({ curve: curves.springMotion(0.36, 0.55) }, (): void => {
      this.offsetX = 0;
      this.alertOpacity = 1;
    });

    // ③ 撞击挤压：横向拉长、纵向压扁（缩放中心在左边缘，贴着屏幕不脱开）
    this.later((): void => {
      this.getUIContext().animateTo({ duration: 110, curve: Curve.Sharp }, (): void => {
        this.squashX = IMPACT_SCALE_X;
        this.squashY = IMPACT_SCALE_Y;
      });
    }, IMPACT_DELAY_MS);

    // ④ 落定：形变回正
    this.later((): void => {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, (): void => {
        this.squashX = 1;
        this.squashY = 1;
      });
    }, SETTLE_DELAY_MS);
  }

  /** 收起：向左淡出，动画结束后通知宿主卸载 */
  private startExit(): void {
    if (this.closing) {
      return;
    }
    this.closing = true;
    this.clearTimers();
    this.getUIContext().animateTo({ duration: EXIT_DURATION_MS, curve: Curve.EaseIn }, (): void => {
      this.offsetX = OFF_SCREEN_LEFT;
      this.alertOpacity = 0;
    });
    this.later((): void => {
      this.onClose();
    }, EXIT_DURATION_MS);
  }

  // ══════════════════ 小工具 ══════════════════

  /** 登记一个延时任务（句柄统一回收，避免卸载后还回调） */
  private later(task: () => void, delayMs: number): void {
    const id: number = setTimeout(task, delayMs);
    this.timers.push(id);
  }

  private clearTimers(): void {
    for (let i = 0; i < this.timers.length; i++) {
      clearTimeout(this.timers[i]);
    }
    this.timers = [];
  }

  // ══════════════════ 界面 ══════════════════

  build() {
    // 外层 Stack 只负责"贴住页面顶部"；translate 到屏幕外的部分看不见
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: UiTheme.gapXs }) {
        // ── 标题行：感叹号 + 标题 + 关闭 ──
        Row({ space: UiTheme.gapS }) {
          Text('!')
            .fontSize(UiTheme.fontSizeCaption)
            .fontWeight(FontWeight.Bold)
            .fontColor(UiTheme.cardBackground)
            .width(BADGE_SIZE)
            .height(BADGE_SIZE)
            .borderRadius(BADGE_SIZE / 2)
            .backgroundColor(UiTheme.danger)
            .textAlign(TextAlign.Center)

          Text(this.title)
            .fontSize(UiTheme.fontSizeSection)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.textPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text('✕')
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textSecondary)
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
            .onClick((): void => {
              this.startExit();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // ── 主文案：服务端 detail（用户名或密码错误 / 账号已禁用 / 网络不可达…）──
        if (this.message.length > 0) {
          Text(this.message)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.danger)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        // ── 诊断行：服务端到底有没有回应，这一行就是为了把 401 和"连不上"分开 ──
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: UiTheme.gapL + UiTheme.alertAccentWidth,
        right: UiTheme.gapM,
        top: UiTheme.gapM,
        bottom: UiTheme.gapM
      })
      // 左侧贴屏幕边缘 → 左圆角为 0，右侧才有圆角；"撞击条"直接用 border-left 表达
      .borderRadius({
        topLeft: 0,
        bottomLeft: 0,
        topRight: UiTheme.alertRadius,
        bottomRight: UiTheme.alertRadius
      })
      .backgroundColor(UiTheme.dangerSoft)
      .border({
        width: { left: UiTheme.alertAccentWidth, right: 1, bottom: 1 },
        color: { left: UiTheme.danger, right: UiTheme.divider, bottom: UiTheme.divider }
      })
      .translate({ x: this.offsetX })
      // 缩放中心钉在左边缘（0 = 元素左边界），挤压时才不会离开屏幕边
      .scale({ x: this.squashX, y: this.squashY, centerX: 0 })
      .opacity(this.alertOpacity)
      .onClick((): void => {
        this.startExit();
      })
    }
    .width('100%')
    .padding({ top: UiTheme.alertOffsetTop })
  }
}
