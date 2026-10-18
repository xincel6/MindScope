/**
 * ReportsPage · 历史报告
 *
 * 页面只做三件事：
 *   ① 按检测时间倒序列出服务端已保存报告，最新在最上面；
 *      同一 mediaId 的重复分析合并为一张卡，卡片内标注分析次数与分数范围；
 *   ② 卡片只保留文件名、检测时间、BDI 与严重度等少量信息；
 *   ③ 点卡片打开分析详情页的已保存快照。
 *
 * ★ 不展示当前登录账号：历史报告与账号不是一一对应关系，
 *   每张卡重复头像/用户名既没有信息量，也会让人误以为报告属于当前账号。
 *   当前远程服务器没有持久化上传者账号，因此卡片不展示姓名/账号行。
 *
 * 数据来源：`AppStore.reportItems`（GET /api/reports）。
 * 本页不发起分析，也不使用当前分析会话的数据顶替历史报告。
 */

import { AppBootstrap } from '../common/AppBootstrap';
import { UiTheme } from '../common/UiTheme';
import { AppStore } from '../store/AppStore';
import {
  BDI_MAX_SCORE, MediaType, ReportListItemModel, ReportMediaGroupModel, UiConstant
} from '../types/Index';
import { ReportsPageParam } from '../types/PageParams';
import { ErrorRetryView } from '../components/ErrorRetryView';
import { RevealCard } from '../components/RevealCard';
import { RippleCard } from '../components/RippleCard';
import { SkeletonBlock } from '../components/SkeletonView';
import { ProgressBar } from '../components/common/ProgressBar';

/** 严重度筛选项 · 空串 = 全部 */
const SEVERITY_FILTERS: string[] = ['', 'none', 'mild', 'moderate', 'severe'];

/** 素材类型筛选项 · 空串 = 全部 */
const MEDIA_TYPE_FILTERS: string[] = ['', 'image', 'video'];

/**
 * 历史报告排序函数
 *
 * 检测时间最近的排最上面；同一时间按报告 id 倒序。
 * 返回新数组，不修改 AppStore 原始列表。
 */
function sortReportsNewestFirst(items: ReportListItemModel[]): ReportListItemModel[] {
  const out: ReportListItemModel[] = items.slice();
  out.sort((a: ReportListItemModel, b: ReportListItemModel): number => {
    if (a.detectedAt !== b.detectedAt) {
      return a.detectedAt < b.detectedAt ? 1 : -1;
    }
    return b.id - a.id;
  });
  return out;
}

/**
 * 历史列表按 mediaId 聚合
 *
 * 同一上传素材可能被重复分析多次，服务端会为每次分析写一条 diagnosis_report。
 * 卡片展示最新一次结果，同时保留分析次数和分数范围；文件名相同但 mediaId 不同的
 * 上传记录不会被强行合并，因为缺少内容哈希时无法证明它们一定是同一张图。
 */
function buildReportGroups(items: ReportListItemModel[]): ReportMediaGroupModel[] {
  const sorted: ReportListItemModel[] = sortReportsNewestFirst(items);
  const out: ReportMediaGroupModel[] = [];
  const indexByMedia: Record<string, number> = {};
  for (let i = 0; i < sorted.length; i++) {
    const item: ReportListItemModel = sorted[i];
    const hit: number | undefined = indexByMedia[item.mediaId];
    if (hit !== undefined) {
      const group: ReportMediaGroupModel = out[hit];
      group.analysisCount = group.analysisCount + 1;
      group.minBdiScore = Math.min(group.minBdiScore, item.bdiScore);
      group.maxBdiScore = Math.max(group.maxBdiScore, item.bdiScore);
      continue;
    }
    indexByMedia[item.mediaId] = out.length;
    const group: ReportMediaGroupModel = {
      mediaId: item.mediaId,
      latest: item,
      analysisCount: 1,
      minBdiScore: item.bdiScore,
      maxBdiScore: item.bdiScore
    };
    out.push(group);
  }
  return out;
}

@ComponentV2
export struct ReportsPage {
  /** 历史报告页参数 · 动作由窗口层注入 */
  @Param pageParam: ReportsPageParam = new ReportsPageParam();

