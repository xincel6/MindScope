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
 * ★ 页面纪律（沿用本工程约定）：不 import 任何领域 store 之外的网络层；
 *   取数只找 AppStore 门面；字段一律驼峰。
 *
 * ★ 语法纪律（2026-10-16 踩坑记录，详见 build() 内注释）：build()/@Builder
 *   体内【不能声明局部变量】。
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
import { SeverityPieChart } from '../components/charts/SeverityPieChart';
import { BdiTrendChart } from '../components/charts/BdiTrendChart';

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
    // ★ 语法纪律（2026-10-16 踩坑记录）：build()/@Builder 体内是 ArkUI UI 语法，
    //   【不能声明局部变量】（const/let 都不行，带不带类型标注都会让 arkts 插件
    //   在容器收尾处报 "Unexpected token"，再伪装成 10905210 "单根节点"错误）。
    //   需要快照/收窄时，把逻辑放到 @Computed getter 里，或在调用处用 `as` 收窄。
    //   （UI 元素后跟分号是合法的，2026-10-16 实测；本工程风格是不跟。）
    // ★ 必须包一层 Scroll：本页内容（页头 + 四张 KPI 卡 + 饼图卡 + 折线卡）高于一屏，
    //   之前直接用 Column 导致第二张图表被顶到屏幕外、藏在底部页签栏后面（看不到图）。
    Scroll() {
      Column({ space: UiTheme.gapL }) {
        PageHeader({ title: '统计', subtitle: '分析次数、严重度分布与 BDI 趋势' })

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

  /** 加载中骨架：与真实内容同构（KPI 行 + 两张图），避免加载完成时布局跳动 */
  @Builder
  buildSkeleton() {
    Column({ space: UiTheme.gapM }) {
      SkeletonBlock({ blockHeight: 72, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 72, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 220, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 220, radius: UiTheme.cardRadius })
    }
    .width('100%')
  }

  @Builder
  buildContent(stats: StatsModel) {
    // ── KPI 卡片（对应网页端 StatCard 四联）──
    Row({ space: UiTheme.gapM }) {
      this.kpiCard('总分析次数', `${stats.totalAnalyses}`)
      this.kpiCard('平均推理耗时', `${stats.avgInferenceTimeMs.toFixed(1)} ms`)
    }
    .width('100%')

    Row({ space: UiTheme.gapM }) {
      this.kpiCard('素材总数', `${stats.totalMedia}`)
      this.kpiCard('重度占比', this.severePct(stats))
    }
    .width('100%')

    // ── 严重度分布（环形饼图 + 圆心总数）──
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

    // ── BDI 日均趋势（折线 + 三条阈值线）──
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

  @Builder
  kpiCard(title: string, value: string) {
    Column({ space: UiTheme.gapXs }) {
      Text(title)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
      Text(value)
        .fontSize(UiTheme.fontSizeMetric)
        .fontWeight(FontWeight.Bold)
        .fontColor(UiTheme.textPrimary)
    }
    .layoutWeight(1)
    .padding(UiTheme.cardPadding)
    .backgroundColor(UiTheme.cardBackground)
    .borderRadius(UiTheme.cardRadius)
  }

  /** 重度占比（对应网页端 severePct） */
  private severePct(stats: StatsModel): string {
    if (stats.totalAnalyses <= 0) {
      return '--';
    }
    const severe: number = stats.severityDistribution['severe'] ?? 0;
    return `${((severe / stats.totalAnalyses) * 100).toFixed(1)}%`;
  }
}
