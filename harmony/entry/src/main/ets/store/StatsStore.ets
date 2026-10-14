/**
 * StatsStore · 统计面板（`BaseStore` 子类）
 *
 * 数据来源：`GET /api/stats`
 * 离线兜底：RDB 单行快照表 `stats_cache`（整包 JSON，聚合结果不适合拆列）
 *
 * 对外暴露的字段：`data` / `buckets` / `bdiTrend` / `recentReports`
 *                 `loading` / `errorMsg` / `lastSyncAt`
 * 对外暴露的方法：`refresh` / `loadFromCache` / `warmUp` / `hasData` / `clear`
 */

import { StatsApi } from '../network/StatsApi';
import { isNetworkFailure, toApiError } from '../network/ApiError';
import { StorageManager } from '../persistence/StorageManager';
import {
  BdiTrendPointModel, Mapper, ReportListItemModel, SeverityBucketModel, StatsModel, StatsOutDto, UiConstant
} from '../types/Index';
import { BaseStore } from './BaseStore';

/** 统计面板 · 集中对外接口在顶部 */
@ObservedV2
export class StatsStore extends BaseStore {
  // ────────────────── 对外字段（UI 直接读）──────────────────

  /** 完整统计模型（null = 还没拉到过数据） */
  @Trace data: StatsModel | null = null;

  /** 严重度分布摊平后的数组（UI 的 ForEach 直接吃它） */
  @Trace buckets: SeverityBucketModel[] = [];

  @Trace loading: boolean = false;
  @Trace errorMsg: string = '';
  @Trace lastSyncAt: number = 0;

  // ────────────────── 单例 ──────────────────

  private static instance: StatsStore | null = null;

  public static get(): StatsStore {
    if (StatsStore.instance === null) {
      StatsStore.instance = new StatsStore();
    }
    return StatsStore.instance;
  }

  // ────────────────── 派生数据 ──────────────────

  /** 是否已有可渲染的数据（决定显示骨架屏还是图表） */
  public hasData(): boolean {
    return this.data !== null;
  }

  /** 分析总次数 */
  public totalAnalyses(): number {
    const current: StatsModel | null = this.data;
    return current === null ? 0 : current.totalAnalyses;
  }

  /** 媒体总数 */
  public totalMedia(): number {
    const current: StatsModel | null = this.data;
    return current === null ? 0 : current.totalMedia;
  }

  /** 平均推理耗时（毫秒） */
  public avgInferenceTimeMs(): number {
    const current: StatsModel | null = this.data;
    return current === null ? 0 : current.avgInferenceTimeMs;
  }

  /** BDI 趋势点（折线图数据源） */
  public bdiTrend(): BdiTrendPointModel[] {
    const current: StatsModel | null = this.data;
    return current === null ? [] : current.bdiTrend;
  }

  /** 最近报告（统计页底部列表） */
  public recentReports(): ReportListItemModel[] {
    const current: StatsModel | null = this.data;
    return current === null ? [] : current.recentReports;
  }

  /** 主要等级的中文标签（占比最高的那一档，统计页顶部大字用） */
  public dominantSeverityLabel(): string {
    let maxCount: number = -1;
    let label: string = '暂无数据';
    for (let i = 0; i < this.buckets.length; i++) {
      const bucket: SeverityBucketModel = this.buckets[i];
      if (bucket.count > maxCount) {
        maxCount = bucket.count;
        label = bucket.label;
      }
    }
    return label;
  }

  // ────────────────── 对外方法 ──────────────────

  /** 实现 BaseStore：从服务端拉统计并回写快照表 */
  public async refresh(): Promise<void> {
    this.beginLoad();
    try {
      const dto: StatsOutDto = await StatsApi.stats();
      this.apply(Mapper.toStats(dto));
      // 整包 JSON 存一行（聚合结构不适合拆列）
      await StorageManager.statsDao().save(JSON.stringify(dto), Date.now());
      await StorageManager.markSynced();
      this.endLoadOk();
      this.log().i(`统计已同步 · 分析 ${this.totalAnalyses()} 次 / 媒体 ${this.totalMedia()} 个`);
    } catch (err) {
      const apiErr = toApiError(err as Object);
      if (isNetworkFailure(err as Object)) {
        this.loading = false;
        this.log().w('统计同步失败（网络不可达）· 使用本地快照');
        return;
      }
      this.endLoadErr(apiErr.message);
      this.log().e('统计同步失败', err as Object);
    }
  }

  /** 从 RDB 快照读回（离线兜底 / 冷启动预热） */
  public async loadFromCache(): Promise<boolean> {
    if (!StorageManager.isRdbReady()) {
      return false;
    }
    const payload: string = await StorageManager.statsDao().loadPayload();
    if (payload.length === 0) {
      return false;
    }
    try {
      const dto: StatsOutDto = JSON.parse(payload) as StatsOutDto;
      this.apply(Mapper.toStats(dto));
      this.lastSyncAt = await StorageManager.lastSyncAt();
      this.log().i('统计已从本地快照恢复');
      return true;
    } catch (err) {
      this.log().w('本地统计快照损坏，已忽略');
      return false;
    }
  }

  /** 冷启动预热 */
  public async warmUp(): Promise<boolean> {
    return this.loadFromCache();
  }

  /** 实现 BaseStore：清空内存 */
  public clear(): void {
    this.data = null;
    this.buckets = [];
    this.loading = false;
    this.errorMsg = '';
    this.lastSyncAt = 0;
  }

  /** 实现 BaseStore */
  protected storeName(): string {
    return 'StatsStore';
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  /** 落地模型并同步摊平分布数组 */
  private apply(stats: StatsModel): void {
    this.data = stats;
    this.buckets = Mapper.toSeverityBuckets(stats.severityDistribution, stats.totalAnalyses);
  }

  /** 供 UI 直接用：把 count 转成百分比文案 */
  public ratioText(bucket: SeverityBucketModel): string {
    return `${Math.round(bucket.ratio * 100)}%`;
  }

  /** 供 UI 直接用：严重度对应颜色（兜底灰色） */
  public colorOf(severity: string): string {
    return UiConstant.severityColor(severity);
  }
}
