/**
 * BaseStore · store 层基础类（用户硬性要求的 `base...` 基础类之一，见交接文档第 5.3 节）
 *
 * 统一提供：`loading` / `errorMsg` / `lastSyncAt` / `refresh()` / `clear()`，
 * 子类命名 `XxxStore`（AuthStore / MediaStore / ReportStore / StatsStore）。
 *
 * ★ ArkTS 响应式规则（docs/鸿蒙端网络层与类型共享方案.md 第 1.5 节）：
 *   普通 class 的字段变化**不会**刷新 UI，只有 `@ObservedV2` 类上的 `@Trace` 字段才会。
 *   而**继承来的 `@Trace` 成员在 ArkTS 里行为不确定**，所以本类的字段
 *   **刻意不加 `@Trace`**，各子类一律用 `@ObservedV2` + 显式重新声明的 `@Trace`
 *   覆盖父类字段。这样「会被 UI 读的字段」在每个子类的顶部一目了然，
 *   也符合用户「对外暴露的接口尽量集中」的要求。
 */

import { Logger, ScopedLogger } from '../common/Logger';

/** store 层基础类 · 集中对外接口在顶部 */
export abstract class BaseStore {
  /** 是否正在加载（子类用 @Trace 重新声明后即可驱动 UI） */
  public loading: boolean = false;

  /** 最近一次错误文案（空串表示无错） */
  public errorMsg: string = '';

  /** 最近一次成功同步时间（毫秒时间戳）· 0 表示从未同步 */
  public lastSyncAt: number = 0;

  /** 子类名 · 用于日志前缀 */
  protected abstract storeName(): string;

  /** 从服务端刷新本 store 的数据 */
  public abstract refresh(): Promise<void>;

  /** 清空本 store 的内存状态（登出 / 重置时调用） */
  public abstract clear(): void;

  // ────────────────── 供子类复用的受保护动作 ──────────────────

  /** 作用域日志器 */
  protected log(): ScopedLogger {
    return Logger.scope(this.storeName());
  }

  /** 标记开始加载 */
  protected beginLoad(): void {
    this.loading = true;
    this.errorMsg = '';
  }

  /** 标记加载完成（成功 · 刷新同步时间） */
  protected endLoadOk(): void {
    this.loading = false;
    this.errorMsg = '';
    this.lastSyncAt = Date.now();
  }

  /**
   * 标记加载失败
   * @param message 已本地化好的用户可读文案
   */
  protected endLoadErr(message: string): void {
    this.loading = false;
    this.errorMsg = message;
  }

  /** 是否曾经同步过（用来决定显示骨架屏还是「暂无数据」） */
  public hasSynced(): boolean {
    return this.lastSyncAt > 0;
  }
}
