/**
 * MainPage · 应用主界面（**Navigation 路由容器** + 底部五个按钮）
 *
 * 结构：
 * ```
 * Navigation(this.navStack)          ← 唯一的路由栈
 *   ├─ 内容区：各页签的 NavDestination（由 navDestination 分发器渲染）
 *   └─ 底部：五个自定义按钮（工作台 / 素材库 / 历史报告 / 统计 / 我的）
 * ```
 *
 * 三条实现要点：
 *  ① **一个 Navigation 一个栈**：主界面与登录流各有独立 `NavPathStack`，
 *     分支切换时旧栈自然销毁，所以不存在"返回键回到登录页"的问题。
 *  ② **页签用 `replacePathByName` 切换**：栈深恒定为 1，底部导航来回点也不会堆积历史；
 *     二级页面（下一轮的报告详情等）继续 `pushPathByName`，返回键即可回到当前页签。
 *  ③ **页面参数由这里注入**：每个页签的 `TabPageParam` 都带上 `pathStack`，
 *     于是子页面既能执行"返回/下一步"，又完全不需要碰 UI 上下文 API。
 *
 * ★ `hideTitleBar(true)`：标题由各页面的 `PageHeader` 自绘（22vp + 正文色），
 *   以保证完全符合设计规范。
 */

import { UiTheme } from '../common/UiTheme';
import { MainTab, MainPageParam, ProfilePageParam, TabPageParam } from '../types/PageParams';
import { MAIN_TABS, mainTabGlyph, mainTabLabel, MainTabMeta } from './PageRoutes';
import { WorkbenchPage } from './WorkbenchPage';
import { MediaLibraryPage } from './MediaLibraryPage';
import { ReportsPage } from './ReportsPage';
import { StatsPage } from './StatsPage';
import { ProfilePage } from './ProfilePage';

@ComponentV2
export struct MainPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: MainPageParam = new MainPageParam();

  /** 路由栈 · 主界面自己持有 */
  @Local navStack: NavPathStack = new NavPathStack();

  /** 当前选中的页签 · 由底部按钮点击时更新，并驱动高亮 */
  @Local selectedTab: MainTab = MainTab.workbench;

  aboutToAppear(): void {
    // 首帧就给第一个页签入栈，避免出现"白屏但底部栏已在"的中间态
    this.pushTab(MainTab.workbench);
  }

  // ══════════════════ 页签切换 ══════════════════

  /** 点页签：切换路由（栈深保持 1），并更新高亮 */
  private pushTab(tab: MainTab): void {
    this.selectedTab = tab;
    this.navStack.replacePathByName(tab as string, this.buildTabParam(tab));
  }

  /**
   * 构造页签参数 · 把当前选中的页签与导航栈注入进去
   * `pathStack` 字段声明为 `NavPathStack | null`，这里必定非空，故做一次显式收窄。
   */
  private buildTabParam(tab: MainTab): TabPageParam {
    const stack: NavPathStack | null = this.navStack;
    const param: TabPageParam = new TabPageParam();
    param.activeTab = tab;
    param.pathStack = stack;
    return param;
  }

  /** 构造"我的"页参数 · 在页签公共字段上补充只读展示文案 */
  private buildProfileParam(tab: MainTab): ProfilePageParam {
    const stack: NavPathStack | null = this.navStack;
    const param: ProfilePageParam = new ProfilePageParam();
    param.activeTab = tab;
    param.pathStack = stack;
    param.userName = this.pageParam.userName;
    param.serverLabel = this.pageParam.serverLabel;
    return param;
  }

  /** 当前页签的中文名 */
  private currentTabLabel(): string {
    return mainTabLabel(this.selectedTab);
  }

  // ══════════════════ 路由分发 ══════════════════

  /**
   * 分发器 · 按路由名渲染对应的 NavDestination
   *
   * ★ `param` 的静态类型在官方签名里是 `unknown`，而 ArkTS 禁止 `unknown`/`any`
   *   （`arkts-no-any-unknown`），所以这里用 ArkTS 提供的动态类型 `ESObject` 承接；
   *   每个分支仍以 `instanceof` 校验后再使用 —— 硬 `as` 会掩盖"名字与参数类型不匹配"的 bug。
   * ★ 五个页签用同一套参数规则，所以合并到 `renderTabDestination` 里，避免五段重复代码。
   */
  @Builder
  destination(name: string, param: ESObject) {
    if (name === 'workbench' && param instanceof TabPageParam) {
      this.renderTabDestination(param as Object)
    } else if (name === 'media' && param instanceof TabPageParam) {
      this.renderTabDestination(param as Object)
    } else if (name === 'reports' && param instanceof TabPageParam) {
      this.renderTabDestination(param as Object)
    } else if (name === 'stats' && param instanceof TabPageParam) {
      this.renderTabDestination(param as Object)
    } else if (name === 'profile' && param instanceof ProfilePageParam) {
      this.renderTabDestination(param as Object)
    }
  }

  /**
   * 页签页面的统一外壳
   * 每个分支各自实例化自己需要的参数类型（不做泛型转换，规避 ArkTS 不支持结构化类型的问题）。
   * `param` 的静态类型是 `Object`（由 `navDestination` 回调传入），
   * 上一层的 `instanceof` 已保证它在运行时的真实类型，这里只需再取回具体类型。
   */
  @Builder
  renderTabDestination(param: Object) {
    NavDestination() {
      if (param instanceof ProfilePageParam) {
        ProfilePage({ pageParam: param as ProfilePageParam })
      } else if (this.selectedTab === MainTab.media) {
        MediaLibraryPage({ pageParam: param as TabPageParam })
      } else if (this.selectedTab === MainTab.reports) {
        ReportsPage({ pageParam: param as TabPageParam })
      } else if (this.selectedTab === MainTab.stats) {
        StatsPage({ pageParam: param as TabPageParam })
      } else {
        WorkbenchPage({ pageParam: param as TabPageParam })
      }
    }
    .hideTitleBar(true)
    .backgroundColor(UiTheme.pageBackground)
  }

  // ══════════════════ 底部导航栏 ══════════════════

  @Builder
  tabBar() {
    Row() {
      ForEach(MAIN_TABS, (item: MainTabMeta) => {
        Column({ space: UiTheme.gapXs }) {
          Text(mainTabGlyph(item.tab))
            .fontSize(20)
            .fontColor(this.selectedTab === item.tab ? UiTheme.primary : UiTheme.textSecondary)

          Text(item.label)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(this.selectedTab === item.tab ? UiTheme.primary : UiTheme.textSecondary)
        }
        .layoutWeight(1)
        .height(UiTheme.tabBarHeight)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.pushTab(item.tab);
        })
      }, (item: MainTabMeta) => item.tab as string)
    }
    .width('100%')
    .height(UiTheme.tabBarHeight)
    .backgroundColor(UiTheme.cardBackground)
    .border({ width: { top: 1 }, color: UiTheme.divider })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Navigation(this.navStack) {
        // 内容区由 `navDestination` 分发器接管。`aboutToAppear` 已经压入第一个页签，
        // 所以这段根内容在正常流程中不会显示，只作为"栈意外为空"时的兜底画面。
        Column() {
          Text(this.currentTabLabel())
            .fontSize(UiTheme.fontSizeTitle)
            .fontColor(UiTheme.textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(UiTheme.pageBackground)
      }
      .navDestination(this.destination)
      .hideTitleBar(true)
      .mode(NavigationMode.Stack)
      .backgroundColor(UiTheme.pageBackground)
      .layoutWeight(1)
      .width('100%')

      this.tabBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.pageBackground)
  }
}
