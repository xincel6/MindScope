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
 * ════════════════ 本轮（「当前任务」加内容 · 与行卡拉差异）════════════════
 * 用户反馈：本卡与下面的「最近使用的素材」行卡几乎同构（缩略图｜名称｜分数｜进度条），
 * 一眼看不出"这是一件正在推进的事"。本轮加了四样东西，**全部只用现成令牌与基础容器**：
 *   ① **阶段指示器**（核心）：底部一行 `上传 → 逐帧推理 → 汇总评分`，
 *      三个 8vp 圆点 + 1vp 连接线，当前阶段实心主色、已过 60% 主色、未达空心浅灰；
 *      阶段由 `task.progress` / `task.status` 推导（规则见 `stageIndex`）。
 *   ② **状态胶囊**：把"圆点 + 文字"升级成右上角胶囊（22 高 / 11 圆角 / 8 内边距），
 *      底色按状态分类（进行中淡主色 / 完成浅绿 / 失败浅红），文字色沿用 `statusColor`。
 *   ③ **档位色竖条**：卡片左侧 4vp 圆角竖条，颜色 = `severityColor` ——
 *      "这张卡在为某个严重度服务"一眼可读，也是与行卡最直接的形态差异。
 *   ④ **空态也有形**：左侧换成中性 `divider` 竖条，并加一个 44vp 圆底单字图标块。
 *
 * ★ 竖条为什么用 `border-left` 而不是"4vp 宽的 Row"：
 *   宽度固定的横排子节点要靠 `height('100%')` 才能撑满卡片高度，而百分比高度在
 *   **内容自适应高度**的父容器里会解析成 0（`BUG清单.md` 记过"卡片整片不可见"）。
 *   border 画在元素自身盒子上，高度天然等于内容高度，零测量风险、零新增节点。
 *   同一做法在 `AuthAlert`（左侧撞击条）上已真机验收过。
 *
 * ★ 不引图片：阶段轨道与空态图标块都是 Row / Text / 描边，没有新增任何资源文件。
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
 *   ★ 本轮新增的阶段指示器同样受这条纪律约束：三个阶段的颜色/透明度/文字色
 *     各自是一个 `@Computed`（`stage0Ring` … `stage2Text`），而不是给 builder 传下标。
 */

import { UiTheme } from '../../common/UiTheme';
import { CurrentTaskModel, MediaType, TaskStatus } from '../../types/Index';
import { RippleCard } from '../RippleCard';
import { ProgressBar } from '../common/ProgressBar';
import { StatusDot } from './StatusDot';

/** 首帧照片尚未到达时的占位字形（与「最近使用的素材」保持同一套字形） */
const IMAGE_GLYPH: string = '图';
const VIDEO_GLYPH: string = '视';

/** 空态圆底图标块里的单字（"任务"的"任"，比画一个图标省事且不引资源） */
const EMPTY_GLYPH: string = '任';

/** 左侧档位色竖条宽度（与 `AuthAlert` 的撞击条同宽，视觉语言一致） */
const RAIL_WIDTH: number = 4;

/** 阶段圆点直径 / 连接线高度 */
const STAGE_DOT_SIZE: number = 8;
const STAGE_LINK_HEIGHT: number = 1;

/** 状态胶囊：高 22 / 圆角取高度一半 / 左右内边距 8 */
const CAPSULE_HEIGHT: number = 22;
const CAPSULE_RADIUS: number = 11;

/** 空态圆底图标块直径 */
const EMPTY_ICON_SIZE: number = 44;

/** 阶段下标（语义化，避免 builder 里出现魔法数字 0/1/2） */
const STAGE_UPLOAD: number = 0;
const STAGE_INFERENCE: number = 1;
const STAGE_SUMMARY: number = 2;

