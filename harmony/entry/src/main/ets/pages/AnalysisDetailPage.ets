/**
 * AnalysisDetailPage · **分析详情页（本轮为占位页）**
 *
 * 页面契约（★ 直接传入参数即可展示本页，页面内不引用任何 store）：
 * ```ts
 * const param = new AnalysisDetailPageParam();
 * param.mediaName = 'interview.mp4';
 * param.status = TaskStatus.running;
 * param.progress = 0.63;
 * param.onBack = () => { stack.pop(); };
 * ```
 *
 * ────────────────── 本轮它是"占位页"，但哪些是真的 ──────────────────
 * 真数据（来自 WebSocket）：进度、帧数、BDI 分数、档位标签与颜色、VLM 文本、错误。
 * 占位（图表组件未实现）：折线图、严重度饼图、注意力热力图。
 * 所以本页**不是**一个空壳 —— 跳转链路与数据链路都能被验证，
 * 只是"把数据画出来"这一层留到下一轮。
 *
 * ★ 返回不停止分析（用户本轮确认）：分析会话挂在 `AppStore` 单例上，
 *   本页 `aboutToDisappear` **故意不调** `stopAnalysis()`，
 *   这样用户回到工作台后「当前任务」仍在推进，再点回来能看到最新进度。
 */

import { UiTheme } from '../common/UiTheme';
import { AnalysisDetailPageParam } from '../types/PageParams';
import { TaskStatus } from '../types/Index';
import { PageHeader } from '../components/PageHeader';
import { RippleCard } from '../components/RippleCard';
import { ProgressBar } from '../components/common/ProgressBar';

