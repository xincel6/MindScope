/**
 * CurrentTaskCard · 工作台「当前任务」区块
 *
 * 两种形态：
 *   ① 无任务 → 一个**不可点**的空态卡片，文案「暂无进行中的分析」；
 *   ② 有任务 → 可点卡片（涟漪），显示**首帧照片 / 素材名 / 状态 / BDI 分数与档位 /
 *      BDI 进度条**，点击回到分析详情页。
 *
 * ────────────────── 本轮（工作台二次打磨）的两处改动 ──────────────────
 * ① **位置**：整块（含「当前任务」标题）移到「开始新的辅助评估」**上方**。
 *    理由（用户提出）：有任务在跑的时候，它比"发起一次新评估"更需要被看到。
 * ② **内容**：加「首帧照片」+「表示 BDI 的进度条」（用户要求）。
 *    · 照片取自 `task.firstFrameUrl`，取值顺序（首帧对齐人脸 → 图片的媒体缩略图 → 空串占位）
 *      **全部在 `AppStore.currentTask()` 里决定**，本组件只负责画，不做数据判断；
 *    · 进度条：条长 = `task.scoreRatio`（= BDI / 63），颜色 = `task.severityColor`
 *      （四档严重度色），口径与「最近使用的素材」完全一致 —— **越长越严重**。
 *
 * ★ 为什么进度条只表达 BDI、不再兼做"分析进度"：
 *   一根条同时表示"跑了多少"和"病得多重"会让人无法判断它到底在说什么。
 *   分析进度改用状态文案里的百分比（「分析中 42%」），两者一眼可分。
 *
 * ★ 空态也画成卡片：工作台"所有内容都是卡片"是本轮的统一风格，
 *   空态如果只留一行灰字，视觉上会像页面没加载完。
 *
 * ══════════════════ ★★ 为什么这里的 @Builder 一律**不带参数** ══════════════════
 * 本轮实装时踩到一个"编译通过、界面不更新"的隐形坑（已记入 `BUG清单.md` BUG-19）：
 *
 *   最初写成 `@Builder taskCard(task: CurrentTaskModel)` + `this.taskCard(this.task)`。
 *   实测：卡片的**照片、档位标签、档位颜色、进度条填充**全部停在"刚创建任务那一刻"
 *   的值（分数 0 → 进度条空、标签空、颜色中性），而 `Text(this.scoreText)` 这种
 *   **@Computed 表达式**却能更新到 11.7 —— 同一张卡片里一半新一半旧。
 *
 *   原因：`@Builder` 的参数是**按值传递**的。`this.taskCard(this.task)` 只在**首次**
 *   构建时把当时的对象交进去；之后 `@Param task` 换了新对象，ArkUI 只会更新
 *   那些**直接依赖响应式变量**的表达式（`this.scoreText` 属于此类），
 *   而 builder 内部捕获的那个局部 `task` 参数不会跟着变。
 *
 *   所以本组件的纪律是：**builder 一律无参，值全部从 `this.*` 的 `@Computed` 里读**。
 *   这样照片/标签/颜色/进度条与分数走同一条响应式路径，不会再出现"一半新一半旧"。
 */

import { UiTheme } from '../../common/UiTheme';
import { CurrentTaskModel, MediaType, TaskStatus } from '../../types/Index';
import { RippleCard } from '../RippleCard';
import { ProgressBar } from '../common/ProgressBar';
import { StatusDot } from './StatusDot';

/** 首帧照片尚未到达时的占位字形（与「最近使用的素材」保持同一套字形） */
const IMAGE_GLYPH: string = '图';
const VIDEO_GLYPH: string = '视';

@ComponentV2
export struct CurrentTaskCard {
  /** 当前任务 · null 表示没有进行中的分析 */
  @Param task: CurrentTaskModel | null = null;

  /** 点「当前任务」卡片 · 窗口层重新打开分析详情页 */
  @Param onOpen: () => void = () => {};

  // ══════════════════ 派生值（★ 全部走 @Computed，builder 不接参数，见文件头）══════════════════

  /** 是否有任务（决定整块卡片走哪个分支） */
  @Computed
  get hasTask(): boolean {
    return this.task !== null;
  }

  /** 素材名 */
  @Computed
  get taskName(): string {
    const task: CurrentTaskModel | null = this.task;
    return task === null ? '' : task.mediaName;
  }

  /** 首帧照片地址（空串 → 画占位块） */
  @Computed
  get firstFrameUrl(): string {
    const task: CurrentTaskModel | null = this.task;
    return task === null ? '' : task.firstFrameUrl;
  }

  /** 照片缺失时的占位字形 */
  @Computed
  get mediaGlyph(): string {
    const task: CurrentTaskModel | null = this.task;
    if (task === null) {
      return IMAGE_GLYPH;
    }
    return task.mediaType === MediaType.video ? VIDEO_GLYPH : IMAGE_GLYPH;
  }

