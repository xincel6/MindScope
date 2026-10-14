/**
 * ReportStore · 报告列表（筛选 + 分页，`BaseStore` 子类）
 *
 * 对应接口：
 *  - `GET /api/reports?severity&media_type&page&limit` → `{items, total}`（列表页/统计页）
 *  - `GET /api/report/{media_id}` → `ReportOut[]`（详情页，path 参数是 **int**）
 *
 * 离线兜底：RDB 镜像表 `diagnosis_report`，筛选与分页都能 1:1 承接。
 *
 * 对外暴露的字段：`items` / `total` / `page` / `pageSize` / `hasMore` / `detailItems`
 *                 `severityFilter` / `mediaTypeFilter` / `loading` / `loadingMore`
 *                 `errorMsg` / `lastSyncAt`
 * 对外暴露的方法：`refresh` / `loadMore` / `applyFilter` / `resetFilter` / `loadDetail`
 *                 `loadFromCache` / `warmUp` / `clear`
 */

import { ReportApi } from '../network/ReportApi';
import { isNetworkFailure, toApiError } from '../network/ApiError';
import { StorageManager } from '../persistence/StorageManager';
import {
  ActionResultModel, DiagnosisReportModel, Mapper, MediaType, ReportFilterModel, ReportListItemDto,
  ReportListItemModel, ReportListOutDto, ReportOutDto, UiConstant
} from '../types/Index';
import { BaseStore } from './BaseStore';

/** 报告列表 · 集中对外接口在顶部 */
@ObservedV2
export class ReportStore extends BaseStore {
  // ────────────────── 对外字段（UI 直接读）──────────────────

  /** 当前页的报告列表 */
  @Trace items: ReportListItemModel[] = [];

  /** 满足筛选条件的总条数（服务端 total） */
  @Trace total: number = 0;

  /** 当前页码（从 1 开始） */
  @Trace page: number = 1;

  /** 每页条数 */
  @Trace pageSize: number = UiConstant.defaultPageSize;

  /** 是否还有下一页 */
  @Trace hasMore: boolean = false;

  /** 详情页数据（按媒体查报告） */
  @Trace detailItems: DiagnosisReportModel[] = [];

  /** 严重度筛选（空串 = 全部） */
  @Trace severityFilter: string = '';

  /** 媒体类型筛选（空串 = 全部） */
  @Trace mediaTypeFilter: string = '';

  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace errorMsg: string = '';
  @Trace lastSyncAt: number = 0;

  // ────────────────── 单例 ──────────────────

  private static instance: ReportStore | null = null;

  public static get(): ReportStore {
    if (ReportStore.instance === null) {
      ReportStore.instance = new ReportStore();
    }
    return ReportStore.instance;
  }

  // ────────────────── 派生数据 ──────────────────

  /** 是否处于筛选态（UI 决定是否显示「清除筛选」按钮） */
  public isFiltered(): boolean {
    return this.severityFilter.length > 0 || this.mediaTypeFilter.length > 0;
  }

  /** 当前筛选条件的可读描述 */
  public filterSummary(): string {
    if (!this.isFiltered()) {
      return '全部报告';
    }
    const parts: string[] = [];
    if (this.severityFilter.length > 0) {
      parts.push(UiConstant.severityLabel(this.severityFilter));
    }
    if (this.mediaTypeFilter.length > 0) {
      parts.push(UiConstant.mediaTypeLabel(this.mediaTypeFilter));
    }
    return parts.join(' · ');
  }

  /** 空态文案 */
  public emptyHint(): string {
    if (this.loading) {
      return '加载中…';
    }
    if (this.isFiltered()) {
      return '当前筛选条件下没有报告';
    }
    return '还没有分析报告，去分析一段视频吧';
  }

  /** 构造给网络层的查询参数 */
  public buildFilter(): ReportFilterModel {
    const filter: ReportFilterModel = {
      severity: this.severityFilter,
      mediaType: this.mediaTypeFilter,
      page: this.page,
      pageSize: this.pageSize
    };
    return filter;
  }

  // ────────────────── 对外方法 ──────────────────

  /**
   * 实现 BaseStore：按当前筛选条件**重置到第 1 页**并拉取
   * 首次进入列表页、下拉刷新、切换筛选都走它。
   */
  public async refresh(): Promise<void> {
    this.page = 1;
    this.beginLoad();
    await this.loadPage(1, false);
  }

  /** 加载下一页并**追加**（上拉加载更多） */
  public async loadMore(): Promise<void> {
    if (!this.hasMore || this.loading || this.loadingMore) {
      return;
    }
    this.loadingMore = true;
    await this.loadPage(this.page + 1, true);
    this.loadingMore = false;
  }

  /**
   * 应用筛选条件并重新拉取
   * @param severity 空串 = 全部
   * @param mediaType 空串 = 全部
   */
  public async applyFilter(severity: string, mediaType: string): Promise<void> {
    this.severityFilter = severity;
    this.mediaTypeFilter = mediaType;
    await this.refresh();
  }

  /** 清除筛选并重新拉取 */
  public async resetFilter(): Promise<void> {
    await this.applyFilter('', '');
  }

