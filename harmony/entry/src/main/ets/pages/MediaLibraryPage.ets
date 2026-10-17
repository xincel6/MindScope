/**
 * MediaLibraryPage · 素材库（一级页签）· **本轮仅占位**
 *
 * 页面契约：`@Param pageParam: TabPageParam`
 *   - `activeTab` 当前页签（本页固定为 `MainTab.media`）
 *   - `busy` / `errorMsg` 下一轮接入 `AppStore.mediaItems` 后驱动骨架屏与"加载失败 + 重试"
 *   - `pathStack` 预留导航栈，供"上传素材""素材详情"跳转用
 *
 * ★ 页面纪律：不 import 任何 store、不发请求、不碰路由栈。
 */

import { UiTheme } from '../common/UiTheme';
import { TabPageParam } from '../types/PageParams';
import { PageHeader } from '../components/PageHeader';
import { PlaceholderView } from '../components/PlaceholderView';
import { RevealCard } from '../components/RevealCard';

@ComponentV2
export struct MediaLibraryPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: TabPageParam = new TabPageParam();

  build() {
    Column({ space: UiTheme.gapL }) {
      // 0 号位
      RevealCard({ order: 0 }) {
        Column() {
          PageHeader({ title: '素材库', subtitle: '已上传的图片与视频' })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // 1 号位
      RevealCard({ order: 1 }) {
        PlaceholderView({
          glyph: '库',
          title: '素材库待实现',
          description: '这里将放素材列表（缩略图 / 类型 / 时间）与上传入口。',
          hint: '下一轮：接入 AppStore.mediaItems、MediaApi.uploadImage 与离线镜像数据',
          actionLabel: '下一步操作',
          onAction: () => {
            this.getUIContext().getPromptAction().showToast({ message: '本页为占位页，下一轮实现素材列表与上传' });
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