  /**
   * 状态中文标签
   * ★ 运行中带上分析进度百分比：进度条已经被 BDI 占用，进度只能走文字。
   */
  @Computed
  get statusLabel(): string {
    const task: CurrentTaskModel | null = this.task;
    if (task === null) {
      return '';
    }
    if (task.status === TaskStatus.running) {
      if (task.progress <= 0) {
        return '分析中';
      }
      const ratio: number = task.progress >= 1 ? 1 : task.progress;
      return `分析中 ${Math.round(ratio * 100)}%`;
    }
    if (task.status === TaskStatus.done) {
      return '已完成';
    }
    if (task.status === TaskStatus.failed) {
      return '分析失败';
    }
    return '未开始';
  }

  /** 状态圆点 / 状态文字颜色 */
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

  /**
   * 分数文案
   * ★ 没出分时给 `--`，不显示 `0.0` —— 否则会被读成"这个人的 BDI 是零"。
   */
  @Computed
  get scoreText(): string {
    const task: CurrentTaskModel | null = this.task;
    if (task === null || task.bdiScore <= 0) {
      return '--';
    }
    return task.bdiScore.toFixed(1);
  }

  /** 档位中文标签（未出分时为空串 → 不渲染那一行） */
  @Computed
  get severityLabel(): string {
    const task: CurrentTaskModel | null = this.task;
    return task === null ? '' : task.severityLabel;
  }

  /** 档位色 / 中性色（未出分时由门面给中性色） */
  @Computed
  get severityColor(): string {
    const task: CurrentTaskModel | null = this.task;
    return task === null ? UiTheme.textSecondary : task.severityColor;
  }

  /** BDI 进度条填充比例 0–1 */
  @Computed
  get severityRatio(): number {
    const task: CurrentTaskModel | null = this.task;
    return task === null ? 0 : task.scoreRatio;
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

  // ══════════════════ 片段（★ 无参 builder）══════════════════

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

  /**
   * 首帧照片
   * ★ 地址为空时画占位块（视频刚上传、第一帧还没到）：不拿 `.mp4` 直链去喂 `Image`，
   *   那只会得到一片空白，还会让人以为卡片坏了。
   */
  @Builder
  firstFrame() {
    if (this.firstFrameUrl.length > 0) {
      Image(this.firstFrameUrl)
        .width(UiTheme.taskThumbSize)
        .height(UiTheme.taskThumbSize)
        .objectFit(ImageFit.Cover)
        .borderRadius(UiTheme.cardRadius)
        .backgroundColor(UiTheme.fillSoft)
        .border({ width: 1, color: UiTheme.divider })
    } else {
      Column() {
        Text(this.mediaGlyph)
          .fontSize(20)
          .fontColor(UiTheme.textSecondary)
      }
      .width(UiTheme.taskThumbSize)
      .height(UiTheme.taskThumbSize)
      .borderRadius(UiTheme.cardRadius)
      .backgroundColor(UiTheme.fillSoft)
      .border({ width: 1, color: UiTheme.divider })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
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
  taskCard() {
    RippleCard({
      onTap: () => {
        this.onOpen();
      }
    }) {
      Column({ space: UiTheme.gapM }) {
        // ── 第一行：首帧照片 ｜ 素材名 + 状态 ｜ BDI 分数 + 档位 ──
        Row({ space: UiTheme.gapM }) {
          this.firstFrame()

          Column({ space: UiTheme.gapXs }) {
            Text(this.taskName)
              .fontSize(UiTheme.fontSizeBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.textPrimary)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)

            Row({ space: UiTheme.gapXs }) {
              StatusDot({ dotColor: this.statusColor, dotSize: 6 })

              Text(this.statusLabel)
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(this.statusColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 分数与档位（右对齐，宽度由内容决定）
          Column({ space: UiTheme.gapXs }) {
            Row({ space: UiTheme.gapXs }) {
              Text(this.scoreText)
                .fontSize(UiTheme.fontSizeCardMetric)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.severityColor)

              Text('BDI')
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(UiTheme.textSecondary)
                .margin({ bottom: UiTheme.gapXs })
            }
            .alignItems(VerticalAlign.Bottom)

            if (this.severityLabel.length > 0) {
              Text(this.severityLabel)
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(this.severityColor)
            }
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // ── 第二行：BDI 进度条（条长 = 分数 / 63，颜色 = 档位色）──
        ProgressBar({
          ratio: this.severityRatio,
          barColor: this.severityColor,
          barHeight: 6
        })

        // ── 第三行：一句话说明 ──
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

      if (this.hasTask) {
        this.taskCard()
      } else {
        this.emptyCard()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
