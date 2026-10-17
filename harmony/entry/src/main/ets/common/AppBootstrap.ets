/**
 * AppBootstrap · 生命周期引导 · **唯一对外启动入口**
 *
 * 本轮核心目标（docs/本轮开发交接.md 第一节第 1 条）：
 *   「在 Ability 生命周期最开始，直接从服务器获取数据，并启动数据存储类，不含任何 UI 内容。」
 *
 * 时序（交接文档第六节）：
 * ```
 * EntryAbility.onCreate
 *   └─ AppBootstrap.start(context)            ← 不 await 阻塞 UI 线程，内部自管
 *        ① StorageManager.init(context)       preferences + RDB 建表
 *        ② ApiConfig.load(context)            读回 host/port/token
 *        ③ 冷启动预热：从 RDB 把上次快照灌进内存 store（UI 立刻有数据）
 *        ④ 若 token 非空 → AuthApi.me() 校验
 *        ⑤ 校验通过 → 并发拉取 media / reports / stats，写内存 store + 回写 RDB
 *        ⑥ 失败/无 token → store 标记未登录或离线，UI 照常渲染（不崩、不白屏）
 * ```
 *
 * ★ `onCreate` 里**不能 await 长任务**（会拖慢首帧），所以 `start()` 返回 `void`，
 *   内部用 Promise 自跑，并暴露 `AppBootstrap.ready` 供 UI 侧按需等待。
 *
 * ★ 本文件**不含任何 UI 内容**：不 import ArkUI、不操作 windowStage、不做路由跳转。
 *   页面该显示什么，由 UI 读 `AppStore.get().bootPhase` 自行决定。
 */

import { AppStore } from '../store/AppStore';
import { StorageManager } from '../persistence/StorageManager';
import { ApiConfig } from './ApiConfig';
import { Logger } from './Logger';
import { MediaPicker } from './MediaPicker';

/** 应用启动引导 · 集中对外接口在顶部 */
export class AppBootstrap {
  /** 引导是否已完成（含「无登录态」这种正常完成） */
  private static started: boolean = false;
  private static done: boolean = false;
  /** 引导 Promise · UI 可 `await AppBootstrap.ready` 后再渲染重内容 */
  private static readyPromise: Promise<void> = Promise.resolve();
  private static readonly log = Logger.scope('Bootstrap');

  // ────────────────── 对外接口 ──────────────────

  /**
   * 启动引导 · 在 `EntryAbility.onCreate` 里调用，**返回 void、不阻塞首帧**
   * 可重复调用（幂等），第二次直接返回。
   */
  public static start(context: Context): void {
    if (AppBootstrap.started) {
      AppBootstrap.log.i('引导已在进行或已完成，忽略重复调用');
      return;
    }
    AppBootstrap.started = true;
    AppBootstrap.readyPromise = AppBootstrap.run(context);
    AppBootstrap.readyPromise.then(() => {
      AppBootstrap.done = true;
      AppBootstrap.log.i('引导流程结束');
    }).catch((err: Object) => {
      // 引导失败不能崩应用：UI 会看到 bootPhase 停在 preparing，自行决定降级展示
      AppBootstrap.log.e('引导流程异常终止', err);
    });
  }

  /**
   * 引导完成信号 · UI 侧按需等待
   * ```ts
   * aboutToAppear(): void { AppBootstrap.ready.then(() => { /* 数据已就绪 *\/ }); }
   * ```
   */
  public static get ready(): Promise<void> {
    return AppBootstrap.readyPromise;
  }

  /** 是否已引导完成 */
  public static isDone(): boolean {
    return AppBootstrap.done;
  }

  /**
   * 应用退出时的收尾（`EntryAbility.onDestroy` 调用）
   * 关掉 WS 与 RDB，避免句柄泄漏。
   */
  public static async shutdown(): Promise<void> {
    try {
      AppStore.get().stopAnalysis();
      await StorageManager.close();
      AppBootstrap.log.i('已释放 WS 与 RDB');
    } catch (err) {
      AppBootstrap.log.e('收尾失败', err as Object);
    }
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  private static async run(context: Context): Promise<void> {
    AppBootstrap.log.i('=== 引导开始 ===');

    // ⓪ 把上下文交给需要系统能力的基础设施
    //    ★ 相册选完的文件必须复制进应用沙箱才能上传（见 MediaPicker.stageToCache 与 BUG-12），
    //      而算沙箱路径需要 context.cacheDir —— 所以启动时注入一次。
    MediaPicker.attachContext(context);

    // ① + ② 存储层初始化（内部会打开 preferences、绑定 ApiConfig 并读回 host/port/token）
    const storageOk: boolean = await StorageManager.init(context);
    AppBootstrap.log.i(`存储层 ${storageOk ? '就绪' : '降级（仅在线能力）'} · ${ApiConfig.baseUrl()}`);

    // ③ ~ ⑥ 全部交给 AppStore 编排：预热 → 校验令牌 → 并发拉取 → 标记阶段
    await AppStore.get().boot();

    AppBootstrap.log.i('=== 引导完成 ===');
  }
}
