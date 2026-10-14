/**
 * Index 页 · **数据层对接示例页**（不是本轮交付的正式 UI）
 *
 * 本页的唯一目的是「把这轮建好的数据层真正跑起来」，因此刻意保持极简：
 *  - 只读 `AppStore` 门面的 `@Trace` 字段，不自己发请求、不自己解析 JSON；
 *  - 展示启动阶段、登录态、媒体/报告/统计三类数据的实时条数；
 *  - 提供「刷新」「探活」两个按钮，方便肉眼确认链路是否通。
 *
 * ★ 写 UI 的合作者可以直接把本页当作模板：
 *   凡是取数，一律 `AppStore.get().xxx`；凡是改数据，一律调门面/领域 store 的方法，
 *   然后在 `await` 之后调用一次 `AppStore.get().sync()`（或用本页这种整体重取的方式）。
 *   详细接口清单见 docs/鸿蒙端数据获取使用指南.md。
 *
 * ★ ArkTS 响应式要点：`@ObservedV2` + `@Trace` 的类，必须在 `@ComponentV2` 组件里
 *   用 `@Computed` 取它的字段才会自动重建（`@Computed` 不允许出现在 `@Component` 里）；
 *   **普通 class 的字段变化不会刷新 UI**。
 */

import { AppBootstrap } from '../common/AppBootstrap';
import { AppStore } from '../store/AppStore';
import { BootPhase, UiConstant } from '../types/Index';

@Entry
@ComponentV2
struct Index {
  /**
   * 刷新触发器 · 门面状态变化后 +1
   * ★ 它在 `@Computed` 里被读取，因此计数器变化一定会让下面的 getter 失效重算；
   *   而 `@Computed` 内部又读了 `AppStore` 的 `@Trace` 字段，两者共同保证界面是新的。
   *   （V2 页面最容易踩的坑：只写 `@Local` 却没有任何地方读它，界面永远不动。）
   */
  @Local tick: number = 0;

  @Computed
  get app(): AppStore {
    // 读取 tick 建立依赖，再取单例返回
    this.tick;
    return AppStore.get();
  }

  @Computed
  get bootPhaseText(): string {
    const phase: BootPhase = this.app.bootPhase;
    if (phase === BootPhase.idle) {
      return '未启动';
    }
    if (phase === BootPhase.preparing) {
      return '初始化中…';
    }
    return phase === BootPhase.authenticated ? '已登录' : '未登录';
  }

  aboutToAppear(): void {
    // 引导流程在 EntryAbility.onCreate 里已经点火，这里只等它结束再刷新一次界面
    AppBootstrap.ready.then(() => {
      AppStore.get().sync();
      this.tick = this.tick + 1;
    });
  }

  build() {
    Column({ space: 12 }) {
      Text('MindScope 数据层').fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor(UiConstant.textPrimaryColor)

      // ── 启动与会话状态 ──
      this.statusRow('启动阶段', this.bootPhaseText)
      this.statusRow('服务端', `${this.app.serverHost}:${this.app.serverPort}`)
      this.statusRow('网络', this.app.offline ? '离线兜底' : '在线')
      this.statusRow('当前用户', this.app.username().length > 0 ? this.app.username() : '—')

      Divider().margin({ top: 6, bottom: 6 })

      // ── 三类业务数据的实时条数（真数据，不是占位）──
      this.countRow('媒体库', `${this.app.mediaItems.length} 条`, this.app.mediaLoading, this.app.mediaError)
      this.countRow('报告列表', `${this.app.reportTotal} 条`, this.app.reportLoading, this.app.reportError)
      this.countRow('统计·分析次数',
        `${this.app.statsSummary === null ? 0 : this.app.statsSummary.totalAnalyses} 次`,
        this.app.statsLoading, '')

      // ── 全局提示（401 等）──
      if (this.app.globalMessage.length > 0) {
        Text(this.app.globalMessage).fontSize(13).fontColor(UiConstant.errorColor)
      }

      Divider().margin({ top: 6, bottom: 6 })

      Row({ space: 10 }) {
        Button('刷新全部')
          .onClick(() => {
            AppStore.get().loadAll().then(() => {
              this.tick = this.tick + 1;
            });
          })
        Button('探活')
          .backgroundColor('#64748b')
          .onClick(() => {
            AppStore.get().checkHealth().then((result) => {
              AppStore.get().globalMessage = result.message;
              this.tick = this.tick + 1;
            });
          })
      }
      .width('100%')

      Text('本页仅为数据层对接示例，正式 UI 由界面合作者实现')
        .fontSize(11).fontColor(UiConstant.textSecondaryColor).margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  /** 一行 key-value 状态 */
  @Builder
  statusRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor(UiConstant.textSecondaryColor).width(100)
      Text(value).fontSize(14).fontColor(UiConstant.textPrimaryColor).layoutWeight(1)
    }
    .width('100%')
  }

  /** 一行带加载/错误态的数据计数 */
  @Builder
  countRow(label: string, value: string, loading: boolean, errorMsg: string) {
    Column({ space: 2 }) {
      Row() {
        Text(label).fontSize(15).fontColor(UiConstant.textSecondaryColor).width(100)
        Text(loading ? '加载中…' : value).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(UiConstant.textPrimaryColor).layoutWeight(1)
      }
      .width('100%')

      if (errorMsg.length > 0) {
        Text(errorMsg).fontSize(12).fontColor(UiConstant.errorColor)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