  /** 整页滚动控制器 · 刷新或筛选后回到最新一条 */
  private scroller: Scroller = new Scroller();

  @Computed
  get app(): AppStore {
    return AppStore.get();
  }

  /** 最新在上的素材报告分组 */
  @Computed
  get reportGroups(): ReportMediaGroupModel[] {
    return buildReportGroups(this.app.reportItems);
  }

  @Computed
  get isFiltered(): boolean {
    return this.app.reportSeverityFilter.length > 0 || this.app.reportMediaTypeFilter.length > 0;
  }

  @Computed
  get countText(): string {
    if (this.app.reportAllLoaded) {
      return `共 ${this.reportGroups.length} 个素材 · 已完整加载`;
    }
    return `已加载 ${this.reportGroups.length} 个素材 · 数据尚未完整`;
  }

  @Computed
  get filterText(): string {
    if (!this.isFiltered) {
      return '全部报告';
    }
    const parts: string[] = [];
    if (this.app.reportSeverityFilter.length > 0) {
      parts.push(UiConstant.severityLabel(this.app.reportSeverityFilter));
    }
    if (this.app.reportMediaTypeFilter.length > 0) {
      parts.push(UiConstant.mediaTypeLabel(this.app.reportMediaTypeFilter));
    }
    return parts.join(' · ');
  }

  @Computed
  get emptyHint(): string {
    if (this.app.reportLoading) {
      return '正在加载历史报告…';
    }
    if (this.isFiltered) {
      return '当前筛选条件下没有报告';
    }
    return '还没有历史报告，先完成一次辅助评估';
  }

  aboutToAppear(): void {
    AppBootstrap.ready.then(() => {
      this.reload();
    });
  }

  // ══════════════════ 数据动作 ══════════════════

  private async reload(): Promise<void> {
    await this.pageParam.onRefresh();
    this.scrollToTop();
  }

  private async changeSeverity(raw: string): Promise<void> {
    if (this.app.reportLoading || raw === this.app.reportSeverityFilter) {
      return;
    }
    await this.pageParam.onFilter(raw, this.app.reportMediaTypeFilter);
    this.scrollToTop();
  }

  private async changeMediaType(raw: string): Promise<void> {
    if (this.app.reportLoading || raw === this.app.reportMediaTypeFilter) {
      return;
    }
    await this.pageParam.onFilter(this.app.reportSeverityFilter, raw);
    this.scrollToTop();
  }

  private async resetFilters(): Promise<void> {
    if (this.app.reportLoading || !this.isFiltered) {
      return;
    }
    await this.pageParam.onFilter('', '');
    this.scrollToTop();
  }

