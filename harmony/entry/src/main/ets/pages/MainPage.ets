/**
 * MainPage · 应用主界面（**Navigation 路由容器** + 底部五个按钮）
 *
 * 结构：
 * ```
 * Navigation(this.navStack)          ← 唯一的路由栈
 *   ├─ 内容区：各页的 NavDestination（由 navDestination 分发器渲染）
 *   └─ 底部：五个自定义按钮（工作台 / 素材库 / 历史报告 / 统计 / 我的）
 * ```
 *
 * 四条实现要点：
 *  ① **一个 Navigation 一个栈**：主界面与登录流各有独立 `NavPathStack`，
 *     分支切换时旧栈自然销毁，所以不存在"返回键回到登录页"的问题。
 *  ② **页签用 `replacePathByName` 切换**：栈深恒定为 1，底部导航来回点也不会堆积历史；
 *     二级页面（素材选择 / 分析详情）用 `pushPathByName`，返回键即回到当前页签。
 *  ③ **页面参数由这里注入**：每个页的 `*PageParam` 都带上 `pathStack`（二级页还带动作回调），
 *     于是子页面既能执行"返回/下一步"，又完全不需要碰 UI 上下文 API 或 store。
 *  ④ **本文件与 `Index.ets` 是仅有的两个"窗口层"**：只有它们允许 import store、
 *     发网络请求、操作路由栈；页面组件一律只吃参数。
 *
 * ★ 参数对象全部**构造一次 + 只改字段**（`@Param` 按引用比对，
 *   每次 build 都 new 会把子树入参整体重置并触发冗余重建）。
 *
 * ★ 二级页面不随页签销毁：压入 `mediaPicker` / `analysisDetail` 时，
 *   工作台仍在栈底存活，所以从详情页返回后页签与滚动位置都还在。
 */

import { UiTheme } from '../common/UiTheme';
import { AppStore } from '../store/AppStore';
import {
  ActionResultModel, CurrentTaskModel, MediaItemModel, MediaType, PickedMediaModel,
  RecentMediaModel
} from '../types/Index';
import { UploadFileSpec } from '../network/HttpClient';
import {
  AnalysisDetailPageParam, MainPageParam, MainTab, MediaPickerPageParam, ProfilePageParam,
  TabPageParam, WorkbenchPageParam
} from '../types/PageParams';
import {
  ANALYSIS_DETAIL_ROUTE, MAIN_TABS, MEDIA_PICKER_ROUTE, mainTabGlyph, mainTabLabel, MainTabMeta
} from './PageRoutes';
import { MediaPicker, PickResult } from '../common/MediaPicker';
import { WorkbenchPage } from './WorkbenchPage';
import { MediaLibraryPage } from './MediaLibraryPage';
import { ReportsPage } from './ReportsPage';
import { StatsPage } from './StatsPage';
import { ProfilePage } from './ProfilePage';
import { MediaPickerPage } from './MediaPickerPage';
import { AnalysisDetailPage } from './AnalysisDetailPage';

/** 工作台「最近使用的素材」展示条数（用户指定两条） */
const RECENT_MEDIA_LIMIT: number = 2;

