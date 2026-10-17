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
 *     二级页面（本轮只剩素材选择）用 `pushPathByName`，返回键即回到当前页签。
 *  ③ **页面参数由这里注入**：每个页的 `*PageParam` 都带上 `pathStack`（二级页还带动作回调），
 *     于是子页面既能执行"返回/下一步"，又完全不需要碰 UI 上下文 API 或 store。
 *  ④ **本文件与 `Index.ets` 是仅有的两个"窗口层"**：只有它们允许 import store、
 *     发网络请求、操作路由栈；页面组件一律只吃参数。
 *     ★ 唯一例外：工作台直接读 `AppStore` 的实时会话（探活/WS 逐帧是异步到达的，
 *       经页面参数无法可靠刷新，BUG-10/11）；它仍然**只通过参数回调写动作**。
 *
 * ★ 参数对象全部**构造一次 + 只改字段**（`@Param` 按引用比对，
 *   每次 build 都 new 会把子树入参整体重置并触发冗余重建）。
 *
 * ★ 二级页面不随页签销毁：压入 `mediaPicker` 时工作台仍在栈底存活；
 *   上传完成后选择页出栈，工作台 hero 直接显示新任务的实时进度。
 *   ★ 本轮已删除独立分析详情页：分析内容全部内嵌在工作台主页里。
 */

