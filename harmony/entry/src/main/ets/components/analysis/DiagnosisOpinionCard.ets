/**
 * DiagnosisOpinionCard · 工作台分析区「诊断意见」卡（本轮新增）
 *
 * ══════════════════ 这张卡解决什么问题 ══════════════════
 * 工作台此前把"分数 / 热力图 / 曲线 / 严重度 / 智能解读"都摊开了，但**没有结论落点**：
 * 医师看完一圈图表，仍要自己在脑子里合成一句话，也没有"我已复核"的动作可以留痕。
 * 这张卡把最后一步补上：
 *   ① **结论**：BDI-II 分数 + 档位 + 模型初判，一眼看到"这次评估说明什么"；
 *   ② **依据**：量表分 / 面部线索 / 时序特征三行，结论不是凭空来的；
 *   ③ **意见**：模型初稿可编辑，医师改完点「确认意见」，卡上留下"已确认 · 医师 · 时间"；
 *   ④ **边界**：固定免责声明，明确这是辅助参考、不能替代面诊。
 *
 * ────────────────── 为什么状态放在组件本地（本轮只做 UI）──────────────────
 * 用户本轮要求「只写鸿蒙 UI」：不新增接口、不改持久化、不碰报告表。
 * 因此"编辑中 / 已确认 / 确认时间"都是 `@Local`，离开页面即复位；
 * 这样既能真机点出完整交互，也不会留下"看起来已签名、实际没入库"的假数据。
 * 将来接后端时，只需要把 `confirmed` 换成 `AppStore` 的持久化字段，视图层不用改。
 *
 * ────────────────── 数据与视图的分工 ──────────────────
 * 本组件**不 import store**：分数、依据、初稿、医师名都由 `WorkbenchPage` 算成
 * `DiagnosisOpinionModel` 传入（与 `AnalysisHeroCard` 同一套约定）。
 * 原因见 hero 文件头：异步逐帧更新时，扁平投影不会因为 @Builder 按值传参而停在旧值。
 *
 * ★ 所有 @Builder 一律无参；取值全部走 @Computed / this.model.*（ArkTS 纪律）。
 * ★ 正文不小于 14fp，辅助说明 12fp；点击区不小于 40–44vp。
 */

import { UiTheme } from '../../common/UiTheme';
import { TaskStatus } from '../../types/Index';
import { StatusDot } from '../workbench/StatusDot';
import { ProgressBar } from '../common/ProgressBar';

/** 左侧档位竖条宽度（与 hero / AuthAlert 的撞击条同宽） */
const RAIL_WIDTH: number = 4;

/** 意见输入框高度（vp）· 约 5 行正文，再高会把卡片拉得过长 */
const EDITOR_HEIGHT: number = 132;

/** 意见最大字数 · 与输入框右下角计数保持一致 */
const MAX_OPINION_LEN: number = 240;

/** 状态胶囊高度 / 圆角 */
const CAPSULE_HEIGHT: number = 22;
const CAPSULE_RADIUS: number = 11;

/** 意见正文行高 */
const BODY_LINE_HEIGHT: number = 22;

/** 一条判断依据 */
export interface DiagnosisEvidenceModel {
  label: string;
  value: string;
}

/**
 * 诊断意见卡的只读投影
 * ★ 全部是扁平字段：页面异步更新时整对象重建，组件按值重绘。
 */
export interface DiagnosisOpinionModel {
  /** 当前素材 id · 换素材时组件据此清空本地编辑/确认态 */
  mediaId: string;
  /** 分析状态 */
  status: TaskStatus;
  /** 分析进度 0–1（仅生成中展示） */
  progress: number;
  /** 是否已出分且可生成意见 */
  ready: boolean;
  /** 素材名（空态文案里可能用到） */
  mediaName: string;
  /** 分数文案（'24.0'） */
  scoreText: string;
  /** 档位中文名（正常 / 轻度 / 中度 / 重度） */
  severityLabel: string;
  /** 档位色（数据表达色，不是 danger） */
  severityColor: string;
  /** 模型初判（一句话结论） */
  conclusion: string;
  /** 判断依据（2–3 行） */
  evidence: DiagnosisEvidenceModel[];
  /** 模型初稿（可编辑） */
  aiDraft: string;
  /** 签名医师（未登录时由页面给「当前医师」兜底） */
  doctorName: string;
  /** 时间说明（本次分析 / 上次分析 · MM-DD HH:mm） */
  timeText: string;
  /** 未就绪时的说明 */
  emptyHint: string;
}

