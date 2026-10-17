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
 * ★ 视觉边界：
 *   本页曾是"浅灰底 #F2F3F7 / 卡片圆角 16 / 极淡投影"这套风格的**来源**，
 *   现已提升为全局规范（`pageBackground` / `cardRadius` / `CardStyle.shadow()`），
 *   所以本页不再自带一套底色、圆角与阴影，只保留图表与版式专用的令牌
 *   （`statsTitleSize` / `statsPagePadding` / `kpi*` / `pie*` / `legend*` / `chart*`）。
 *   核心卡的渐变是用户明确保留的本页个性，不属于可收敛的重复项。
 *
 * ★ 版式：
 *   页面左右内边距 16 / 模块垂直间距 16；
 *   KPI 区 = 「总分析次数」满行渐变核心卡 + 下方 3 张等宽小卡；
 *   环形图、折线图各占一张独立卡片（标题 16/600 + 副标题 12，左上对齐）。
 *
 * ★ 交互：4 张卡都套一层 `RippleCard`（与工作台同一套按压语言：系统涟漪 + 轻微缩放），
 *   但传 `_enabled: false` —— 统计页的卡片只表达"被按到了"，不承担任何跳转。
 *   卡片的白底 / 16 圆角 / 极淡投影由 `RippleCard` 内联画（同值，所以不在本页再写一份）；
 *   核心渐变卡自带背景，用 `_transparent: true` 让壳子一点不画。
 *   全部传 `_padding: 0`：这几张卡自己已经有内边距，否则会叠成双层。
 *   ★ `RippleCard` 必须套在 `RevealCard` **里层**，转场的位移/缩放才作用在整卡上。
 *
 * ★ 转场：每块内容（含 KPI 三小卡）各包一层 `RevealCard({ order })` 做错峰滑入，
 *   全页 order 0..6 连续。三小卡的等宽由 `RevealCard._weight: 1` 承担 ——
 *   均分看的是 Row 的**直接子节点**，裸 `layoutWeight` 会被动画卡那层 Column 吞掉。
 *
 * ★ 语法纪律（2026-10-16 踩坑）：build()/@Builder 体内【不能声明局部变量】。
 */