import { bundleManager, common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { UiTheme } from '../common/UiTheme';
import { CardTransit } from '../common/CardTransit';
import { ApiConfig } from '../common/ApiConfig';
import { Logger } from '../common/Logger';
import { AppStore } from '../store/AppStore';
import {
  ActionResultModel, MediaItemModel, MediaType, PickedMediaModel, UserModel
} from '../types/Index';
import { UploadFileSpec } from '../network/HttpClient';
import {
  MainPageParam, MainTab, MediaLibraryPageParam, MediaPickerPageParam, ProfilePageParam,
  TabPageParam, WorkbenchPageParam
} from '../types/PageParams';
import {
  MAIN_TABS, MEDIA_PICKER_ROUTE, mainTabIndexOf, mainTabLabel,
  MainTabMeta
} from './PageRoutes';
import { MediaPicker, PickResult } from '../common/MediaPicker';
import { PatientNameDialog } from '../components/PatientNameDialog';
import { WorkbenchPage } from './WorkbenchPage';
import { MediaLibraryPage } from './MediaLibraryPage';
import { ReportsPage } from './ReportsPage';
import { StatsPage } from './StatsPage';
import { ProfilePage } from './ProfilePage';
import { MediaPickerPage } from './MediaPickerPage';

/**
 * 页签胶囊的高度与圆角
 *
 * ★ 高度写死、不让文字自己撑：五个胶囊必须一样高。字重差异（选中 Medium / 未选 Normal）
 *   会让行高差一点点，选中时底色块的上下边就会轻微跳动，一眼看得出来。
 * ★ 32 = 正文行高约 20 + 上下各 6 的内边距；圆角取高度一半即胶囊形（与进度条同一套取法）。
 */
const TAB_CAPSULE_HEIGHT: number = 32;
const TAB_CAPSULE_RADIUS: number = TAB_CAPSULE_HEIGHT / 2;

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
  private mediaParam: MediaLibraryPageParam = new MediaLibraryPageParam();
  private reportsParam: TabPageParam = new TabPageParam();
  private statsParam: TabPageParam = new TabPageParam();
  private profileParam: ProfilePageParam = new ProfilePageParam();
  private pickerParam: MediaPickerPageParam = new MediaPickerPageParam();

  /** 动作回调是否已挂载（只挂一次，避免每次同步都新建闭包） */
  private actionsAttached: boolean = false;

  /** 素材库动作回调是否已挂载（只挂一次） */
  private mediaActionsAttached: boolean = false;

  /** 素材选择页当前选中的素材（窗口层持有，页面只读投影字段） */
  private picked: PickedMediaModel | null = null;

  /** 素材库当前选中的素材 id（空串 = 未选中） */
  @Local selectedMediaId: string = '';

  /** 素材库删除进行中的素材 id（空串 = 无） */
  @Local deletingMediaId: string = '';

  /** 「我的」页展示的应用版本（只读一次，缓存）· 空串表示没取到 */
  private versionLabel: string = '';

  /** 转场进行中标志 · 挡住连点，避免两轮"离场→换页→入场"叠在一起 */
  private transitBusy: boolean = false;

  private readonly log = Logger.scope('MainPage');

  // ══════════════════ 生命周期 ══════════════════

  aboutToAppear(): void {
    this.attachActions();
    // 首帧就给第一个页签入栈，避免出现"白屏但底部栏已在"的中间态。
    // ★ 这里不能走 `pushTab()`：首页签与 `selectedTab` 相同，会被"同页签忽略"的判据挡掉，
    //   而且首屏不需要播转场动画。
    this.navStack.replacePathByName(
      MainTab.workbench as string, this.buildTabParam(MainTab.workbench)
    );
    // 进主界面先探一次活：服务状态圆点必须是真实结果，不是默认值
    this.refreshHealth();
  }

  // ══════════════════ 页签切换 ══════════════════

  /**
   * 点页签：发信号让**每个组件自己按序号**依次离场，等它们演完再换页；
   * 新页的组件挂载后由各自的 `onAppear` 依次入场。
   *
   * ────────────── 为什么是"发信号 + 等待"，而不是页面统一驱动动画 ──────────────
   * 每个卡片的动画都收在 `components/RevealCard.ets` 里（各自的 `@Local` 状态 + 各自的
   * `delay`），页面只负责两件事：给方向、在动画播完之后换页。
   * 这样每个组件想怎么动（平移 / 缩放 / 改内容）都自成一体，页面不参与。
   *
   * ────────────── 为什么必须等动画播完再换页（★ 实测结论）──────────────
   * `replacePathByName` 会在换页那一帧就销毁旧页（证据 `_materials/_verify/s1.jpeg`），
   * `customNavContentTransition` 也留不住它。所以"离场动画"只能发生在换页**之前**。
   */
  private pushTab(tab: MainTab): void {
    // 同一页签连点、或上一轮转场还没播完 → 忽略，避免动画叠在一起
    if (tab === this.selectedTab || this.transitBusy) {
      return;
    }

    const fromIndex: number = mainTabIndexOf(this.selectedTab as string);
    const toIndex: number = mainTabIndexOf(tab as string);
    const transit: CardTransit = CardTransit.get();

    // 往右边的页签切（下标变大）→ 组件向左离场；反之向右
    transit.dir = toIndex >= fromIndex ? -1 : 1;
    this.transitBusy = true;

    // ① 发"开始离场"信号：在树上的每个组件收到后按自己的 order 延迟启动
    transit.exitClock = transit.exitClock + 1;

    // ② 等最后一个组件演完再换页（切早了会把旧页的离场动画砍断）
    //    核对过：最后一个 order（= count-1）的位移跑 cardMs，透明度延后 0.62×cardMs 再跑
    //    0.38×cardMs，两者都收在 cardMs + stepMs×(count-1)；sequenceMs 就是它 +40ms 余量。
    //    所以这里**继续用 sequenceMs**，不在页面里另算一套时间表（两套算式迟早会漂移）。
    const leavingWait: number = CardTransit.sequenceMs(this.cardCountOf(this.selectedTab));
    setTimeout(() => {
      this.selectedTab = tab;
      this.navStack.replacePathByName(tab as string, this.buildTabParam(tab));

      // ③ 新页组件在 `onAppear` 里依次入场，这里只按同样的节奏解锁连点保护
      setTimeout(() => {
        this.transitBusy = false;
        this.refreshUi();
      }, CardTransit.sequenceMs(this.cardCountOf(tab)));
    }, leavingWait);
  }

  /**
   * 某个页签有多少个参与转场的组件
   * ★ 必须与页面里 `RevealCard({ order: ... })` 的个数一致，
   *   否则等待时间算短了会砍断最后一个组件的动画。
   */
  private cardCountOf(tab: MainTab): number {
    if (tab === MainTab.workbench) {
      return CardTransit.CARDS_WORKBENCH;
    }
    if (tab === MainTab.stats) {
      return CardTransit.CARDS_STATS;
    }
    if (tab === MainTab.profile) {
      return CardTransit.CARDS_PROFILE;
    }
    return CardTransit.CARDS_PLACEHOLDER;
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
      this.syncMediaParam();
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
    // ★ 其余账户信息直接从门面的登录态镜像取（本文件是窗口层，允许碰 store）；
    //   这些字段都必须在**页面入栈之前**写好 —— 参数类不是 @ObservedV2，
    //   挂载后再改不会刷新（BUG-11 的教训）。
    const user: UserModel | null = app.currentUser;
    profile.email = user === null ? '' : user.email;
    profile.accountId = user === null ? '' : `${user.id}`;
    profile.registeredAt = user === null ? '' : user.createdAt;
    profile.appVersion = this.readAppVersion();
  }

  /**
   * 读一次应用版本号（形如 `1.0.0(1000000)`）
   * ★ `bundleManager` 是系统能力，只在窗口层调用一次并缓存；
   *   取不到就返回空串（「我的」页会把空值渲染成 `—`，不会出现半截文案）。
   */
  private readAppVersion(): string {
    if (this.versionLabel.length > 0) {
      return this.versionLabel;
    }
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      this.versionLabel = `${info.versionName}(${info.versionCode})`;
    } catch (err) {
      this.versionLabel = '';
    }
    return this.versionLabel;
  }

  /**
   * 工作台参数投影
   *
   * ★ 工作台的**分析展示数据不再经参数传递** —— 它直接订阅 `AppStore` 的 `@Trace`
   *   会话（原因见 `WorkbenchPage` 文件头：探活与 WS 逐帧都是异步到达的）。
   *   这里只剩下"注入路由栈引用"这一件事。
   *
   * ★ scrollTopTick / refreshing 不在这里同步：它们是用户动作触发的（上传完成、点刷新），
   *   由 `uploadPicked` / `refreshWorkbench` 直接写，页面经 @ObservedV2 + @Trace
   *   收到变更，不依赖切页签时的参数投影。
   */
  private syncWorkbenchParam(param: WorkbenchPageParam): void {
    const stack: NavPathStack | null = this.navStack;
    param.pathStack = stack;
  }

  // ══════════════════ 素材库页参数与动作（患者命名）══════════════════

  /**
   * 把 store 的实时状态写进素材库页参数（数据字段 + 动作回调）
   * 回调只挂一次，数据字段每次刷新都改写。
   */
  private syncMediaParam(): void {
    const param: MediaLibraryPageParam = this.mediaParam;
    if (!this.mediaActionsAttached) {
      this.mediaActionsAttached = true;
      this.attachMediaActions(param);
    }
    const app: AppStore = AppStore.get();
    param.activeTab = MainTab.media;
    param.pathStack = this.navStack;
    param.busy = app.mediaLoading;
    param.errorMsg = app.mediaError;
    param.videos = this.collectMedia(MediaType.video);
    param.images = this.collectMedia(MediaType.image);
    param.patients = app.patientOptions();
    param.selectedPatient = app.patientFilter();
    param.selectedMediaId = this.selectedMediaId;
    param.analyzing = app.analyzing;
  }

  /** 从门面取某类型的素材列表（已按患者筛选，并解析 URL 后返回新数组） */
  private collectMedia(type: MediaType): MediaItemModel[] {
    const out: MediaItemModel[] = [];
    const items: MediaItemModel[] = AppStore.get().filteredMediaItems(type);
    for (let i = 0; i < items.length; i++) {
      const src: MediaItemModel = items[i];
      // 复制一份并把相对路径解析成绝对地址，页面拿到即可直接喂给 Image
      const item: MediaItemModel = {
        id: src.id,
        name: src.name,
        type: src.type,
        thumbnailUrl: ApiConfig.resolveMediaUrl(src.thumbnailUrl),
        url: ApiConfig.resolveMediaUrl(src.url),
        duration: src.duration,
        createdAt: src.createdAt,
        patient: src.patient
      };
      out.push(item);
    }
    return out;
  }

  /** 挂载素材库页的动作回调（只执行一次） */
  private attachMediaActions(param: MediaLibraryPageParam): void {
    param.onUpload = (): void => {
      this.startUploadFlow();
    };
    param.onOpenMedia = (mediaId: string): void => {
      this.openMedia(mediaId);
    };
    param.onDelete = (mediaId: string): void => {
      this.confirmDeleteMedia(mediaId);
    };
    param.onRetry = (): void => {
      this.retryLoadMedia();
    };
    param.onSelectPatient = (patient: string): void => {
      this.selectPatient(patient);
    };
    param.onRename = (mediaId: string): void => {
      this.startRenameFlow(mediaId);
    };
  }

  /** 切换患者筛选 */
  private selectPatient(patient: string): void {
    AppStore.get().setPatientFilter(patient);
    this.refreshAfterAction();
  }

  /**
   * 上传流程：先弹患者命名输入框（可跳过），再调起相册选择器。
   * 选完文件后带上患者名一起上传。
   */
  private startUploadFlow(): void {
    this.promptPatientName('', '为素材命名所属患者', (patient: string) => {
      this.pickAndUpload(patient);
    });
  }

  /** 重命名流程：弹输入框回填当前患者名，确认后调 renamePatient */
  private startRenameFlow(mediaId: string): void {
    const item: MediaItemModel | null = AppStore.get().findMedia(mediaId);
    const current: string = item === null ? '' : item.patient;
    this.promptPatientName(current, '修改素材所属患者', async (patient: string) => {
      const res: ActionResultModel = await AppStore.get().renamePatient(mediaId, patient);
      this.refreshAfterAction();
      this.toast(res.message);
    });
  }

  /** 弹患者名输入框（自定义对话框） */
  private promptPatientName(initial: string, title: string, onConfirm: (patient: string) => void): void {
    const ctrl: CustomDialogController = new CustomDialogController({
      builder: PatientNameDialog({
        title: title,
        initial: initial,
        onConfirm: onConfirm
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    ctrl.open();
  }

  /** 上传：调起系统相册选择器，选中后带上患者名走 MediaStore 上传 */
  private async pickAndUpload(patient: string): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      const uris: string[] = result.photoUris;
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      const file: UploadFileSpec = this.buildUploadSpec(uri);
      const res: ActionResultModel = patient.length > 0
        ? await AppStore.get().media().uploadImageWithPatient(file, patient)
        : await AppStore.get().media().uploadImage(file);
      this.refreshAfterAction();
      this.toast(res.message);
    } catch (err) {
      this.log.e('选择或上传素材失败', err as Object);
      this.refreshAfterAction();
      this.toast('上传失败，请重试');
    }
  }

  /** 从相册 URI 构造上传文件描述（copy 到沙箱后再传，规避跨应用访问权限） */
  private buildUploadSpec(uri: string): UploadFileSpec {
    let filePath: string = uri;
    let fileName: string = 'upload.jpg';
    let mimeType: string = 'image/jpeg';
    try {
      const context: Context = this.getUIContext().getHostContext() as Context;
      const source: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const namePart: string = this.extractName(uri);
      fileName = namePart.length > 0 ? namePart : 'upload.jpg';
      mimeType = this.inferMime(namePart);
      const destPath: string = `${(context as common.UIAbilityContext).cacheDir}/${fileName}`;
      const dest: fileIo.File = fileIo.openSync(
        destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      const stat: fileIo.Stat = fileIo.statSync(source.fd);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(source.fd, buf);
      fileIo.writeSync(dest.fd, buf);
      fileIo.closeSync(source);
      fileIo.closeSync(dest);
      filePath = destPath;
    } catch (err) {
      this.log.e('复制上传文件到沙箱失败，退回原始 URI', err as Object);
    }
    const spec: UploadFileSpec = {
      filePath: filePath,
      fileName: fileName,
      mimeType: mimeType
    };
    return spec;
  }

  /** 从 URI 里抽取文件名（取最后一段，去掉查询串） */
  private extractName(uri: string): string {
    const clean: string = uri.split('?')[0];
    const parts: string[] = clean.split('/');
    return parts.length > 0 ? parts[parts.length - 1] : '';
  }

  /** 按扩展名推断 MIME */
  private inferMime(name: string): string {
    const lower: string = name.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    return 'image/jpeg';
  }

  /** 打开素材 · 触发分析（跳转目标后续再接） */
  private openMedia(mediaId: string): void {
    this.selectedMediaId = mediaId;
    AppStore.get().startAnalysis(mediaId);
    this.refreshAfterAction();
  }

  /** 删除素材 · 二次确认后调 MediaStore.deleteMedia */
  private confirmDeleteMedia(mediaId: string): void {
    if (this.deletingMediaId.length > 0) {
      return;
    }
    const item: MediaItemModel | null = AppStore.get().findMedia(mediaId);
    const name: string = item === null ? '该素材' : item.name;
    this.getUIContext().showAlertDialog({
      title: '删除素材',
      message: `确定删除「${name}」吗？删除后不可恢复。`,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: UiTheme.danger,
        action: (): void => {
          this.doDeleteMedia(mediaId);
        }
      }
    });
  }

  /** 执行删除 */
  private async doDeleteMedia(mediaId: string): Promise<void> {
    this.deletingMediaId = mediaId;
    try {
      const res: ActionResultModel = await AppStore.get().media().deleteMedia(mediaId);
      this.refreshAfterAction();
      this.toast(res.message);
    } catch (err) {
      this.log.e('删除素材失败', err as Object);
      this.refreshAfterAction();
      this.toast('删除失败，请重试');
    } finally {
      this.deletingMediaId = '';
    }
  }

  /** 重试加载素材 */
  private async retryLoadMedia(): Promise<void> {
    await AppStore.get().refreshMedia();
    this.refreshAfterAction();
  }

  /** 素材库动作收尾统一：tick + 同步素材库参数 */
  private refreshAfterAction(): void {
    this.tick = this.tick + 1;
    this.syncMediaParam();
  }

  /** 轻提示 */
  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
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
      this.refreshWorkbench();
    };
    this.workbenchParam.onSelectMedia = () => {
      this.openMediaPicker();
    };
    // 重新分析：先登记当前任务再起 WS；会话变 live 后工作台自动切到实时数据
    this.workbenchParam.onReanalyze = (mediaId: string, mediaName: string, mediaType: MediaType) => {
      this.reanalyzeMedia(mediaId, mediaName, mediaType);
    };
    this.workbenchParam.onCancelAnalysis = () => {
      AppStore.get().cancelAnalysis();
      this.refreshUi();
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

    // ── 我的页 ──
    /**
     * 退出登录
     *
     * ★ 真正的登出动作放在 `Index`（见 `MainPageParam.onLogout` 的注释）：
     *   它除了清登录态，还要把**登录流的栈**复位到登录页 ——
     *   否则用户注册过（栈里压着注册页）时，退出后会落在注册页上。
     *   本页只做转发，不自己调 `AuthStore.logout()`。
     */
    this.profileParam.onLogout = async (): Promise<void> => {
      await this.pageParam.onLogout();
    };
  }

  /** 探活 · 写回服务状态并刷新界面 */
  private refreshHealth(): void {
    AppStore.get().checkHealth()
      .then(() => {
        this.refreshUi();
      })
      .catch(() => {
        this.refreshUi();
      });
  }

  /**
   * 工作台刷新 · 探活 + 统计/报告/媒体全量刷新
   *
   * 工作台现在同时展示概览与最新评估（当前任务或报告回退），只探活会让页面数据陈旧；
   * 所以按钮的语义升级为"刷新主页数据"。`refreshing` 写进页面参数，
   * 页头按钮与离线横幅的「重试」共用同一个忙碌态。
   * ★ 顺序：先探活（决定离线横幅），再并行拉数据；任一失败由各 store 自己兜底，
   *   这里只负责在结束时把忙碌态复位。
   */
  private refreshWorkbench(): void {
    const app: AppStore = AppStore.get();
    this.workbenchParam.refreshing = true;
    this.refreshUi();

    app.checkHealth()
      .then((): Promise<void[]> => {
        const tasks: Promise<void>[] = [
          app.refreshStats(),
          app.refreshReports(),
          app.refreshMedia()
        ];
        return Promise.all(tasks);
      })
      .then(() => {
        this.workbenchParam.refreshing = false;
        this.refreshUi();
      })
      .catch(() => {
        this.workbenchParam.refreshing = false;
        this.refreshUi();
      });
  }

  /**
   * 重新分析一条素材
   *
   * ★ 适用场景：App 重启后打开历史素材（本机没有逐帧会话）、归档被淘汰、
   *   或上一次分析失败。重新分析会**覆盖该素材自己那一条会话**，其它素材不受影响。
   * ★ 先登记当前任务再起 WS：工作台 hero 的「当前任务」与阶段轨要立刻看到它；
   *   `start()` 成功后会建好该素材的会话，页面按会话自动切到实时数据。
   */
  private reanalyzeMedia(mediaId: string, mediaName: string, mediaType: MediaType): void {
    if (mediaId.length === 0) {
      return;
    }
    const app: AppStore = AppStore.get();
    app.setCurrentTask(mediaId, mediaName, mediaType);
    app.startAnalysis(mediaId);
    this.refreshUi();
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
   * 上传已选素材 → 记录当前任务 → 启动 WS 分析 → **出栈回工作台**
   *
   * 顺序不能变：**先记当前任务再启动分析**，否则 WS 的第一帧可能在任务登记之前到达，
   * `syncCurrentTask()` 会因为"还没有任务"而直接返回，工作台就看不到进度。
   *
   * ★ 本轮（主页重构）不再跳转分析详情页：选择页的使命结束后直接 `pop()` 回工作台，
   *   工作台 hero 立刻显示新任务的实时进度。这样"上传 → 看到分析"只隔一次出栈，
   *   用户也不会落在一个需要再按返回的详情页上。
   * ★ 出栈前先清空工作台 focus：否则上一次固定在历史素材上的查看目标会挡住新任务。
   * ★ 栈深回到 1 时（用户已按返回）不再 pop，避免误弹工作台/别的页签。
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

    // ② 启动分析（WS）。失败也不阻断返回 —— 工作台 hero 会把错误显示出来
    //    （带「重新分析该素材」出口）；选择页仍会先把错误写进参数。
    const started: ActionResultModel = app.startAnalysis(uploaded.id);
    if (!started.ok) {
      this.pickerParam.errorMsg = started.message;
    }

    // ③ 新任务的 hero 在页面顶部：递增回顶信号，出栈后工作台自动滚回顶部
    this.workbenchParam.scrollTopTick = this.workbenchParam.scrollTopTick + 1;
    this.refreshUi();

    // ④ 选择页使命结束：出栈回工作台（不再有独立分析详情页）
    //    选中态清掉，避免残留素材被重复上传。
    this.picked = null;
    // ★ 上传是异步的：这段等待里用户可能已经按返回把选择页弹掉了（甚至切到别的页签）。
    //   栈深回到 1 说明最上层已经不是选择页，此时再 pop 会把**工作台/别的页签**弹掉，
    //   所以只在"选择页仍压在上面"时才出栈。分析已经在跑，用户回到工作台照样能看到进度。
    if (this.navStack.size() > 1) {
      this.navStack.pop();
    }
    return true;
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
   *   因为二级页面（本轮只剩素材选择）入栈时 `selectedTab` 仍是当前页签，
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
    } else if (name === MainTab.workbench && param instanceof WorkbenchPageParam) {
      NavDestination() {
        // ★ 工作台接收**整个参数对象**：动作回调之外，参数里还承载 scrollTopTick/refreshing
        //   这些"挂载后仍会变化"的字段（@ObservedV2 + @Trace，见 WorkbenchPageParam）。
        //   展示数据仍由页面直接订阅 `AppStore`（异步逐帧到达，传参无法可靠刷新）。
        WorkbenchPage({ pageParam: param as WorkbenchPageParam })
      }
      .hideTitleBar(true)
      .backgroundColor(UiTheme.pageBackground)
    } else if (name === MainTab.media && param instanceof MediaLibraryPageParam) {
      NavDestination() {
        MediaLibraryPage({ pageParam: param as MediaLibraryPageParam })
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

  /**
   * 底部页签栏 · **纯文字 + 选中胶囊底**
   *
   * ★ 这里刻意**不再渲染** `mainTabGlyph(item.tab)`：`MainTabMeta.glyph` 只是一个汉字
   *   （析/库/报/统/我），摆在图标位就成了"单字图标"——真机上读起来像乱码或被截断的标签，
   *   用户已按截图判定为视觉缺陷。`PageRoutes` 的 `glyph` 字段与 `mainTabGlyph()` 保留不动
   *   （路由元数据仍可能被别处按名字取用），本栏只是不再消费它。
   *
   * ★ 选中态改用胶囊底表达：未选中只有 textSecondary 文字、无底色；选中是薄荷绿胶囊
   *   （`cardPressTint`）+ 主色文字 + Medium 字重。胶囊随文字宽度，在各自的等分槽里居中。
   */
  @Builder
  tabBar() {
    Row() {
      ForEach(MAIN_TABS, (item: MainTabMeta) => {
        // 槽本身负责"等分 + 居中 + 点击"：胶囊只有文字那么宽，点击区却仍是整槽，好按
        Row() {
          Text(item.label)
            .fontSize(UiTheme.fontSizeBody)
            .fontWeight(this.selectedTab === item.tab ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.selectedTab === item.tab ? UiTheme.primary : UiTheme.textSecondary)
            .maxLines(1)
            .height(TAB_CAPSULE_HEIGHT)
            // ★ 左右内边距取 gapS(8) 而不是更宽的档位：五个页签是等分槽，
            //   "历史报告"四个字在 14fp 下已占约 56vp，槽宽只有屏宽/5，
            //   再宽的内边距会把字挤出槽外（ArkUI 会按槽宽回夹，字就被截断）。
            .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
            .borderRadius(TAB_CAPSULE_RADIUS)
            // 未选中给全透明而不是"不设底色"：两态共用一条属性链，builder 里不必写 if/else
            .backgroundColor(this.selectedTab === item.tab ? UiTheme.cardPressTint : Color.Transparent)
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .height(UiTheme.tabBarHeight)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
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