/** 某个阶段的视觉状态：还没到 / 已走过 / 正卡在这一段 */
const VIS_PENDING: number = 0;
const VIS_PASSED: number = 1;
const VIS_CURRENT: number = 2;

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

  /** 状态圆点 / 状态文字颜色（胶囊的文字与圆点都用它） */
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

  // ══════════════ 本轮新增派生值：状态胶囊底色 / 左侧竖条色 ══════════════

  /**
   * 状态胶囊底色 · 只表达"这属于哪一类状态"，不承载情报（文字色另由 `statusColor` 负责）
   *
   * ★ 完成态要"浅绿底"，而本轮 `UiTheme` 锁定、**不许新增令牌**：
   *   复用同值 `#E8F6EF` 的 `kpiGradientStart`（统计页浅薄荷渐变起点色），
   *   而不是在这里写死一个字面量色值 —— 用户调主题时它仍能跟着变。
   * ★ 未开始/未知态落 `fillSoft`：此时既没在跑也没结果，不该给任何色调暗示。
   */
  @Computed
  get capsuleBg(): string {
    const task: CurrentTaskModel | null = this.task;
    if (task === null) {
      return UiTheme.fillSoft;
    }
    if (task.status === TaskStatus.failed) {
      return UiTheme.dangerSoft;
    }
    if (task.status === TaskStatus.done) {
      return UiTheme.kpiGradientStart;
    }
    if (task.status === TaskStatus.running) {
      return UiTheme.cardPressTint;
    }
    return UiTheme.fillSoft;
  }

  /**
   * 卡片左侧竖条颜色
   * ★ 有任务 = 档位色：竖条回答"这张卡在为哪个严重度服务"，是它与行卡最直接的形态差异；
   * ★ 空态 = 中性 `divider`：没有数据就不该有颜色在暗示档位。
   */
  @Computed
  get railColor(): string {
    return this.hasTask ? this.severityColor : UiTheme.divider;
  }

  // ══════════════ 本轮新增派生值：阶段指示器（下标 + 每段三件套）══════════════
  //
  // 为什么每段要三个独立 @Computed（而不是给 builder 传下标）：
  //   @Builder 参数按值传递，第一阶段快照之后就再不更新（BUG-19）。
  //   拆成 getter 看起来啰嗦，但换来的是"阶段跟着 progress 走"这条唯一的数据通路。
  //
  // 阶段规则（用户指定）：
  //   progress < 0.15            → 上传
  //   0.15 ≤ progress < 0.95     → 逐帧推理
  //   progress ≥ 0.95 或 done    → 汇总评分
  //   failed                     → 停在出错那一刻所在的那一段，并把该段染 danger

  /**
   * 当前阶段下标（0 上传 / 1 逐帧推理 / 2 汇总评分）
   * ★ `done` 直接收敛到 2：服务端落库后 progress 可能停在 0.99，不能只靠阈值兜底。
   * ★ `failed` **不跳阶段**：停在 progress 指向的那一段，用户才知道"挂在哪一步"。
   */
  @Computed
  get stageIndex(): number {
    const task: CurrentTaskModel | null = this.task;
    if (task === null) {
      return STAGE_UPLOAD;
    }
    if (task.status === TaskStatus.done || task.progress >= 0.95) {
      return STAGE_SUMMARY;
    }
    if (task.progress < 0.15) {
      return STAGE_UPLOAD;
    }
    return STAGE_INFERENCE;
  }

  /** 当前阶段是否已经失败（决定那一段的圆点与文字是否改染 danger） */
  @Computed
  get stageFailed(): boolean {
    const task: CurrentTaskModel | null = this.task;
    return task !== null && task.status === TaskStatus.failed;
  }

  /**
   * 某一段处在"未达 / 已过 / 当前"哪一态
   * ★ 抽成方法而不是三段各写一遍 if：三段必须共用**同一套**规则，
   *   分开写迟早出现"第一段已过、第三段还算当前"这种自相矛盾的显示。
   */
  private stageVisualAt(index: number): number {
    if (index === this.stageIndex) {
      return VIS_CURRENT;
    }
    return index < this.stageIndex ? VIS_PASSED : VIS_PENDING;
  }

  /** 圆点描边色：未达 = fillSoft（"空心"的那一圈）；其余 = 主色，当前段失败时染 danger */
  private stageRingAt(index: number): string {
    const visual: number = this.stageVisualAt(index);
    if (visual === VIS_PENDING) {
      return UiTheme.fillSoft;
    }
    if (visual === VIS_CURRENT && this.stageFailed) {
      return UiTheme.danger;
    }
    return UiTheme.primary;
  }

  /** 圆点填充色：未达 = 卡片白（配 fillSoft 描边即"空心"）；其余与描边同色 → 实心 */
  private stageFillAt(index: number): string {
    const visual: number = this.stageVisualAt(index);
    return visual === VIS_PENDING ? UiTheme.cardBackground : this.stageRingAt(index);
  }

  /** 圆点透明度：已过 60%（"走过但不再是焦点"），当前/未达都保持 1 */
  private stageOpacityAt(index: number): number {
    return this.stageVisualAt(index) === VIS_PASSED ? 0.6 : 1;
  }

  /** 阶段文字色：当前段 = 正文色（失败染 danger），其余 = 次要文字色 */
  private stageTextAt(index: number): string {
    const visual: number = this.stageVisualAt(index);
    if (visual === VIS_CURRENT) {
      return this.stageFailed ? UiTheme.danger : UiTheme.textPrimary;
    }
    return UiTheme.textSecondary;
  }

  // ── 阶段 0「上传」──

  @Computed
  get stage0Ring(): string {
    return this.stageRingAt(STAGE_UPLOAD);
  }

  @Computed
  get stage0Fill(): string {
    return this.stageFillAt(STAGE_UPLOAD);
  }

  @Computed
  get stage0Opacity(): number {
    return this.stageOpacityAt(STAGE_UPLOAD);
  }

  @Computed
  get stage0Text(): string {
    return this.stageTextAt(STAGE_UPLOAD);
  }

  // ── 阶段 1「逐帧推理」──

  @Computed
  get stage1Ring(): string {
    return this.stageRingAt(STAGE_INFERENCE);
  }

  @Computed
  get stage1Fill(): string {
    return this.stageFillAt(STAGE_INFERENCE);
  }

  @Computed
  get stage1Opacity(): number {
    return this.stageOpacityAt(STAGE_INFERENCE);
  }

  @Computed
  get stage1Text(): string {
    return this.stageTextAt(STAGE_INFERENCE);
  }

  // ── 阶段 2「汇总评分」──

  @Computed
  get stage2Ring(): string {
    return this.stageRingAt(STAGE_SUMMARY);
  }

  @Computed
  get stage2Fill(): string {
    return this.stageFillAt(STAGE_SUMMARY);
  }

  @Computed
  get stage2Opacity(): number {
    return this.stageOpacityAt(STAGE_SUMMARY);
  }

  @Computed
  get stage2Text(): string {
    return this.stageTextAt(STAGE_SUMMARY);
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

  /**
   * 状态胶囊徽标（卡片右上角）
   *
   * ★ 从"圆点 + 一行文字"升级成胶囊：底色把状态从**一句话**变成**一枚标签**，
   *   与「最近使用的素材」行卡里那行裸文字状态形成明显的形态差异。
   * ★ 文字与圆点仍用 `statusColor`（危险/成功/主色），底色只负责分类：
   *   状态"是什么"靠文字，颜色只做辅助 —— 只靠颜色区分对色觉障碍用户不可读。
   */
  @Builder
  statusCapsule() {
    Row({ space: UiTheme.gapXs }) {
      StatusDot({ dotColor: this.statusColor, dotSize: 6 })

      Text(this.statusLabel)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(this.statusColor)
        .maxLines(1)
    }
    .height(CAPSULE_HEIGHT)
    .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
    .borderRadius(CAPSULE_RADIUS)
    .backgroundColor(this.capsuleBg)
    .alignItems(VerticalAlign.Center)
  }

  /** 阶段 0 · 上传（圆点 + 段名，尺寸三段一致，只有颜色/透明度不同） */
  @Builder
  stageUpload() {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(STAGE_DOT_SIZE)
        .height(STAGE_DOT_SIZE)
        .borderRadius(STAGE_DOT_SIZE / 2)
        .backgroundColor(this.stage0Fill)
        .border({ width: 1, color: this.stage0Ring })
        .opacity(this.stage0Opacity)

      Text('上传')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(this.stage0Text)
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 阶段 1 · 逐帧推理 */
  @Builder
  stageInference() {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(STAGE_DOT_SIZE)
        .height(STAGE_DOT_SIZE)
        .borderRadius(STAGE_DOT_SIZE / 2)
        .backgroundColor(this.stage1Fill)
        .border({ width: 1, color: this.stage1Ring })
        .opacity(this.stage1Opacity)

      Text('逐帧推理')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(this.stage1Text)
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 阶段 2 · 汇总评分 */
  @Builder
  stageSummary() {
    Row({ space: UiTheme.gapXs }) {
      Row()
        .width(STAGE_DOT_SIZE)
        .height(STAGE_DOT_SIZE)
        .borderRadius(STAGE_DOT_SIZE / 2)
        .backgroundColor(this.stage2Fill)
        .border({ width: 1, color: this.stage2Ring })
        .opacity(this.stage2Opacity)

      Text('汇总评分')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(this.stage2Text)
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 阶段之间的连接细线（1vp · divider）
   * ★ 用 `layoutWeight(1)` 而不是写死宽度：卡片宽度随屏幕变，
   *   写死的连线会在窄屏上把「逐帧推理」挤成两行；权重分配由布局引擎算。
   */
  @Builder
  stageLink() {
    Row()
      .layoutWeight(1)
      .height(STAGE_LINK_HEIGHT)
      .backgroundColor(UiTheme.divider)
      .margin({ left: UiTheme.gapS, right: UiTheme.gapS })
  }

  /**
   * 阶段指示器 · `上传 → 逐帧推理 → 汇总评分`
   *
   * ★ 这是本卡与「最近使用的素材」行卡**最核心**的差异：行卡只有"一条记录"的分数，
   *   这里画的是"一件事推进到哪一步"，读起来是流程而不是清单。
   * ★ 只用 Row / Text / 描边 + 令牌，不引图片、不新增资源 —— 复用图标完全够用。
   */
  @Builder
  stageRail() {
    Row() {
      this.stageUpload()
      this.stageLink()
      this.stageInference()
      this.stageLink()
      this.stageSummary()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 空态卡片 · 不可点（没有可跳转的目标）
   * ★ 本轮给它加了"形状"：44vp 圆底单字块 + 左侧中性竖条。
   *   纯两行灰字在灰页底上看起来像页面没加载完，也与行卡更难区分。
   */
  @Builder
  emptyCard() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Row({ space: UiTheme.gapM }) {
        // 圆底图标块（skeletonFill 比 fillSoft 深一档，坐在白卡里也辨得出来）
        Column() {
          Text(EMPTY_GLYPH)
            .fontSize(20)
            .fontColor(UiTheme.textSecondary)
        }
        .width(EMPTY_ICON_SIZE)
        .height(EMPTY_ICON_SIZE)
        .borderRadius(EMPTY_ICON_SIZE / 2)
        .backgroundColor(UiTheme.skeletonFill)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: UiTheme.gapXs }) {
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
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: RAIL_WIDTH + UiTheme.gapM })
      .borderRadius(RAIL_WIDTH / 2)
      .border({ width: { left: RAIL_WIDTH }, color: { left: this.railColor } })
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
        // ── 第一行：首帧照片 ｜ 素材名 + 档位 ｜ 状态胶囊 + BDI 分数 ──
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

            if (this.severityLabel.length > 0) {
              Text(this.severityLabel)
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(this.severityColor)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 胶囊钉在右上角，分数在它下面（右对齐，宽度由内容决定）
          Column({ space: UiTheme.gapXs }) {
            this.statusCapsule()

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
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // ── 第二行：BDI 进度条（条长 = 分数 / 63，颜色 = 档位色）──
        ProgressBar({
          ratio: this.severityRatio,
          barColor: this.severityColor,
          barHeight: 6
        })

        // ── 第三行：阶段指示器（上传 → 逐帧推理 → 汇总评分）──
        this.stageRail()

        // ── 第四行：一句话说明 ──
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
      // 档位色竖条：用 border-left 表达（高度天然等于内容高度，见文件头说明）
      .padding({ left: RAIL_WIDTH + UiTheme.gapM })
      .borderRadius(RAIL_WIDTH / 2)
      .border({ width: { left: RAIL_WIDTH }, color: { left: this.railColor } })
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