@ComponentV2
export struct AnalysisDetailPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: AnalysisDetailPageParam = new AnalysisDetailPageParam();

  // ══════════════════ 派生文案（全部只读参数，无本地状态）══════════════════

  /** 状态中文标签 */
  @Computed
  get statusLabel(): string {
    const status: TaskStatus = this.pageParam.status;
    if (status === TaskStatus.running) {
      return '分析中';
    }
    if (status === TaskStatus.done) {
      return '已完成';
    }
    if (status === TaskStatus.failed) {
      return '分析失败';
    }
    return '未开始';
  }

  /** 状态标签颜色 · 运行中用主色，完成用分数档位色，失败用错误色 */
  @Computed
  get statusColor(): string {
    const status: TaskStatus = this.pageParam.status;
    if (status === TaskStatus.failed) {
      return UiTheme.danger;
    }
    if (status === TaskStatus.done && this.pageParam.severityColor.length > 0) {
      return this.pageParam.severityColor;
    }
    return UiTheme.primary;
  }

  /** 进度百分比文案 */
  @Computed
  get progressText(): string {
    const ratio: number = this.pageParam.progress;
    if (!Number.isFinite(ratio) || ratio <= 0) {
      return '0%';
    }
    const percent: number = ratio >= 1 ? 100 : Math.round(ratio * 100);
    return `${percent}%`;
  }

  /** 是否已经有分数可展示 */
  @Computed
  get hasScore(): boolean {
    return this.pageParam.bdiScore > 0;
  }

  /** 分数文案（保留一位小数，与后端 `round(final_score, 2)` 的口径一致但更适合阅读） */
  @Computed
  get scoreText(): string {
    if (!this.hasScore) {
      return '--';
    }
    return this.pageParam.bdiScore.toFixed(1);
  }

  /** 顶部一句话状态说明 */
  @Computed
  get statusHint(): string {
    // ★ 历史快照（从「最近使用的素材」进入）：没有实时会话，不能承诺"收帧中"这类实时语义
    if (!this.pageParam.followLiveTask) {
      return '这是该素材最近一次分析的报告快照，图表区待实现';
    }
    const status: TaskStatus = this.pageParam.status;
    if (status === TaskStatus.running) {
      return `服务端正在逐帧推理，已收到 ${this.pageParam.frameCount} 帧`;
    }
    if (status === TaskStatus.done) {
      return '分析已完成，报告已写入服务端';
    }
    if (status === TaskStatus.failed) {
      return '分析中断，可返回工作台重新发起';
    }
    return '等待开始';
  }

  // ══════════════════ 图表占位块 ══════════════════

  /**
   * 占位块 · 明确写出"这里将来放什么、什么时候有"
   * ★ 不做灰色假图表：拿假数据画出来的图，评审时无法区分"画错了"与"还没画"。
   */
  @Builder
  chartPlaceholder(title: string, hint: string, chartHeight: number) {
    Column({ space: UiTheme.gapS }) {
      Text(title)
        .fontSize(UiTheme.fontSizeBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)

      Column({ space: UiTheme.gapXs }) {
        Text('图表组件待实现')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
        Text(hint)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height(chartHeight)
      .borderRadius(UiTheme.cardRadius)
      .backgroundColor(UiTheme.fillSoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: UiTheme.gapL }) {
      PageHeader({
        title: '分析详情',
        subtitle: this.pageParam.mediaName,
        showBack: true,
        onBack: () => {
          this.pageParam.onBack();
        }
      })

      Scroll() {
        Column({ space: UiTheme.gapL }) {
          // ── ① 素材与状态卡 ──
          RippleCard({ _enabled: false, _clickable: false }) {
            Column({ space: UiTheme.gapM }) {
              Row({ space: UiTheme.gapS }) {
                Text(this.pageParam.mediaName)
                  .fontSize(UiTheme.fontSizeSection)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(UiTheme.textPrimary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Start)

                Text(this.statusLabel)
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(this.statusColor)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Row({ space: UiTheme.gapS }) {
                Text(this.pageParam.mediaTypeLabel)
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
                Text('·')
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
                Text(`素材 id ${this.pageParam.mediaId}`)
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
              }
              .width('100%')

              Text(this.statusHint)
                .fontSize(UiTheme.fontSizeBody)
                .fontColor(UiTheme.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Start)

              // 进度条（真实数据）
              ProgressBar({
                ratio: this.pageParam.progress,
                barColor: this.statusColor,
                barHeight: 8
              })

              Row() {
                Text('分析进度')
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Start)
                Text(this.progressText)
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.textPrimary)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ── ② 分数卡（重要分数用大字号 32vp，符合规范） ──
          RippleCard({ _enabled: false, _clickable: false }) {
            Column({ space: UiTheme.gapS }) {
              Text('辅助评估分数')
                .fontSize(UiTheme.fontSizeSection)
                .fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.textPrimary)
                .width('100%')
                .textAlign(TextAlign.Start)

              Row({ space: UiTheme.gapS }) {
                Text(this.scoreText)
                  .fontSize(UiTheme.fontSizeMetric)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.hasScore ? this.statusColor : UiTheme.textSecondary)

                Text('BDI')
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.textSecondary)
                  .margin({ bottom: UiTheme.gapS })

                if (this.pageParam.severityLabel.length > 0) {
                  Text(this.pageParam.severityLabel)
                    .fontSize(UiTheme.fontSizeBody)
                    .fontColor(this.pageParam.severityColor)
                    .margin({ bottom: UiTheme.gapS })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Bottom)

              Text('分数范围为 0–63，越高表示抑郁倾向越明显')
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(UiTheme.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ── ③ 图表占位区（本轮的核心"留白"） ──
          RippleCard({ _enabled: false, _clickable: false }) {
            Column({ space: UiTheme.gapL }) {
              this.chartPlaceholder(
                '情绪曲线（折线图）',
                '逐帧 BDI 分数的走势，按帧序号为横轴',
                140
              )
              this.chartPlaceholder(
                '严重度分布（饼图）',
                '本次分析各档位帧数占比',
                140
              )
              this.chartPlaceholder(
                '注意力热力图（16×16）',
                '模型关注的面部区域，随最近一帧刷新',
                140
              )
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ── ④ VLM 文本解读（有才显示：不是所有素材都会触发） ──
          if (this.pageParam.vlmText.length > 0) {
            RippleCard({ _enabled: false, _clickable: false }) {
              Column({ space: UiTheme.gapS }) {
                Text('智能解读')
                  .fontSize(UiTheme.fontSizeSection)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(UiTheme.textPrimary)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                Text(this.pageParam.vlmText)
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.textPrimary)
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }

          // ── ⑤ 错误提示 ──
          if (this.pageParam.errorMsg.length > 0) {
            RippleCard({ _enabled: false, _clickable: false }) {
              Text(this.pageParam.errorMsg)
                .fontSize(UiTheme.fontSizeBody)
                .fontColor(UiTheme.danger)
                .width('100%')
                .textAlign(TextAlign.Start)
            }
          }

          // ── ⑥ 取消分析（弱化：★ 视频场景服务端早已算完，取消基本无效） ──
          //    ★ 只在"实时任务且正在跑"时出现：历史快照没有可取消的会话
          if (this.pageParam.followLiveTask && this.pageParam.status === TaskStatus.running) {
            Button('取消分析')
              .width('100%')
              .height(44)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textSecondary)
              .backgroundColor(Color.Transparent)
              .borderWidth(1)
              .borderColor(UiTheme.divider)
              .borderRadius(UiTheme.buttonRadius)
              .onClick(() => {
                this.pageParam.onCancelAnalysis();
              })

            Text('提示：视频分析在服务端处理得很快，取消可能不会生效')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .padding({ bottom: UiTheme.gapXl })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: UiTheme.pagePadding, right: UiTheme.pagePadding, top: UiTheme.gapL })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }
}
