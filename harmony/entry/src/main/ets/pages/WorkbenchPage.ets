/**
 * WorkbenchPage · 工作台（一级页签）· **本轮仅占位**
 *
 * 页面契约：`@Param pageParam: TabPageParam`
 *   - `activeTab` 当前页签（本页固定为 `MainTab.workbench`）
 *   - `busy` / `errorMsg` 下一轮接入真实数据后驱动骨架屏与重试；
 *     本轮没有数据源，因此不渲染加载态与错误态（无触发器，写了也无从验证）
 *   - `pathStack` 预留的导航栈，供"下一步操作"跳转到二级页面用
 *
 * ★ 页面纪律：不 import 任何 store、不发请求、不碰路由栈（栈由参数注入）。
 */

import { UiTheme } from '../common/UiTheme';
import { TabPageParam } from '../types/PageParams';
import { PageHeader } from '../components/PageHeader';
import { PlaceholderView } from '../components/PlaceholderView';

@ComponentV2
export struct WorkbenchPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: TabPageParam = new TabPageParam();

  build() {
    Column({ space: UiTheme.gapL }) {
      PageHeader({ title: '工作台', subtitle: '分析入口与今日概览' })

      PlaceholderView({
        glyph: '析',
        title: '工作台待实现',
        description: '这里将放「上传素材 / 开始分析 / 最近一次评分 / 分析进度」入口。',
        hint: '下一轮：接入 AppStore.mediaItems 与 WS 分析进度（analysisProgress / analysisScore）',
        actionLabel: '下一步操作',
        onAction: () => {
          this.getUIContext().getPromptAction().showToast({ message: '本页为占位页，下一轮实现分析入口' });
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
