/**
 * StatsPage · 统计（一级页签）· **本轮仅占位**
 *
 * 页面契约：`@Param pageParam: TabPageParam`
 *   - `activeTab` 当前页签（本页固定为 `MainTab.stats`）
 *   - `busy` / `errorMsg` 下一轮接入 `AppStore.statsSummary / statsBuckets` 后驱动骨架屏与重试
 *   - `pathStack` 预留导航栈
 *
 * ★ 重要分数用大字号：本页接入数据后请用 `UiTheme.fontSizeMetric`（32vp）渲染平均 BDI 分数。
 * ★ 页面纪律：不 import 任何 store、不发请求、不碰路由栈。
 */

import { UiTheme } from '../common/UiTheme';
import { TabPageParam } from '../types/PageParams';
import { PageHeader } from '../components/PageHeader';
import { PlaceholderView } from '../components/PlaceholderView';

@ComponentV2
export struct StatsPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: TabPageParam = new TabPageParam();

  build() {
    Column({ space: UiTheme.gapL }) {
      PageHeader({ title: '统计', subtitle: '分析次数、严重度分布与 BDI 趋势' })

      PlaceholderView({
        glyph: '统',
        title: '统计待实现',
        description: '这里将放总分析次数、严重度分布与 BDI 趋势图。',
        hint: '下一轮：接入 AppStore.statsSummary 与 statsBuckets；重要分数用 32vp 大字号',
        actionLabel: '下一步操作',
        onAction: () => {
          this.getUIContext().getPromptAction().showToast({ message: '本页为占位页，下一轮实现统计图表' });
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: UiTheme.pagePadding, right: UiTheme.pagePadding, top: UiTheme.gapL })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }
}
