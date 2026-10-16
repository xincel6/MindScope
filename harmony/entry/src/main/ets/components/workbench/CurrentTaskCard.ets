/**
 * CurrentTaskCard · 工作台「当前任务」区块
 *
 * 两种形态：
 *   ① 无任务 → 一个**不可点**的空态卡片，文案「暂无进行中的分析」；
 *   ② 有任务 → 可点卡片（涟漪），显示素材名 / 状态 / 进度或分数，点击回到分析详情页。
 *
 * ★ 为什么空态也要画成卡片：工作台"所有内容都是卡片"是本轮的统一风格，
 *   空态如果只留一行灰字，视觉上会像页面没加载完。
 *
 * ★ 状态文案与颜色都来自 `TaskStatus`，不在这里做业务判断
 *   （"跑完了没有"是 AppStore 的事，组件只管显示）。
 */

import { UiTheme } from '../../common/UiTheme';
import { CurrentTaskModel, TaskStatus } from '../../types/Index';
import { RippleCard } from '../RippleCard';
import { ProgressBar } from '../common/ProgressBar';
import { StatusDot } from './StatusDot';

@ComponentV2
export struct CurrentTaskCard {
  /** 当前任务 · null 表示没有进行中的分析 */
  @Param task: CurrentTaskModel | null = null;

  /** 点「当前任务」卡片 · 窗口层重新打开分析详情页 */
  @Param onOpen: () => void = () => {};

  /** 状态中文标签 */
  @Computed
  get statusLabel(): string {
    const task: CurrentTaskModel | null = this.task;
    if (task === null) {
      return '';
    }
    if (task.status === TaskStatus.running) {
      return '分析中';
    }
    if (task.status === TaskStatus.done) {
      return '已完成';
    }
    if (task.status === TaskStatus.failed) {
      return '分析失败';
    }
    return '未开始';
  }

  /** 状态圆点颜色 */
  @Computed
  get statusColor(): string {
    const task: CurrentTaskModel | null = this.task;
    if (task === null) {
      return UiTheme.textSecondary;
    }
    if (task.status === TaskStatus.failed) {
      return UiTheme.danger;
    }
    if (task.status === TaskStatus.done) {
      return UiTheme.statusOnline;
    }
    return UiTheme.primary;
  }

  /** 分数文案（没出分时给一个中性占位，不显示 0.0 以免被误读成"分数是零"） */
  @Computed
  get scoreText(): string {
    const task: CurrentTaskModel | null = this.task;
    if (task === null || task.bdiScore <= 0) {
      return '--';
    }
    return task.bdiScore.toFixed(1);
  }

  /** 一句话说明 */
  @Computed
  get hint(): string {
    const task: CurrentTaskModel | null = this.task;
    if (task === null) {
      return '';
    }
    if (task.status === TaskStatus.failed) {
      return task.errorMsg.length > 0 ? task.errorMsg : '分析失败，可重新发起';
    }
    if (task.status === TaskStatus.done) {
      return '点击查看分析详情';
    }
    return '离开本页后分析会继续，点击可回到详情';
  }

  /** 区块标题行 */
  @Builder
  sectionTitle() {
    Text('当前任务')
      .fontSize(UiTheme.fontSizeSection)
      .fontWeight(FontWeight.Medium)
      .fontColor(UiTheme.textPrimary)
      .width('100%')
      .textAlign(TextAlign.Start)
  }

  /** 空态卡片 · 不可点（没有可跳转的目标） */
  @Builder
  emptyCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapS }) {
        Text('暂无进行中的分析')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('选择素材后会在这里挂载当前任务')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 任务卡片 · 可点，回到分析详情页 */
  @Builder
  taskCard(task: CurrentTaskModel) {
    RippleCard({
      onTap: () => {
        this.onOpen();
      }
    }) {
      Column({ space: UiTheme.gapM }) {
        // 第一行：素材名 + 状态圆点与标签
        Row({ space: UiTheme.gapS }) {
          Text(task.mediaName)
            .fontSize(UiTheme.fontSizeBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)

          StatusDot({ dotColor: this.statusColor, dotSize: 6 })

          Text(this.statusLabel)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(this.statusColor)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 第二行：进度（分析中）或分数（已完成/失败）
        if (task.status === TaskStatus.running) {
          ProgressBar({ ratio: task.progress, barColor: UiTheme.primary, barHeight: 6 })
        } else {
          Row({ space: UiTheme.gapS }) {
            Text(this.scoreText)
              .fontSize(UiTheme.fontSizeMetric)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.statusColor)

            Text('BDI')
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textSecondary)
              .margin({ bottom: UiTheme.gapS })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }

        Text(this.hint)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Column({ space: UiTheme.gapM }) {
      this.sectionTitle()

      if (this.task === null) {
        this.emptyCard()
      } else {
        this.taskCard(this.task)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