import { AppStore } from '../store/AppStore';
import { AppBootstrap } from '../common/AppBootstrap';
import { UiTheme } from '../common/UiTheme';
import { CardStyle } from '../common/CardStyle';
import { TabPageParam } from '../types/PageParams';
import { StatsModel } from '../types/Index';
import { ErrorRetryView } from '../components/ErrorRetryView';
import { SkeletonBlock } from '../components/SkeletonView';
import { RevealCard } from '../components/RevealCard';
import { RippleCard } from '../components/RippleCard';
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
        // 页头 · 0 号位（本页自绘，字号比全局 22 大一档到 26）
        RevealCard({ order: 0 }) {
          Column({ space: UiTheme.gapXs }) {
            Text('统计')
              .fontSize(UiTheme.statsTitleSize)
              .fontWeight(FontWeight.Bold)
              .fontColor(UiTheme.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(1)

            Text('分析次数、严重度分布与 BDI 趋势')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(1)
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

      SkeletonBlock({ blockHeight: 320, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 340, radius: UiTheme.cardRadius })
    }
    .width('100%')
  }

  @Builder
  buildContent(stats: StatsModel) {
    // ── 核心 KPI 卡 · 1 号位（满行 · 浅薄荷 → 白 渐变）──
    RevealCard({ order: 1 }) {
      // ★ 透明壳：这张卡自带渐变底，壳子不画任何底色/描边/投影，只借统一的按压语言。
      //   _padding: 0 让内边距仍由里层给（否则 16+16 会把 106 高的卡撑变形）。
      RippleCard({
        _transparent: true,
        _enabled: false,
        _clickable: true,
        _pressScale: 0.985,
        _padding: 0
      }) {
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
        // 渐变与圆角仍留在里层：透明壳不画背景，也就不会替它裁圆角、兜投影
        .borderRadius(UiTheme.cardRadius)
        .linearGradient({
          // 160° 近乎垂直：绿色压在卡片上半部，白色往下收。
          // 135° 时 32fp 的绿色数字正好落在白色区，真机上几乎看不出渐变。
          angle: 160,
          colors: [
            [UiTheme.kpiGradientStart, 0],
            [UiTheme.kpiGradientEnd, 1]
          ]
        })
        .shadow(CardStyle.shadow())
      }
    }

    // ── 3 张等宽小卡 · 2/3/4 号位 ──
    // ★ 等宽的权重挂在 RevealCard 的 `_weight` 上：均分只认 Row 的直接子节点，
    //   而这里唯一的直接子节点就是动画卡那层 Column；小卡自己再写 layoutWeight
    //   会变成第二套权重、与 `_weight` 抢同一条主轴。
    Row({ space: UiTheme.gapM }) {
      RevealCard({ order: 2, _weight: 1 }) {
        this.smallKpi('平均推理耗时', `${stats.avgInferenceTimeMs.toFixed(1)}`, 'ms')
      }

      RevealCard({ order: 3, _weight: 1 }) {
        this.smallKpi('素材总数', `${stats.totalMedia}`, '项')
      }

      RevealCard({ order: 4, _weight: 1 }) {
        this.smallKpi('重度占比', this.severePct(stats), this.severePct(stats) === '--' ? '' : '%')
      }
    }
    .width('100%')

    // ── 严重度分布（环形饼图 + 环心总数）· 5 号位 ──
    RevealCard({ order: 5 }) {
      // 白底 / 16 圆角 / 极淡投影交给 RippleCard 内联画（与原来同值，不保留两份）；
      // _padding: 0 是因为下面这层自己已经有 cardPadding，否则会叠成双层内边距。
      RippleCard({
        _enabled: false,
        _clickable: true,
        _pressScale: 0.98,
        _padding: 0
      }) {
        Column({ space: UiTheme.gapM }) {
          Column({ space: UiTheme.gapXs }) {
            Text('严重等级分布')
              .fontSize(UiTheme.fontSizeSection)
              .fontWeight(600)
              .fontColor(UiTheme.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(1)

            Text('按 BDI-II 四档统计')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(1)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

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
        .width('100%')
        .padding(UiTheme.cardPadding)
        .alignItems(HorizontalAlign.Start)
      }
    }

    // ── BDI 日均趋势（折线 + 两条阈值线）· 6 号位 ──
    RevealCard({ order: 6 }) {
      RippleCard({
        _enabled: false,
        _clickable: true,
        _pressScale: 0.98,
        _padding: 0
      }) {
        Column({ space: UiTheme.gapM }) {
          Column({ space: UiTheme.gapXs }) {
            Text('BDI 日均趋势')
              .fontSize(UiTheme.fontSizeSection)
              .fontWeight(600)
              .fontColor(UiTheme.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(1)

            Text('按检测日期聚合的日均分')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(1)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

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
        .width('100%')
        .padding(UiTheme.cardPadding)
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  /**
   * 次级 KPI 小卡（三张等宽并排 · 白底 + 16 圆角 + 极淡投影）
   * 标签 12/辅助色 在上，数字 20/600/一级色 + 单位 10 在下
   *
   * ★ 宽度靠 `.width('100%')` 撑满外层 `RevealCard` 的槽位，自己**不写** `layoutWeight`：
   *   主轴均分由 `RevealCard({ _weight: 1 })` 决定，本组件只需把那一格填满。
   */
  @Builder
  smallKpi(title: string, value: string, unit: string) {
    // 三张小卡与两张图卡共用同一套按压语言：按下轻微内缩 + 系统涟漪，松手不跳转。
    // 卡片视觉（白底 / 16 圆角 / 极淡投影）由 RippleCard 内联画，这里只留版式。
    RippleCard({
      _enabled: false,
      _clickable: true,
      _pressScale: 0.98,
      _padding: 0
    }) {
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
      .width('100%')
      .height(UiTheme.kpiSmallHeight)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding(UiTheme.kpiSmallPadding)
    }
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
