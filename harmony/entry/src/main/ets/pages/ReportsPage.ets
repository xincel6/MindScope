/**
 * ReportsPage · 历史报告（一级页签）· **本轮仅占位**
 *
 * 页面契约：`@Param pageParam: TabPageParam`
 *   - `activeTab` 当前页签（本页固定为 `MainTab.reports`）
 *   - `busy` / `errorMsg` 下一轮接入 `AppStore.reportItems / reportTotal` 后驱动骨架屏与重试
 *   - `pathStack` 预留导航栈，供"报告详情"跳转用
 *
 * ★ 页面纪律：不 import 任何 store、不发请求、不碰路由栈。
 */

import { UiTheme } from '../common/UiTheme';
import { TabPageParam } from '../types/PageParams';
import { PageHeader } from '../components/PageHeader';
import { PlaceholderView } from '../components/PlaceholderView';
import { RevealCard } from '../components/RevealCard';

@ComponentV2
export struct ReportsPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: TabPageParam = new TabPageParam();

  build() {
    Column({ space: UiTheme.gapL }) {
      // 0 号位
      RevealCard({ order: 0 }) {
        Column() {
          PageHeader({ title: '历史报告', subtitle: '按严重度与媒体类型筛选' })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // 1 号位
      RevealCard({ order: 1 }) {
        PlaceholderView({
          glyph: '报',
          title: '历史报告待实现',
          description: '这里将放报告列表（BDI 分数 / 严重度 / 检测时间）与筛选分页。',
          hint: '下一轮：接入 AppStore.reportItems、reportTotal 与 ReportApi 的筛选分页',
          actionLabel: '下一步操作',
          onAction: () => {
            this.getUIContext().getPromptAction().showToast({ message: '本页为占位页，下一轮实现报告列表与筛选' });
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: UiTheme.pagePadding, right: UiTheme.pagePadding, top: UiTheme.gapL })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }
}
