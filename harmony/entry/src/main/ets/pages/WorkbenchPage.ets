/**
 * WorkbenchPage · 工作台（一级页签）
 *
 * ────────────────── 本页为什么直接读 AppStore（唯一的纪律例外）──────────────────
 * 工程通用纪律是「页面只吃参数、不 import store」。工作台**刻意偏离**了这一条，
 * 原因是这条纪律在"异步到达的数据"上不可靠：
 *
 *   · 服务状态来自 `/health` 探活、任务进度来自 WebSocket，都是 `await` 之后才写值；
 *   · 页面是通过 `Navigation.navDestination` 挂载的，**改参数的字段不会让已挂载的
 *     页面重新收到新值**（实测：点刷新圆点不变色，切页签再回来才更新）。
 *
 * 而 `AppStore` 是 `@ObservedV2` + `@Trace`，它的字段变化**必定**触发依赖它的组件重绘，
 * 是 ArkUI 里最可靠的一条响应式路径。所以本页：
 *   · **读** 走 `AppStore`（响应式，异步刷新不会丢）；
 *   · **写** 仍走注入的回调（不碰路由栈、不发请求，纪律的核心部分保留）。
 *
 * ★ 这道口子只开给工作台：其它页签的数据是"进入页面时一次性拉取"的，
 *   没有这个痛点，继续走参数契约。
 */

import { UiTheme } from '../common/UiTheme';
import { AppStore } from '../store/AppStore';
import { CurrentTaskModel, RecentMediaModel } from '../types/Index';
import { RippleCard } from '../components/RippleCard';
import { ServiceStatusCard } from '../components/workbench/ServiceStatusCard';
import { StartAssessmentCard } from '../components/workbench/StartAssessmentCard';
import { CurrentTaskCard } from '../components/workbench/CurrentTaskCard';
import { RecentMediaSection } from '../components/workbench/RecentMediaSection';

/** 工作台「最近使用的素材」展示条数（用户指定两条） */
const RECENT_MEDIA_LIMIT: number = 2;

@ComponentV2
export struct WorkbenchPage {
  // ══════════════════ 入参 · 动作回调（全部由窗口层实现）══════════════════

  /** 点右上角刷新 / 离线横幅的「重试」· 窗口层调 `AppStore.checkHealth()` */
  @Param onRefresh: () => void = () => {};

  /** 点「选择素材」或「开始新的辅助评估」卡片 · 窗口层跳素材选择页 */
  @Param onSelectMedia: () => void = () => {};

  /** 点「当前任务」卡片 · 窗口层重新打开分析详情页 */
  @Param onOpenTask: () => void = () => {};

  /** 点「查看全部」· 窗口层切到历史报告页签 */
  @Param onViewAll: () => void = () => {};

  /** 点某条最近素材 · 窗口层按该素材的报告快照打开分析详情页 */
  @Param onSelectRecent: (mediaId: string) => void = (mediaId: string) => {};

  // ══════════════════ 读数 · 直接订阅 store（响应式，见文件头说明）══════════════════

  /** store 门面 · 只读，不在这里调用任何写方法 */
  @Computed
  get app(): AppStore {
    return AppStore.get();
  }

  /** 服务端是否在线 */
  @Computed
  get serverOnline(): boolean {
    return this.app.serverOnline;
  }

  /** 是否正在探活 */
  @Computed
  get healthChecking(): boolean {
    return this.app.healthChecking;
  }

  /** 服务端地址展示 · 形如 100.122.178.113:8000 */
  @Computed
  get serverLabel(): string {
    return `${this.app.serverHost}:${this.app.serverPort}`;
  }

  /** 当前任务 · null 表示「暂无进行中的分析」 */
  @Computed
  get currentTask(): CurrentTaskModel | null {
    return this.app.currentTask();
  }

  /** 最近 2 条素材（报告 + 媒体库拼出来的） */
  @Computed
  get recentItems(): RecentMediaModel[] {
    return this.app.recentMedia(RECENT_MEDIA_LIMIT);
  }

  /** 最近素材是否仍在加载（只有"列表为空且正在拉"才算，避免有缓存时误报） */
  @Computed
  get recentLoading(): boolean {
    return this.app.reportLoading && this.recentItems.length === 0;
  }

