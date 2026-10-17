/**
 * StatsPage · 统计（一级页签）
 *
 * 页面契约：`@Param pageParam: TabPageParam`（MainPage 传入，本页固定 stats 页签）
 *
 * 数据来源（只消费，不发请求）：
 *   `AppStore.statsSummary`（StatsModel：totalAnalyses / totalMedia /
 *     avgInferenceTimeMs / severityDistribution / bdiTrend）
 *   `AppStore.statsBuckets`（SeverityBucketModel[]，饼图直接吃）
 *   `AppStore.statsLoading` / `refreshStats()`
 * 网页端对应：src/views/StatsView.vue（KPI 四联卡 + 严重度饼图 + BDI 趋势折线）
 *
 * ★ 版式（2026-10-17 · 与全工程「扁平 + 圆角8 + 无渐变」的 UI 规范对齐）：
 *   页面左右内边距 16 / 模块垂直间距 16；
 *   顶部 KPI 区 = 「总分析次数」满行核心卡（浅薄荷底 + 描边，不用渐变）
 *                + 下方 3 张等宽小卡并排（平均推理耗时 / 素材总数 / 重度占比）；
 *   环形图、折线图各占一张独立卡片。
 *   ★ 层级靠「浅色块 + 1vp 描边」表达，不用投影：`UiTheme.cardShadowEnabled` 为 false，
 *     全工程是扁平风，本页跟随，避免切页签时观感跳变。
 *
 * ★ 转场：每块内容包一层 `RevealCard({ order })` 做错峰滑入（队友实现的通用转场）。
 *   KPI 三小卡那一排不包 —— 它们在 Row 里靠 `layoutWeight(1)` 均分宽度，
 *   外面再套容器会破坏均分（见 buildContent 注释）。
 *
 * ★ 语法纪律（2026-10-16 踩坑）：build()/@Builder 体内【不能声明局部变量】。
 */

import { AppStore } from '../store/AppStore';
import { AppBootstrap } from '../common/AppBootstrap';
import { UiTheme } from '../common/UiTheme';
import { TabPageParam } from '../types/PageParams';
import { StatsModel } from '../types/Index';
import { PageHeader } from '../components/PageHeader';
import { AppCard } from '../components/AppCard';
import { ErrorRetryView } from '../components/ErrorRetryView';
import { SkeletonBlock } from '../components/SkeletonView';
import { RevealCard } from '../components/RevealCard';
import { SeverityPieChart } from '../components/charts/SeverityPieChart';
import { BdiTrendChart } from '../components/charts/BdiTrendChart';

/** 次级 KPI 数字字号（三卡并排，20 是 393 宽下的安全上限） */
const KPI_SUB_METRIC_SIZE: number = 20;