@ComponentV2
export struct MainPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: MainPageParam = new MainPageParam();

  /** 路由栈 · 主界面自己持有 */
  @Local navStack: NavPathStack = new NavPathStack();

  /** 当前选中的页签 · 由底部按钮点击时更新，并驱动高亮 */
  @Local selectedTab: MainTab = MainTab.workbench;

  /**
   * 刷新触发器 · 每个 `@Trace` 字段变化本身就会刷新 UI，
   * 但 `@Computed` 里对 `AppStore.get()` 的调用是普通静态方法，
   * 需要一个显式的整数来保证重算（工程既有页面同样写法）。
   */
  @Local tick: number = 0;

  // ── 页面参数对象（构造一次，之后只改字段）──

  private workbenchParam: WorkbenchPageParam = new WorkbenchPageParam();
  private mediaParam: TabPageParam = new TabPageParam();
  private reportsParam: TabPageParam = new TabPageParam();
  private statsParam: TabPageParam = new TabPageParam();
  private profileParam: ProfilePageParam = new ProfilePageParam();
  private pickerParam: MediaPickerPageParam = new MediaPickerPageParam();
  private detailParam: AnalysisDetailPageParam = new AnalysisDetailPageParam();

  /** 动作回调是否已挂载（只挂一次，避免每次同步都新建闭包） */
  private actionsAttached: boolean = false;

  /** 素材选择页当前选中的素材（窗口层持有，页面只读投影字段） */
  private picked: PickedMediaModel | null = null;

  // ══════════════════ 生命周期 ══════════════════

  aboutToAppear(): void {
    this.attachActions();
    // 首帧就给第一个页签入栈，避免出现"白屏但底部栏已在"的中间态
    this.pushTab(MainTab.workbench);
    // 进主界面先探一次活：服务状态圆点必须是真实结果，不是默认值
    this.refreshHealth();
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
    const param: TabPageParam = this.paramOf(tab);
    param.activeTab = tab;
    param.pathStack = stack;
    this.syncTabParam(tab, param);
    return param;
  }

  /** 取页签对应的（已缓存的）参数对象 */
  private paramOf(tab: MainTab): TabPageParam {
    if (tab === MainTab.workbench) {
      return this.workbenchParam;
    }
    if (tab === MainTab.media) {
      return this.mediaParam;
    }
    if (tab === MainTab.reports) {
      return this.reportsParam;
    }
    if (tab === MainTab.stats) {
      return this.statsParam;
    }
    return this.profileParam;
  }

  /**
   * 把 store 的实时状态投影到页签参数
   * ★ 只同步"页面真的会读"的字段：多写无用字段等于给自己增加维护面。
   */
  private syncTabParam(tab: MainTab, param: TabPageParam): void {
    const app: AppStore = AppStore.get();
    if (tab === MainTab.workbench) {
      this.syncWorkbenchParam(param as WorkbenchPageParam);
      return;
    }
    if (tab === MainTab.media) {
      param.busy = app.mediaLoading;
      param.errorMsg = app.mediaError;
      return;
    }
    if (tab === MainTab.reports) {
      param.busy = app.reportLoading;
      param.errorMsg = app.reportError;
      return;
    }
    if (tab === MainTab.stats) {
      param.busy = app.statsLoading;
      return;
    }
    // 我的页：只读展示文案
    const profile: ProfilePageParam = param as ProfilePageParam;
    profile.userName = this.pageParam.userName;
    profile.serverLabel = this.pageParam.serverLabel;
  }

  /**
   * 工作台参数投影
   *
   * ★ 工作台的**展示数据不再经参数传递** —— 它直接订阅 `AppStore`（响应式）。
   *   原因见 `WorkbenchPage` 文件头：探活与 WS 进度都是异步到达的，
   *   而经 `navDestination` 传参时，改字段不会让已挂载页面收到新值。
   *   这里只剩下"注入路由栈引用"这一件事。
   *
   * ★ 分析详情页也不再需要在这里同步：它的实时数据全部从
   *   `AppStore.analysisSessionOf(mediaId)` 读（旧 `syncDetailParam()` 已删除，
   *   那个方法只在切页签时被调用，WS 收帧不会触发，正是 BUG-15 的根因）。
   */
  private syncWorkbenchParam(param: WorkbenchPageParam): void {
    const stack: NavPathStack | null = this.navStack;
    param.pathStack = stack;
  }

  // ══════════════════ 动作实现（★ 只有本文件与 Index 允许碰 store）══════════════════

  /** 挂载所有动作回调（只挂一次） */
  private attachActions(): void {
    if (this.actionsAttached) {
      return;
    }
    this.actionsAttached = true;

    // ── 工作台 ──
    this.workbenchParam.onRefresh = () => {
      this.refreshHealth();
    };
    this.workbenchParam.onSelectMedia = () => {
      this.openMediaPicker();
    };
    this.workbenchParam.onOpenTask = () => {
      this.openCurrentTask();
    };
    this.workbenchParam.onViewAll = () => {
      this.pushTab(MainTab.reports);
    };
    this.workbenchParam.onSelectRecent = (mediaId: string) => {
      this.openRecentDetail(mediaId);
    };

    // ── 素材选择页 ──
    this.pickerParam.onBack = () => {
      this.navStack.pop();
    };
    this.pickerParam.onPickRequest = async (): Promise<boolean> => {
      return await this.pickMedia();
    };
    this.pickerParam.onUpload = async (): Promise<boolean> => {
      return await this.uploadPicked();
    };

    // ── 分析详情页 ──
    this.detailParam.onBack = () => {
      // ★ 只出栈，**不停止分析**：分析会话挂在 AppStore 上继续跑，
      //   用户回到工作台就能看到「当前任务」在推进。
      this.navStack.pop();
    };
    this.detailParam.onCancelAnalysis = () => {
      AppStore.get().cancelAnalysis();
      this.refreshUi();
    };
    /**
     * 重新分析当前页的素材
     *
     * ★ 适用场景：App 重启后打开历史素材（本机没有逐帧会话）、归档被淘汰、
     *   或上一次分析失败。重新分析会**覆盖该素材自己那一条会话**，其它素材不受影响。
     * ★ 页面不需要重新入栈：`analysisLiveMediaId === mediaId` 变真后，
     *   页面的 `@Computed` 自动切到实时数据。
     */
    this.detailParam.onReanalyze = () => {
      const param: AnalysisDetailPageParam = this.detailParam;
      if (param.mediaId.length === 0) {
        return;
      }
      const app: AppStore = AppStore.get();
      // 先登记当前任务（工作台「当前任务」卡片要能看到它），再起 WS。
      // ★ 失败也不回滚页面：`start()` 已经建好该素材的会话，
      //   连接层的错误会通过会话的 errorMsg 显示在页面里（带「重新分析」可再试）。
      app.setCurrentTask(param.mediaId, param.mediaName, param.mediaType);
      app.startAnalysis(param.mediaId);
      this.refreshUi();
    };
  }

  /** 探活 · 写回服务状态并刷新界面 */
  private refreshHealth(): void {
    AppStore.get().checkHealth()
      .then((result: ActionResultModel) => {
        this.refreshUi();
      })
      .catch(() => {
        this.refreshUi();
      });
  }

  /**
   * 打开素材选择页
   * ★ 每次进入都重置选择态：上一次选完但没上传的残留素材不应该出现在新会话里。
   */
  private openMediaPicker(): void {
    this.picked = null;
    this.pickerParam.hasPicked = false;
    this.pickerParam.pickedName = '';
    this.pickerParam.pickedUri = '';
    this.pickerParam.pickedIsVideo = false;
    this.pickerParam.uploading = false;
    this.pickerParam.errorMsg = '';
    this.navStack.pushPathByName(MEDIA_PICKER_ROUTE, this.pickerParam);
  }

  /** 打开系统选择器并把结果写进选择页参数 */
  private async pickMedia(): Promise<boolean> {
    const result: PickResult = await MediaPicker.pickOne();
    if (result.error.length > 0) {
      this.pickerParam.errorMsg = result.error;
      this.refreshUi();
      return false;
    }
    const media: PickedMediaModel | null = result.media;
    if (media === null) {
      // 用户取消：什么都不做（不弹错误）
      return false;
    }
    this.picked = media;
    this.pickerParam.hasPicked = true;
    this.pickerParam.pickedName = media.fileName;
    this.pickerParam.pickedUri = media.uri;
    this.pickerParam.pickedIsVideo = media.type === MediaType.video;
    this.pickerParam.errorMsg = '';
    this.refreshUi();
    return true;
  }

  /**
   * 上传已选素材 → 记录当前任务 → 启动 WS 分析 → 跳到分析详情页
   *
   * 顺序不能变：**先记当前任务再启动分析**，否则 WS 的第一帧可能在任务登记之前到达，
   * `syncCurrentTask()` 会因为"还没有任务"而直接返回，工作台就看不到进度。
   *
   * ★ 跳转用 `replacePathByName`（不是 `pushPathByName`）：上传成功后选择页的使命就结束了，
   *   把它**换成**详情页，栈深仍是 2 —— 用户从详情页按返回是回到工作台（计划 §3 的链路），
   *   而不是回到选择页对着同一份素材再点一次「开始分析」（那会重复上传、重复起分析）。
   */
  private async uploadPicked(): Promise<boolean> {
    const media: PickedMediaModel | null = this.picked;
    if (media === null) {
      this.pickerParam.errorMsg = '请先选择素材';
      this.refreshUi();
      return false;
    }
    // ★ 必须用沙箱副本路径上传：相册 URI 是媒体库 provider 的 URI，
    //   http 的 filePath 读不了它（会抛 2300026，看起来像"网络不可达"）。见 BUG-12。
    if (media.uploadPath.length === 0) {
      this.pickerParam.errorMsg = '无法读取所选素材，请重新选择';
      this.refreshUi();
      return false;
    }
    // 连点保护：页面侧已用 busy 挡过一次，这里再挡一次真正的重复上传
    if (this.pickerParam.uploading) {
      return false;
    }

    this.pickerParam.uploading = true;
    this.pickerParam.errorMsg = '';
    this.refreshUi();

    const spec: UploadFileSpec = {
      filePath: media.uploadPath,
      fileName: media.fileName,
      mimeType: media.mimeType
    };
    const app: AppStore = AppStore.get();
    const uploaded: MediaItemModel | null = await app.media().uploadMedia(spec);
    app.sync();
    this.pickerParam.uploading = false;

    if (uploaded === null) {
      this.pickerParam.errorMsg = app.mediaError.length > 0 ? app.mediaError : '上传失败，请重试';
      this.refreshUi();
      return false;
    }

    // ① 任务登记（先于 WS：否则第一帧可能在任务登记之前到达，工作台就看不到进度）
    app.setCurrentTask(uploaded.id, uploaded.name, uploaded.type);

    // ② 启动分析（WS）。失败也不阻断跳转 —— 详情页会把错误显示出来
    const started: ActionResultModel = app.startAnalysis(uploaded.id);
    if (!started.ok) {
      this.pickerParam.errorMsg = started.message;
    }

    // ③ 详情页参数：只写"入栈那一刻就确定"的素材元信息。
    //    ★ 实时数据（进度/分数/帧/档位/VLM）由页面自己从 AppStore 的会话读，
    //      窗口层不再抄参数（旧的 syncDetailParam 已删除，见文件头）。
    this.detailParam.mediaId = uploaded.id;
    this.detailParam.mediaName = uploaded.name;
    this.detailParam.mediaType = uploaded.type;
    this.detailParam.reportScore = 0;
    this.detailParam.reportTime = '';
    this.refreshUi();

    // ④ 选择页 → 详情页（替换，不是压栈）；选中态清掉，避免残留素材被重复上传
    this.picked = null;
    // ★ 上传是异步的：这段等待里用户可能已经按返回把选择页弹掉了（甚至切到别的页签）。
    //   栈深回到 1 说明最上层已经不是选择页，此时再 replace 会把**工作台/别的页签**换掉，
    //   所以只在"选择页仍压在上面"时才做替换。分析已经在跑，用户可以照常从
    //   工作台「当前任务」卡片进入详情页 —— 不跳转也不会丢失这次分析。
    if (this.navStack.size() > 1) {
      this.navStack.replacePathByName(ANALYSIS_DETAIL_ROUTE, this.detailParam);
    }
    return true;
  }

  /** 从工作台点「当前任务」回到分析详情页（实时数据由页面订阅 store 得到） */
  private openCurrentTask(): void {
    const task: CurrentTaskModel | null = AppStore.get().currentTask();
    if (task === null) {
      return;
    }
    this.detailParam.mediaId = task.mediaId;
    this.detailParam.mediaName = task.mediaName;
    this.detailParam.mediaType = task.mediaType;
    this.detailParam.reportScore = task.bdiScore;
    this.detailParam.reportTime = '';
    this.navStack.pushPathByName(ANALYSIS_DETAIL_ROUTE, this.detailParam);
  }

  /**
   * 从「最近使用的素材」打开某条素材的分析详情
   *
   * ★ 参数里只放**报告侧**的冻结值（分数 / 时间）+ 素材元信息；
   *   逐帧热力图与曲线由页面按 `mediaId` 去会话归档里取：
   *     · 本机跑过这条素材（会话还在）→ 直接显示它自己的帧；
   *     · 本机没有（App 重启过 / 归档被淘汰）→ 提示"本机未保留逐帧数据"，
   *       并给「重新分析」按钮（`onReanalyze`）。
   * ★ 绝不再用"当前任务"的数据顶替被点的素材 —— 那正是
   *   「点开 A 却看到 B 的热力图」的根因（BUG-14）。
   */
  private openRecentDetail(mediaId: string): void {
    const app: AppStore = AppStore.get();
    const recent: RecentMediaModel[] = app.recentMedia(RECENT_MEDIA_LIMIT);
    let hit: RecentMediaModel | null = null;
    for (let i = 0; i < recent.length; i++) {
      if (recent[i].mediaId === mediaId) {
        hit = recent[i];
        break;
      }
    }
    if (hit === null) {
      // 列表已变（例如刚被刷新掉）：退回工作台，不跳一个空页面
      this.refreshUi();
      return;
    }

    const param: AnalysisDetailPageParam = this.detailParam;
    param.mediaId = hit.mediaId;
    param.mediaName = hit.name;
    param.mediaType = hit.type;
    param.reportScore = hit.bdiScore;
    param.reportTime = hit.detectedAt;
    this.navStack.pushPathByName(ANALYSIS_DETAIL_ROUTE, param);
  }

  /** 让界面与页面参数都跟上 store 的最新状态 */
  private refreshUi(): void {
    this.tick = this.tick + 1;
    this.syncTabParam(this.selectedTab, this.paramOf(this.selectedTab));
  }

  // ══════════════════ 路由分发 ══════════════════

  /**
   * 分发器 · 按路由名渲染对应的 NavDestination
   *
   * ★ 页签分支**只按路由名判断**，不再看 `selectedTab`：
   *   因为二级页面（素材选择/分析详情）入栈时 `selectedTab` 仍是当前页签，
   *   用页签做判据会把二级页渲染成页签页（这是个很容易埋进去的 bug）。
   * ★ `param` 的静态类型在官方签名里是 `unknown`，而 ArkTS 禁止 `unknown`/`any`
   *   （`arkts-no-any-unknown`），所以这里用 ArkTS 提供的动态类型 `ESObject` 承接；
   *   每个分支仍以 `instanceof` 校验后再使用 —— 硬 `as` 会掩盖"名字与参数类型不匹配"的 bug。
   */
  @Builder
  destination(name: string, param: ESObject) {
    if (name === MEDIA_PICKER_ROUTE && param instanceof MediaPickerPageParam) {
      NavDestination() {
        MediaPickerPage({ pageParam: param as MediaPickerPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
    } else if (name === ANALYSIS_DETAIL_ROUTE && param instanceof AnalysisDetailPageParam) {
      NavDestination() {
        AnalysisDetailPage({ pageParam: param as AnalysisDetailPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
    } else if (name === MainTab.workbench && param instanceof WorkbenchPageParam) {
      NavDestination() {
        // ★ 工作台只接收**动作回调**：它的展示数据直接订阅 `AppStore`
        //   （原因见 WorkbenchPage 文件头：异步到达的数据经 navDestination 传参不可靠）
        WorkbenchPage({
          onRefresh: param.onRefresh,
          onSelectMedia: param.onSelectMedia,
          onOpenTask: param.onOpenTask,
          onViewAll: param.onViewAll,
          onSelectRecent: param.onSelectRecent
        })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
    } else if (name === MainTab.media && param instanceof TabPageParam) {
      NavDestination() {
        MediaLibraryPage({ pageParam: param as TabPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
    } else if (name === MainTab.reports && param instanceof TabPageParam) {
      NavDestination() {
        ReportsPage({ pageParam: param as TabPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
    } else if (name === MainTab.stats && param instanceof TabPageParam) {
      NavDestination() {
        StatsPage({ pageParam: param as TabPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
    } else if (name === MainTab.profile && param instanceof ProfilePageParam) {
      NavDestination() {
        ProfilePage({ pageParam: param as ProfilePageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
    }
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
          Text(mainTabLabel(this.selectedTab))
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
