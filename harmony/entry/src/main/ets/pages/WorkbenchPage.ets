/**
 * WorkbenchPage · 工作台（一级页签）
 *
 * 页面契约：`@Param pageParam: WorkbenchPageParam`
 *   - `serverOnline` / `serverStatusLabel` / `healthChecking`  ← 服务状态圆点与刷新按钮
 *   - `currentTask`         ← 「当前任务」卡片（null = 暂无进行中的分析）
 *   - `recentItems` 等      ← 「最近使用的素材」两条（含分数与严重度进度条）
 *   - 各 `on*` 回调         ← 把动作交回窗口层（页面不碰 store、不碰路由栈）
 *
 * ★ 页面纪律：本文件**不 import 任何 store**、不发请求、不操作导航栈。
 *   所有数据与动作都从参数进出，这样本页可以脱离整个 App 单独渲染。
 *
 * ★ 「刷新」按钮放在页头**最右侧**（按需求），所以这里没用 `PageHeader`（它没有右侧插槽），
 *   而是自绘标题行 —— 标题字号/颜色仍严格取自 `UiTheme`，不会与其它页漂移。
 */

import { UiTheme } from '../common/UiTheme';
import { CurrentTaskModel, RecentMediaModel, TaskStatus } from '../types/Index';
import { WorkbenchPageParam } from '../types/PageParams';
import { RippleCard } from '../components/RippleCard';
import { ServiceStatusCard } from '../components/workbench/ServiceStatusCard';
import { StartAssessmentCard } from '../components/workbench/StartAssessmentCard';
import { CurrentTaskCard } from '../components/workbench/CurrentTaskCard';
import { RecentMediaSection } from '../components/workbench/RecentMediaSection';

@ComponentV2
export struct WorkbenchPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: WorkbenchPageParam = new WorkbenchPageParam();

  // ══════════════════ 派生文案 ══════════════════

  /** 服务状态文案 · 参数没给就按在线状态兜底 */
  @Computed
  get serverLabel(): string {
    const label: string = this.pageParam.serverStatusLabel;
    if (label.length > 0) {
      return label;
    }
    return this.pageParam.serverOnline ? '在线' : '未连接';
  }

  // ══════════════════ 页头（标题 + 右侧刷新） ══════════════════

  /**
   * 刷新按钮 · 与背景完全重合
   * ★ 图标暂用字符 `⟳` 占位（用户明确说明图标待选）：
   *   拿到图标资源后把这里换成 `Image($r('app.media.ic_refresh'))` 即可，其它代码不动。
   */
  @Builder
  refreshButton() {
    Button(this.pageParam.healthChecking ? '…' : '⟳')
      .fontSize(20)
      .fontColor(UiTheme.textSecondary)
      .backgroundColor(Color.Transparent)
      .borderRadius(UiTheme.cardRadius)
      .width(40)
      .height(40)
      .enabled(!this.pageParam.healthChecking)
      .onClick(() => {
        this.pageParam.onRefresh();
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

        Button(this.pageParam.healthChecking ? '重连中…' : '重试')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.danger)
          .backgroundColor(Color.Transparent)
          .borderWidth(1)
          .borderColor(UiTheme.danger)
          .borderRadius(UiTheme.buttonRadius)
          .height(36)
          .padding({ left: UiTheme.gapL, right: UiTheme.gapL })
          .enabled(!this.pageParam.healthChecking)
          .onClick(() => {
            this.pageParam.onRefresh();
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
              online: this.pageParam.serverOnline,
              label: this.serverLabel,
              checking: this.pageParam.healthChecking,
              serverLabel: this.pageParam.serverLabel,
              onRefresh: () => {
                this.pageParam.onRefresh();
              }
            })
          }

          // ── ② 离线横幅（只在不可达时出现） ──
          if (!this.pageParam.serverOnline && !this.pageParam.healthChecking) {
            this.offlineBanner()
          }

          // ── ③ 开始新的辅助评估 ──
          StartAssessmentCard({
            onPick: () => {
              this.pageParam.onSelectMedia();
            }
          })

          // ── ④ 当前任务 ──
          CurrentTaskCard({
            task: this.pageParam.currentTask,
            onOpen: () => {
              this.pageParam.onOpenTask();
            }
          })

          // ── ⑤ 最近使用的素材 ──
          RecentMediaSection({
            items: this.pageParam.recentItems,
            loading: this.pageParam.recentLoading,
            errorMsg: this.pageParam.recentError,
            onViewAll: () => {
              this.pageParam.onViewAll();
            },
            onSelect: (mediaId: string) => {
              this.pageParam.onSelectRecent(mediaId);
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