/** 无数据兜底 · @Param 必须有默认值 */
export function emptyDiagnosisOpinionModel(): DiagnosisOpinionModel {
  return {
    mediaId: '',
    status: TaskStatus.none,
    progress: 0,
    ready: false,
    mediaName: '',
    scoreText: '--',
    severityLabel: '',
    severityColor: UiTheme.textSecondary,
    conclusion: '',
    evidence: [],
    aiDraft: '',
    doctorName: '',
    timeText: '',
    emptyHint: '等待分析数据'
  };
}

/** 两位补零（ArkTS 的 String 没有 padStart） */
function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 当前时刻 · "MM-DD HH:mm"（确认留痕用） */
function formatNow(): string {
  const now: Date = new Date();
  return `${pad2(now.getMonth() + 1)}-${pad2(now.getDate())} ${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
}

/** 进度比例 → 百分比文案 */
function percentOf(ratio: number): string {
  if (!Number.isFinite(ratio) || ratio <= 0) {
    return '0%';
  }
  if (ratio >= 1) {
    return '100%';
  }
  return `${Math.round(ratio * 100)}%`;
}

@ComponentV2
export struct DiagnosisOpinionCard {
  /** 只读投影 · 由工作台计算 */
  @Param model: DiagnosisOpinionModel = emptyDiagnosisOpinionModel();

  // ────────────────── 本地编辑态（只做 UI，不入库）──────────────────

  /** 输入框里的草稿 */
  @Local draft: string = '';

  /** 最近一次保存/确认的正文（非编辑态展示它） */
  @Local opinionText: string = '';

  /** 是否在编辑 */
  @Local editing: boolean = false;

  /** 是否已确认 */
  @Local confirmed: boolean = false;

  /** 确认时间 */
  @Local confirmedAt: string = '';

  /** 确认人 */
  @Local signedBy: string = '';

  /** 医师是否改过初稿（决定状态胶囊文案） */
  @Local edited: boolean = false;

  /** 已同步的素材 id（用来识别"换了患者"） */
  @Local lastMediaId: string = '';

  /** 已同步的模型初稿（用来识别"异步初稿到了"） */
  @Local lastDraft: string = '';

  /** 初始化 + 换素材时复位 */
  aboutToAppear(): void {
    this.lastMediaId = this.model.mediaId;
    this.resetForModel();
  }

  /**
   * model 投影变化时做两件事：换素材清空、初稿到达填充
   *
   * ★ 监听整个 `model`（@Param 引用变化），而不是 `model.mediaId` / `model.aiDraft`：
   *   本轮 CompileArkTS 对子字段路径给出告警
   *   "The '@Monitor' decorator needs to monitor the state variables that exist"，
   *   说明该写法在当前编译器上不会注册为可观察状态。改成整对象监听 + 本地比对，
   *   行为一致且不依赖子路径观察能力。
   */
  @Monitor('model')
  onModelChanged(): void {
    // 1) 换素材 → 清空上一条意见，避免 A 的"已确认"印章残留到 B
    if (this.model.mediaId !== this.lastMediaId) {
      this.lastMediaId = this.model.mediaId;
      this.resetForModel();
      return;
    }
    // 2) 初稿异步到达 → 未编辑、未确认、不在编辑中时自动填入
    if (this.edited || this.confirmed || this.editing) {
      return;
    }
    if (this.model.aiDraft !== this.lastDraft) {
      this.lastDraft = this.model.aiDraft;
      this.draft = this.model.aiDraft;
      this.opinionText = this.model.aiDraft;
    }
  }

  private resetForModel(): void {
    this.draft = this.model.aiDraft;
    this.opinionText = this.model.aiDraft;
    this.lastMediaId = this.model.mediaId;
    this.lastDraft = this.model.aiDraft;
    this.editing = false;
    this.confirmed = false;
    this.confirmedAt = '';
    this.signedBy = '';
    this.edited = false;
  }

  // ══════════════════ 派生值 ══════════════════

  /** 生成中（用来决定空态里画不画进度条） */
  @Computed
  get running(): boolean {
    return this.model.status === TaskStatus.running;
  }

  /** 状态胶囊文案 */
  @Computed
  get statusText(): string {
    if (this.confirmed) {
      return '已确认';
    }
    if (!this.model.ready) {
      return this.running ? '生成中' : '待分析';
    }
    return this.edited ? '已修改 · 待确认' : '待确认';
  }

  /** 状态胶囊文字色 · 已确认=主色 / 待确认=辅助蓝 / 其余=次要灰 */
  @Computed
  get statusColor(): string {
    if (this.confirmed) {
      return UiTheme.primary;
    }
    if (!this.model.ready) {
      return UiTheme.textSecondary;
    }
    return UiTheme.accent;
  }

  /** 状态圆点色 */
  @Computed
  get statusDotColor(): string {
    if (this.confirmed) {
      return UiTheme.primary;
    }
    if (!this.model.ready) {
      return UiTheme.textSecondary;
    }
    return UiTheme.accent;
  }

  /** 状态胶囊底色 · 只用既有浅填充，不新增色板 */
  @Computed
  get statusBg(): string {
    return this.confirmed ? UiTheme.kpiGradientStart : UiTheme.fillSoft;
  }

  /** 非编辑态展示的正文（空串时给占位说明） */
  @Computed
  get bodyText(): string {
    if (this.opinionText.length > 0) {
      return this.opinionText;
    }
    if (!this.model.ready) {
      return this.model.emptyHint;
    }
    return '尚未填写医师意见，可点「编辑」补充。';
  }

  /** 正文颜色：没有内容时降为次要色，避免空段落看起来像正文 */
  @Computed
  get bodyColor(): string {
    return this.opinionText.length > 0 ? UiTheme.textPrimary : UiTheme.textSecondary;
  }

  /** 「确认意见」是否可用 · 编辑中必须先保存 */
  @Computed
  get canConfirm(): boolean {
    return this.model.ready && !this.editing && this.opinionText.trim().length > 0;
  }

  /** 编辑态「保存意见」是否可用 */
  @Computed
  get canSave(): boolean {
    return this.draft.trim().length > 0;
  }

  /** 进度文案 */
  @Computed
  get progressText(): string {
    return percentOf(this.model.progress);
  }

  // ══════════════════ 动作 ══════════════════

  /** 进入 / 退出编辑；退出不保存，恢复已保存正文 */
  private toggleEdit(): void {
    if (this.editing) {
      this.draft = this.opinionText;
      this.editing = false;
      return;
    }
    this.draft = this.opinionText.length > 0 ? this.opinionText : this.model.aiDraft;
    this.editing = true;
  }

  /** 保存草稿（不确认） */
  private saveDraft(): void {
    const value: string = this.draft.trim();
    if (value.length === 0) {
      return;
    }
    this.opinionText = value;
    this.draft = value;
    this.edited = value !== this.model.aiDraft;
    this.editing = false;
  }

  /** 用模型初稿覆盖当前意见（已确认则退回待确认） */
  private regenerate(): void {
    this.draft = this.model.aiDraft;
    this.opinionText = this.model.aiDraft;
    this.edited = false;
    this.confirmed = false;
    this.confirmedAt = '';
    this.signedBy = '';
    this.editing = false;
  }

  /** 确认意见 · 留痕（医师 + 时间） */
  private confirmOpinion(): void {
    const value: string = this.opinionText.trim();
    if (!this.model.ready || value.length === 0) {
      return;
    }
    this.opinionText = value;
    this.draft = value;
    this.edited = value !== this.model.aiDraft;
    this.confirmed = true;
    this.signedBy = this.model.doctorName;
    this.confirmedAt = formatNow();
  }

  /** 修改已确认的意见 · 退回编辑态，确认章随新保存重新生成 */
  private revise(): void {
    this.confirmed = false;
    this.confirmedAt = '';
    this.signedBy = '';
    this.draft = this.opinionText;
    this.editing = true;
  }

  // ══════════════════ 片段（★ 无参 builder）══════════════════

  /** 标题 + 状态胶囊 */
  @Builder
  headerRow() {
    Row({ space: UiTheme.gapS }) {
      Column({ space: UiTheme.gapXs }) {
        Text('诊断意见')
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('模型辅助生成 · 需医师复核后生效')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: UiTheme.gapXs }) {
        StatusDot({ dotColor: this.statusDotColor, dotSize: 6 })
        Text(this.statusText)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(this.statusColor)
          .maxLines(1)
      }
      .height(CAPSULE_HEIGHT)
      .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
      .borderRadius(CAPSULE_RADIUS)
      .backgroundColor(this.statusBg)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 未就绪：生成中给进度，失败/无分给原因 */
  @Builder
  emptyBody() {
    Column({ space: UiTheme.gapM }) {
      Text(this.model.emptyHint)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .lineHeight(BODY_LINE_HEIGHT)

      if (this.running) {
        Column({ space: UiTheme.gapS }) {
          Row() {
            Text('正在生成初稿')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
              .layoutWeight(1)
              .textAlign(TextAlign.Start)

            Text(this.progressText)
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
          }
          .width('100%')

          ProgressBar({
            ratio: this.model.progress,
            barColor: UiTheme.primary,
            barHeight: 4
          })
        }
        .width('100%')
        .padding(UiTheme.gapM)
        .backgroundColor(UiTheme.kpiHeroTint)
        .borderRadius(UiTheme.buttonRadius)
        .border({ width: 1, color: UiTheme.kpiHeroBorder })
      }
    }
    .width('100%')
    .padding(UiTheme.gapM)
    .backgroundColor(UiTheme.fillSoft)
    .borderRadius(UiTheme.buttonRadius)
    .alignItems(HorizontalAlign.Start)
  }

  /** 结论块：左侧档位条 + 分数 + 初判 */
  @Builder
  conclusionBlock() {
    Column({ space: UiTheme.gapS }) {
      Row({ space: UiTheme.gapXs }) {
        Text('综合判断')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)

        Text('AI 初判')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.accent)
          .height(20)
          .padding({ left: UiTheme.gapXs, right: UiTheme.gapXs })
          .borderRadius(UiTheme.gapXs)
          .backgroundColor(UiTheme.fillSoft)

        Blank()

        Text(this.model.timeText)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: UiTheme.gapS }) {
        Text(this.model.scoreText)
          .fontSize(UiTheme.fontSizeCardMetric)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.model.severityColor)

        Text(`分 · ${this.model.severityLabel}`)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(this.model.severityColor)
          .margin({ bottom: UiTheme.gapXs })
          .maxLines(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Text(this.model.conclusion)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .lineHeight(BODY_LINE_HEIGHT)
    }
    .width('100%')
    .padding(UiTheme.gapM)
    // 竖条用 border-left 画：高度天然等于内容，不新增"height('100%')"的测量风险
    .border({ width: { left: RAIL_WIDTH }, color: this.model.severityColor })
    .borderRadius(UiTheme.buttonRadius)
    .backgroundColor(UiTheme.kpiHeroTint)
    .alignItems(HorizontalAlign.Start)
  }

  /** 判断依据列表 */
  @Builder
  evidenceList() {
    Column({ space: UiTheme.gapS }) {
      Text('判断依据')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)

      ForEach(this.model.evidence, (item: DiagnosisEvidenceModel, index: number) => {
        Row({ space: UiTheme.gapM }) {
          Text(item.label)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width(64)
            .textAlign(TextAlign.Start)

          Text(item.value)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
            .lineHeight(BODY_LINE_HEIGHT)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (index < this.model.evidence.length - 1) {
          Divider()
            .color(UiTheme.divider)
            .strokeWidth(0.5)
        }
      }, (item: DiagnosisEvidenceModel) => item.label)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 意见编辑区标题行 */
  @Builder
  opinionHeader() {
    Row({ space: UiTheme.gapS }) {
      Text('医师意见')
        .fontSize(UiTheme.fontSizeSection)
        .fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      if (this.confirmed) {
        Button('修改意见')
          .type(ButtonType.Normal)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.accent)
          .backgroundColor(Color.Transparent)
          .height(44)
          .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
          .onClick(() => {
            this.revise();
          })
      } else {
        Button('重新生成')
          .type(ButtonType.Normal)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .backgroundColor(Color.Transparent)
          .height(44)
          .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
          .enabled(this.model.ready)
          .onClick(() => {
            this.regenerate();
          })

        Button(this.editing ? '收起' : '编辑')
          .type(ButtonType.Normal)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.accent)
          .backgroundColor(Color.Transparent)
          .height(44)
          .padding({ left: UiTheme.gapS, right: UiTheme.gapS })
          .enabled(this.model.ready)
          .onClick(() => {
            this.toggleEdit();
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 编辑态 · TextArea + 字数 + 保存/取消 */
  @Builder
  editor() {
    Column({ space: UiTheme.gapS }) {
      TextArea({ text: this.draft, placeholder: '填写诊断意见（会作为本次评估的医师结论）' })
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textPrimary)
        .placeholderColor(UiTheme.textSecondary)
        .width('100%')
        .height(EDITOR_HEIGHT)
        .maxLength(MAX_OPINION_LEN)
        .padding(UiTheme.gapM)
        .backgroundColor(UiTheme.fillSoft)
        .borderRadius(UiTheme.buttonRadius)
        .onChange((value: string) => {
          this.draft = value;
        })

      Row() {
        Text('仅本次会话有效，未写入报告')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        Text(`${this.draft.length}/${MAX_OPINION_LEN}`)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
      }
      .width('100%')

      Row({ space: UiTheme.gapS }) {
        Button('取消')
          .type(ButtonType.Normal)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .backgroundColor(Color.Transparent)
          .borderWidth(1)
          .borderColor(UiTheme.divider)
          .borderRadius(UiTheme.buttonRadius)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.toggleEdit();
          })

        Button('保存意见')
          .type(ButtonType.Normal)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor('#FFFFFF')
          .backgroundColor(UiTheme.primary)
          .borderRadius(UiTheme.buttonRadius)
          .layoutWeight(1)
          .height(44)
          .enabled(this.canSave)
          .opacity(this.canSave ? 1 : 0.5)
          .onClick(() => {
            this.saveDraft();
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 非编辑态 · 正文 + 确认印章 */
  @Builder
  opinionBody() {
    Column({ space: UiTheme.gapM }) {
      Text(this.bodyText)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(this.bodyColor)
        .width('100%')
        .textAlign(TextAlign.Start)
        .lineHeight(BODY_LINE_HEIGHT)

      if (this.confirmed) {
        Row({ space: UiTheme.gapS }) {
          StatusDot({ dotColor: UiTheme.primary, dotSize: 6 })

          Text(`已确认 · ${this.signedBy} · ${this.confirmedAt}`)
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.primary)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(UiTheme.gapM)
        .backgroundColor(UiTheme.kpiHeroTint)
        .borderRadius(UiTheme.buttonRadius)
        .border({ width: 1, color: UiTheme.kpiHeroBorder })
        .alignItems(VerticalAlign.Center)
      } else {
        Button('确认意见')
          .type(ButtonType.Normal)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor('#FFFFFF')
          .backgroundColor(UiTheme.primary)
          .borderRadius(UiTheme.buttonRadius)
          .width('100%')
          .height(48)
          .enabled(this.canConfirm)
          .opacity(this.canConfirm ? 1 : 0.5)
          .onClick(() => {
            this.confirmOpinion();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 页脚免责声明 · 每张卡都带，不依赖页面别处 */
  @Builder
  disclaimer() {
    Column({ space: UiTheme.gapS }) {
      Divider()
        .color(UiTheme.divider)
        .strokeWidth(0.5)

      Text('本意见由模型辅助生成，仅作临床参考，不能替代精神科医师面诊、量表复核与影像学检查。')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: UiTheme.gapM }) {
      this.headerRow()

      if (!this.model.ready) {
        this.emptyBody()
        this.disclaimer()
      } else {
        this.conclusionBlock()
        this.evidenceList()
        this.opinionHeader()

        if (this.editing) {
          this.editor()
        } else {
          this.opinionBody()
        }

        this.disclaimer()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