  /** 最近素材的错误文案（有数据时不展示错误，避免同时出现内容与报错） */
  @Computed
  get recentError(): string {
    return this.recentItems.length === 0 ? this.app.reportError : '';
  }

  // ══════════════════ 派生文案 ══════════════════

  /** 服务状态文案 */
  @Computed
  get resolvedServerLabel(): string {
    const label: string = this.app.serverStatusLabel;
    if (label.length > 0) {
      return label;
    }
    return this.serverOnline ? '在线' : '未连接';
  }

  // ══════════════════ 页头（标题 + 右侧刷新） ══════════════════

  /**
   * 刷新按钮 · 与背景完全重合
   * ★ 图标暂用字符 `⟳` 占位（用户明确说明图标待选）：
   *   拿到图标资源后把这里换成 `Image($r('app.media.ic_refresh'))` 即可，其它代码不动。
   */
  @Builder
  refreshButton() {
    Button(this.healthChecking ? '…' : '⟳')
      .fontSize(20)
      .fontColor(UiTheme.textSecondary)
      .backgroundColor(Color.Transparent)
      .borderRadius(UiTheme.cardRadius)
      .width(40)
      .height(40)
      .enabled(!this.healthChecking)
      .onClick(() => {
        this.onRefresh();
      })
  }

  @Builder
  pageHeader() {
    Column({ space: UiTheme.gapXs }) {
      Row() {
        Text('工作台')
          .fontSize(UiTheme.fontSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        this.refreshButton()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('分析入口与今日概览')
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ══════════════════ 顶部横幅（离线提示） ══════════════════

  /**
   * 离线提示 · 只在"服务端不可达"时出现
   * ★ 不用整页错误态：工作台即使离线也应该能看历史素材与上一次的分数（本地有缓存），
   *   所以这里只加一条横幅，而不是用 `ErrorRetryView` 把整页盖掉。
   */
  @Builder
  offlineBanner() {
    RippleCard({ _padding: UiTheme.gapM, _enabled: false, _clickable: false }) {
      Row({ space: UiTheme.gapS }) {
        Column({ space: UiTheme.gapXs }) {
          Text('服务端未连接')
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.danger)
            .width('100%')
            .textAlign(TextAlign.Start)

          Text('已显示本地缓存的数据；点右上角刷新可重试连接')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(this.healthChecking ? '重连中…' : '重试')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.danger)
          .backgroundColor(Color.Transparent)
          .borderWidth(1)
          .borderColor(UiTheme.danger)
          .borderRadius(UiTheme.buttonRadius)
          .height(36)
          .padding({ left: UiTheme.gapL, right: UiTheme.gapL })
          .enabled(!this.healthChecking)
          .onClick(() => {
            this.onRefresh();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Column({ space: UiTheme.gapL }) {
      Scroll() {
        Column({ space: UiTheme.gapL }) {
          this.pageHeader()

          // ── ① 服务状态（圆点 + 文案 + 地址） ──
          RippleCard({ _padding: UiTheme.gapM, _enabled: false, _clickable: false }) {
            ServiceStatusCard({
              online: this.serverOnline,
              label: this.resolvedServerLabel,
              checking: this.healthChecking,
              serverLabel: this.serverLabel,
              onRefresh: () => {
                this.onRefresh();
              }
            })
          }

          // ── ② 离线横幅（只在不可达时出现） ──
          if (!this.serverOnline && !this.healthChecking) {
            this.offlineBanner()
          }

          // ── ③ 开始新的辅助评估 ──
          StartAssessmentCard({
            onPick: () => {
              this.onSelectMedia();
            }
          })

          // ── ④ 当前任务 ──
          CurrentTaskCard({
            task: this.currentTask,
            onOpen: () => {
              this.onOpenTask();
            }
          })

          // ── ⑤ 最近使用的素材 ──
          RecentMediaSection({
            items: this.recentItems,
            loading: this.recentLoading,
            errorMsg: this.recentError,
            onViewAll: () => {
              this.onViewAll();
            },
            onSelect: (mediaId: string) => {
              this.onSelectRecent(mediaId);
            }
          })
        }
        .width('100%')
        .padding({ bottom: UiTheme.gapXl })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: UiTheme.pagePadding, right: UiTheme.pagePadding, top: UiTheme.gapL })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }
}