@ComponentV2
export struct StatsPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: TabPageParam = new TabPageParam();

  @Computed
  get app(): AppStore {
    return AppStore.get();
  }

  aboutToAppear(): void {
    // 等数据层引导完成再拉统计（引导内部已并发拉过一轮，这里保证切到本页时最新）
    AppBootstrap.ready.then(() => {
      this.app.refreshStats();
    });
  }

  build() {
    // ★ 语法纪律（2026-10-16 踩坑）：build()/@Builder 体内是 ArkUI UI 语法，
    //   【不能声明局部变量】（const/let 都不行），否则 arkts 插件在容器收尾处
    //   报 "Unexpected token"，并伪装成 10905210 "单根节点"错误。
    // ★ 必须包一层 Scroll：本页内容（页头 + KPI 区 + 饼图卡 + 折线卡）高于一屏。
    Scroll() {
      Column({ space: UiTheme.gapL }) {
        // 页头 · 0 号位（转场由 RevealCard 内部负责）
        RevealCard({ order: 0 }) {
          Column() {
            PageHeader({ title: '统计', subtitle: '分析次数、严重度分布与 BDI 趋势' })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        if (this.app.statsLoading) {
          this.buildSkeleton()
        } else if (this.app.statsSummary === null) {
          // 冷启动无缓存且没拉到数据：给错误 + 重试（不白屏）
          ErrorRetryView({
            message: '统计数据加载失败，请检查网络后重试',
            onRetry: () => {
              this.app.refreshStats();
            }
          })
        } else {
          // 上一个分支已排除 null，这里显式收窄后传给 @Builder
          this.buildContent(this.app.statsSummary as StatsModel)
        }
      }
      .width('100%')
      .padding({
        left: UiTheme.statsPagePadding,
        right: UiTheme.statsPagePadding,
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

  /** 加载中骨架：与真实内容同构（核心卡 + 3 小卡 + 两张图），避免加载完成时布局跳动 */
  @Builder
  buildSkeleton() {
    Column({ space: UiTheme.gapL }) {
      SkeletonBlock({ blockHeight: UiTheme.kpiHeroHeight, radius: UiTheme.cardRadius })

      Row({ space: UiTheme.gapM }) {
        SkeletonBlock({ blockWidth: '31%', blockHeight: UiTheme.kpiSmallHeight, radius: UiTheme.cardRadius })
        SkeletonBlock({ blockWidth: '31%', blockHeight: UiTheme.kpiSmallHeight, radius: UiTheme.cardRadius })
        SkeletonBlock({ blockWidth: '31%', blockHeight: UiTheme.kpiSmallHeight, radius: UiTheme.cardRadius })
      }
      .width('100%')

      SkeletonBlock({ blockHeight: 300, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 300, radius: UiTheme.cardRadius })
    }
    .width('100%')
  }

  @Builder
  buildContent(stats: StatsModel) {
    // ── 核心 KPI 卡 · 1 号位（满行 · 浅薄荷底 + 描边表达层级）──
    RevealCard({ order: 1 }) {
      Column({ space: UiTheme.gapS }) {
        Text('总分析次数')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)

        Text() {
          Span(`${stats.totalAnalyses}`)
            .fontSize(UiTheme.fontSizeMetric)
            .fontWeight(FontWeight.Bold)
            .fontColor(UiTheme.statAccent)
          Span(' 次')
            .fontSize(UiTheme.fontSizeUnit)
            .fontColor(UiTheme.textSecondary)
        }
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
      }
      .width('100%')
      .height(UiTheme.kpiHeroHeight)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding(UiTheme.cardPadding)
      .backgroundColor(UiTheme.kpiHeroTint)
      .borderRadius(UiTheme.cardRadius)
      .border({ width: 1, color: UiTheme.kpiHeroBorder })
    }

    // ── 3 张等宽小卡 ──
    // ★ 这一排不包 RevealCard：小卡在 Row 里靠 layoutWeight(1) 均分宽度，
    //   外层再套容器会破坏均分（同队友在工作台页踩到的坑）。
    Row({ space: UiTheme.gapM }) {
      this.smallKpi('平均推理耗时', `${stats.avgInferenceTimeMs.toFixed(1)}`, 'ms')
      this.smallKpi('素材总数', `${stats.totalMedia}`, '项')
      this.smallKpi('重度占比', this.severePct(stats), this.severePct(stats) === '--' ? '' : '%')
    }
    .width('100%')

    // ── 严重度分布（环形饼图 + 环心总数）· 2 号位 ──
    RevealCard({ order: 2 }) {
      AppCard({ title: '严重等级分布', subtitle: '按 BDI-II 四档统计' }) {
        if (stats.totalAnalyses > 0) {
          SeverityPieChart({
            buckets: this.app.statsBuckets,
            total: stats.totalAnalyses
          })
        } else {
          Text('暂无分析数据')
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
    }

    // ── BDI 日均趋势（折线 + 两条阈值线）· 3 号位 ──
    RevealCard({ order: 3 }) {
      AppCard({ title: 'BDI 日均趋势', subtitle: '按检测日期聚合的日均分' }) {
        if (stats.bdiTrend.length === 0) {
          Text('暂无趋势数据')
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
        } else {
          BdiTrendChart({ trend: stats.bdiTrend })
        }
      }
    }
  }

  /**
   * 次级 KPI 小卡（三张等宽并排 · 白底 + 细描边，无投影）
   * 标签 12/辅助色 在上，数字 20/600/一级色 + 单位 10 在下
   */
  @Builder
  smallKpi(title: string, value: string, unit: string) {
    Column({ space: UiTheme.gapS }) {
      Text(title)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text() {
        Span(value)
          .fontSize(KPI_SUB_METRIC_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.textPrimary)
        Span(` ${unit}`)
          .fontSize(UiTheme.fontSizeUnitSmall)
          .fontColor(UiTheme.textSecondary)
      }
      .width('100%')
      .textAlign(TextAlign.Start)
      .maxLines(1)
      .height(28)
    }
    .layoutWeight(1)
    .height(UiTheme.kpiSmallHeight)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .padding(UiTheme.kpiSmallPadding)
    .backgroundColor(UiTheme.cardBackground)
    .borderRadius(UiTheme.cardRadius)
    .border({ width: 1, color: UiTheme.divider })
  }

  /** 重度占比（对应网页端 severePct · 返回不带 % 的数值串） */
  private severePct(stats: StatsModel): string {
    if (stats.totalAnalyses <= 0) {
      return '--';
    }
    const severe: number = stats.severityDistribution['severe'] ?? 0;
    return ((severe / stats.totalAnalyses) * 100).toFixed(1);
  }
}
