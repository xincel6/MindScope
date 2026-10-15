/**
 * ProfilePage · 我的（一级页签）· **本轮仅占位**
 *
 * 页面契约：`@Param pageParam: ProfilePageParam`（定义在 `types/PageParams.ets`）
 *   - 继承 `TabPageParam` 的全部字段（activeTab / busy / errorMsg / pathStack）
 *   - 额外：`userName`、`serverLabel` —— 展示用的只读文案，由窗口层从
 *     `AppStore.username()` 与 `AppStore.serverHost/serverPort` 取好再传进来
 *
 * ★ 本轮**不做登出**（用户已确认）：所以本页没有登出按钮。
 *   下一轮补登出时，只需在窗口层给 `ProfilePageParam` 的 `onLogout` 赋值，
 *   页面侧加一个按钮调用 `this.pageParam.onLogout()` 即可，不必改动其它文件。
 *
 * ★ 页面纪律：不 import 任何 store、不发请求、不碰路由栈。
 */

import { UiTheme } from '../common/UiTheme';
import { ProfilePageParam } from '../types/PageParams';
import { PageHeader } from '../components/PageHeader';
import { AppCard } from '../components/AppCard';
import { PlaceholderView } from '../components/PlaceholderView';

@ComponentV2
export struct ProfilePage {
  /** ★ 本页唯一入参 */
  @Param pageParam: ProfilePageParam = new ProfilePageParam();

  build() {
    Column({ space: UiTheme.gapL }) {
      PageHeader({ title: '我的', subtitle: '账号与设置' })

      AppCard({ title: '账号信息' }) {
        Column({ space: UiTheme.gapM }) {
          Row({ space: UiTheme.gapM }) {
            Text('当前用户')
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textSecondary)
              .width(80)
              .textAlign(TextAlign.Start)
            Text(this.pageParam.userName.length > 0 ? this.pageParam.userName : '—')
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .layoutWeight(1)
              .textAlign(TextAlign.Start)
          }
          .width('100%')

          Row({ space: UiTheme.gapM }) {
            Text('服务端')
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textSecondary)
              .width(80)
              .textAlign(TextAlign.Start)
            Text(this.pageParam.serverLabel.length > 0 ? this.pageParam.serverLabel : '—')
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .layoutWeight(1)
              .textAlign(TextAlign.Start)
          }
          .width('100%')
        }
        .width('100%')
      }

      PlaceholderView({
        glyph: '我',
        title: '设置待实现',
        description: '这里将放服务端地址切换、数据缓存管理与登出入口。',
        hint: '下一轮：AppStore.changeServer() 与 AuthStore.logout()（后端无登出接口，登出=本地删令牌）',
        actionLabel: '下一步操作',
        onAction: () => {
          this.getUIContext().getPromptAction().showToast({ message: '本页为占位页，下一轮实现设置项' });
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