  private scrollToTop(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Start);
    }, 250);
    // 全量数据可能分两页到达，页面完成二次测量后再校正一次。
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Start);
    }, 900);
  }

  // ══════════════════ 展示派生 ══════════════════

  private severityFilterLabel(raw: string): string {
    return raw.length === 0 ? '全部' : UiConstant.severityLabel(raw);
  }

  private mediaFilterLabel(raw: string): string {
    return raw.length === 0 ? '全部' : UiConstant.mediaTypeLabel(raw);
  }

  /** 报告里可直接使用的姓名/素材名（去掉扩展名，减少视觉噪声） */
  private subjectNameOf(raw: string): string {
    const trimmed: string = raw.trim();
    const dot: number = trimmed.lastIndexOf('.');
    const name: string = dot > 0 ? trimmed.slice(0, dot) : trimmed;
    return name.length > 0 ? name : '未命名素材';
  }

  private dateText(raw: string): string {
    return raw.length >= 10 ? raw.slice(0, 10) : raw;
  }

  private timeText(raw: string): string {
    return raw.length >= 16 ? raw.slice(11, 16) : '';
  }

  private scoreText(item: ReportListItemModel): string {
    return item.bdiScore > 0 ? item.bdiScore.toFixed(1) : '--';
  }

  private scoreRatioOf(item: ReportListItemModel): number {
    if (item.bdiScore <= 0) {
      return 0;
    }
    return item.bdiScore >= BDI_MAX_SCORE ? 1 : item.bdiScore / BDI_MAX_SCORE;
  }

  private severityLabelOf(item: ReportListItemModel): string {
    return UiConstant.severityLabelOf(item.severity);
  }

  private severityColorOf(item: ReportListItemModel): string {
    return UiConstant.severityColorOf(item.severity);
  }

  private mediaTypeLabelOf(item: ReportListItemModel): string {
    return item.mediaType === MediaType.video ? '视频' : '图片';
  }

  /** 同一素材的分析次数与历史分数范围 */
  private analysisSummaryOf(group: ReportMediaGroupModel): string {
    if (group.analysisCount <= 1) {
      return '1 次分析';
    }
    if (group.maxBdiScore - group.minBdiScore < 0.05) {
      return `共 ${group.analysisCount} 次分析 · 结果一致`;
    }
    return `共 ${group.analysisCount} 次分析 · 分数 ${group.minBdiScore.toFixed(1)}–${group.maxBdiScore.toFixed(1)}`;
  }

  // ══════════════════ 页头与筛选 ══════════════════

  @Builder
  headerBlock() {
    Column({ space: UiTheme.gapM }) {
      Row({ space: UiTheme.gapS }) {
        Column({ space: UiTheme.gapXs }) {
          Text('历史报告')
            .fontSize(UiTheme.fontSizeTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(UiTheme.textPrimary)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(this.app.reportLoading ? '…' : '↻')
          .fontSize(20)
          .fontColor(UiTheme.textSecondary)
          .backgroundColor(Color.Transparent)
          .borderRadius(UiTheme.cardRadius)
          .width(40)
          .height(40)
          .enabled(!this.app.reportLoading)
          .onClick(() => {
            this.reload();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        Text('严重度')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width(46)
          .textAlign(TextAlign.Start)

        ForEach(SEVERITY_FILTERS, (raw: string) => {
          this.severityChip(raw)
        }, (raw: string) => `sev-${raw}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        Text('素材')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width(46)
          .textAlign(TextAlign.Start)

        ForEach(MEDIA_TYPE_FILTERS, (raw: string) => {
          this.mediaTypeChip(raw)
        }, (raw: string) => `media-${raw}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  severityChip(raw: string) {
    Text(this.severityFilterLabel(raw))
      .fontSize(UiTheme.fontSizeCaption)
      .fontColor(raw === this.app.reportSeverityFilter ? UiTheme.cardBackground : UiTheme.textSecondary)
      .padding({ left: UiTheme.gapS, right: UiTheme.gapS, top: 5, bottom: 5 })
      .borderRadius(14)
      .borderWidth(1)
      .borderColor(raw === this.app.reportSeverityFilter ? UiTheme.primary : UiTheme.divider)
      .backgroundColor(raw === this.app.reportSeverityFilter ? UiTheme.primary : UiTheme.cardBackground)
      .enabled(!this.app.reportLoading)
      .onClick(() => {
        this.changeSeverity(raw);
      })
  }

  @Builder
  mediaTypeChip(raw: string) {
    Text(this.mediaFilterLabel(raw))
      .fontSize(UiTheme.fontSizeCaption)
      .fontColor(raw === this.app.reportMediaTypeFilter ? UiTheme.cardBackground : UiTheme.textSecondary)
      .padding({ left: UiTheme.gapS, right: UiTheme.gapS, top: 5, bottom: 5 })
      .borderRadius(14)
      .borderWidth(1)
      .borderColor(raw === this.app.reportMediaTypeFilter ? UiTheme.primary : UiTheme.divider)
      .backgroundColor(raw === this.app.reportMediaTypeFilter ? UiTheme.primary : UiTheme.cardBackground)
      .enabled(!this.app.reportLoading)
      .onClick(() => {
        this.changeMediaType(raw);
      })
  }

  @Builder
  listToolbar() {
    Row({ space: UiTheme.gapS }) {
      Column({ space: 2 }) {
        Text('历史记录')
          .fontSize(UiTheme.fontSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(`${this.countText} · ${this.filterText}`)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isFiltered) {
        Text('清除筛选')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.accent)
          .padding({ left: UiTheme.gapS, right: UiTheme.gapXs, top: UiTheme.gapXs, bottom: UiTheme.gapXs })
          .onClick(() => {
            this.resetFilters();
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ══════════════════ 报告卡片 ══════════════════

  @Builder
  reportCard(group: ReportMediaGroupModel) {
    RippleCard({
      _padding: UiTheme.cardPadding,
      onTap: () => {
        this.pageParam.onOpenReport(group.latest);
      }
    }) {
      Column({ space: UiTheme.gapM }) {
        Row({ space: UiTheme.gapM }) {
          Column({ space: 3 }) {
            Text(`${this.subjectNameOf(group.latest.mediaName)} · ${this.dateText(group.latest.detectedAt)} ${this.timeText(group.latest.detectedAt)} · ${this.mediaTypeLabelOf(group.latest)}`)
              .fontSize(UiTheme.fontSizeBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.textPrimary)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 2 }) {
            Text(this.scoreText(group.latest))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.severityColorOf(group.latest))
              .maxLines(1)

            Text(this.severityLabelOf(group.latest))
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(this.severityColorOf(group.latest))
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        ProgressBar({
          ratio: this.scoreRatioOf(group.latest),
          barColor: this.severityColorOf(group.latest),
          barHeight: 5
        })

        Row({ space: UiTheme.gapS }) {
          Column({ space: 2 }) {
            Text(`最近一次 · 推理 ${group.latest.inferenceTimeMs.toFixed(1)} ms`)
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)

            Text(this.analysisSummaryOf(group))
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(this.severityColorOf(group.latest))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text('查看报告  ›')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.accent)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // ══════════════════ 状态 ══════════════════

  @Builder
  skeletonList() {
    Column({ space: UiTheme.gapM }) {
      SkeletonBlock({ blockHeight: 132, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 132, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 132, radius: UiTheme.cardRadius })
    }
    .width('100%')
  }

  @Builder
  emptyCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapS }) {
        Text(this.emptyHint)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('这里只展示服务端已经保存的分析报告。')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  incompleteCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapS }) {
        Text('历史报告尚未完整加载')
          .fontSize(UiTheme.fontSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('分页数据没有全部返回，当前列表可能少素材。请重新加载后再查看。')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Button('重新加载')
          .height(36)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.accent)
          .backgroundColor(Color.Transparent)
          .borderWidth(1)
          .borderColor(UiTheme.accent)
          .borderRadius(UiTheme.buttonRadius)
          .enabled(!this.app.reportLoading)
          .onClick(() => {
            this.reload();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  listFooter() {
    Column({ space: UiTheme.gapS }) {
      Divider().color(UiTheme.divider)
      Text('已到最早一份素材报告')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: UiTheme.gapS })
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: UiTheme.gapM }) {
        RevealCard({ order: 0 }) {
          this.headerBlock()
        }

        RevealCard({ order: 1 }) {
          this.listToolbar()
        }

        if (!this.app.reportAllLoaded && !this.app.reportLoading && this.app.reportTotal > 0) {
          this.incompleteCard()
        }

        if (this.app.reportLoading && this.reportGroups.length === 0) {
          this.skeletonList()
        } else if (this.app.reportError.length > 0 && this.reportGroups.length === 0) {
          ErrorRetryView({
            message: this.app.reportError,
            retryLabel: '重新加载',
            retrying: this.app.reportLoading,
            onRetry: () => {
              this.reload();
            }
          })
        } else if (this.reportGroups.length === 0) {
          this.emptyCard()
        } else {
          Column({ space: UiTheme.gapM }) {
            ForEach(this.reportGroups, (group: ReportMediaGroupModel) => {
              this.reportCard(group)
            }, (group: ReportMediaGroupModel) => `media-${group.mediaId}`)

            this.listFooter()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .padding({
        left: UiTheme.pagePadding,
        right: UiTheme.pagePadding,
        top: UiTheme.gapL,
        bottom: UiTheme.gapXxl
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(UiTheme.pageBackground)
  }
}