  /**
   * 拉取某媒体的全部报告明细（详情页）
   * ★ path 参数是 int，这里把字符串 id 转数字后再请求
   * @param mediaId 媒体 id（字符串形态）
   * @param mediaName 媒体名（仅用于补写本地镜像，可传空串）
   * @param mediaType 媒体类型（仅用于补写本地镜像，可传空串）
   */
  public async loadDetail(mediaId: string, mediaName: string, mediaType: string): Promise<ActionResultModel> {
    this.beginLoad();
    try {
      const dtos: ReportOutDto[] = await ReportApi.listByMediaIdText(mediaId);
      const detail: DiagnosisReportModel[] = Mapper.toDiagnosisReports(dtos);
      this.detailItems = detail;
      await this.cacheDetail(detail, mediaName, mediaType);
      this.endLoadOk();
      return ReportStore.ok(`共 ${detail.length} 条报告`);
    } catch (err) {
      const apiErr = toApiError(err as Object);
      if (isNetworkFailure(err as Object)) {
        // 离线：退回本地镜像
        const cached: DiagnosisReportModel[] = await StorageManager.reportDao().loadDetailByMedia(mediaId);
        this.detailItems = cached;
        this.loading = false;
        return ReportStore.ok(cached.length > 0 ? `离线数据 · 共 ${cached.length} 条` : '离线且无本地数据');
      }
      this.endLoadErr(apiErr.message);
      return ReportStore.fail(apiErr.message);
    }
  }

  /** 从 RDB 镜像表读回当前筛选条件的第一页（离线兜底 / 冷启动预热） */
  public async loadFromCache(): Promise<number> {
    if (!StorageManager.isRdbReady()) {
      return 0;
    }
    const filter: ReportFilterModel = this.buildFilter();
    const page: ReportListItemModel[] = await StorageManager.reportDao().queryPage(filter);
    const total: number = await StorageManager.reportDao().countByFilter(filter);
    if (page.length > 0) {
      this.items = page;
      this.total = total;
      this.hasMore = page.length < total;
      this.lastSyncAt = await StorageManager.lastSyncAt();
      this.log().i(`报告列表已从本地缓存恢复 · ${page.length}/${total}`);
    }
    return page.length;
  }

  /** 冷启动预热 · 有本地数据先进内存 */
  public async warmUp(): Promise<boolean> {
    const count: number = await this.loadFromCache();
    return count > 0;
  }

  /** 实现 BaseStore：清空内存 */
  public clear(): void {
    this.items = [];
    this.detailItems = [];
    this.total = 0;
    this.page = 1;
    this.hasMore = false;
    this.severityFilter = '';
    this.mediaTypeFilter = '';
    this.loading = false;
    this.loadingMore = false;
    this.errorMsg = '';
    this.lastSyncAt = 0;
  }

  /** 实现 BaseStore */
  protected storeName(): string {
    return 'ReportStore';
  }

  // ────────────────── 内部实现（全部下压）──────────────────

  /**
   * 拉取指定页
   * @param append true = 追加（翻页），false = 替换（刷新）
   */
  private async loadPage(targetPage: number, append: boolean): Promise<void> {
    const filter: ReportFilterModel = this.buildFilter();
    filter.page = targetPage;
    try {
      const out: ReportListOutDto = await ReportApi.list({
        severity: filter.severity, mediaType: filter.mediaType, page: filter.page, limit: filter.pageSize
      });
      const dtos: ReportListItemDto[] = out.items === undefined || out.items === null ? [] : out.items;
      const pageItems: ReportListItemModel[] = Mapper.toReportListItems(dtos);
      const total: number = out.total === undefined || out.total === null ? pageItems.length : out.total;

      this.items = append ? ReportStore.concat(this.items, pageItems) : pageItems;
      this.total = total;
      this.page = targetPage;
      this.hasMore = this.items.length < total;

      // 回写镜像表（列表项不含 notes，详情接口会补写）
      await StorageManager.reportDao().replaceAll(pageItems);
      await StorageManager.markSynced();
      this.endLoadOk();
      this.log().i(`报告已同步 · 第 ${targetPage} 页 / 共 ${total} 条`);
    } catch (err) {
      const apiErr = toApiError(err as Object);
      if (isNetworkFailure(err as Object)) {
        this.loading = false;
        this.log().w('报告同步失败（网络不可达）· 使用本地缓存');
        return;
      }
      this.endLoadErr(apiErr.message);
      this.log().e('报告同步失败', err as Object);
    }
  }

  /**
   * 把详情写进镜像表（补上列表接口不给的 notes）
   * ★ 镜像行的 media_name / media_type 是列表接口才有的字段，详情接口没有；
   *   调用方拿不到时传空串，此时**跳过补写**，避免把列表页已写好的正确值覆盖成空。
   */
  private async cacheDetail(
    detail: DiagnosisReportModel[], mediaName: string, mediaType: string
  ): Promise<void> {
    if (!StorageManager.isRdbReady() || detail.length === 0) {
      return;
    }
    if (mediaName.length === 0 && mediaType.length === 0) {
      this.log().d('详情镜像补写已跳过（缺少媒体名与类型）');
      return;
    }
    const type: MediaType = mediaType === (MediaType.video as string) ? MediaType.video : MediaType.image;
    for (let i = 0; i < detail.length; i++) {
      await StorageManager.reportDao().saveDetail(detail[i], mediaName, type);
    }
  }

  private static concat(first: ReportListItemModel[], second: ReportListItemModel[]): ReportListItemModel[] {
    const out: ReportListItemModel[] = [];
    for (let i = 0; i < first.length; i++) {
      out.push(first[i]);
    }
    for (let j = 0; j < second.length; j++) {
      out.push(second[j]);
    }
    return out;
  }

  private static ok(message: string): ActionResultModel {
    const result: ActionResultModel = { ok: true, message: message };
    return result;
  }

  private static fail(message: string): ActionResultModel {
    const result: ActionResultModel = { ok: false, message: message };
    return result;
  }
}
