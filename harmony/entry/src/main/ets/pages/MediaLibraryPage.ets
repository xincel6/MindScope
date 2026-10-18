/**
 * MediaLibraryPage · 素材库（一级页签）
 *
 * 页面契约：`@Param pageParam: MediaLibraryPageParam`
 *   - 数据（`videos` / `images` / `patients` / `selectedPatient` / `selectedMediaId` / `analyzing`）
 *     由窗口层注入；
 *   - 动作（`onUpload` / `onOpenMedia` / `onDelete` / `onRetry` / `onSelectPatient` / `onRename`）
 *     通过回调交回窗口层；
 *   - `busy` / `errorMsg` 驱动骨架屏与「加载失败 + 重试」。
 *
 * ★ 页面纪律：不 import 任何 store、不发请求、不碰路由栈。
 */

import { UiTheme } from '../common/UiTheme';
import { MediaLibraryPageParam } from '../types/PageParams';
import { MediaItemModel, MediaType } from '../types/Index';
import { PageHeader } from '../components/PageHeader';
import { RevealCard } from '../components/RevealCard';
import { SkeletonBlock } from '../components/SkeletonView';
import { ErrorRetryView } from '../components/ErrorRetryView';

/** 当前激活的素材类型 Tab（本页内部状态，与业务筛选无关） */
enum MediaTab {
  video = 0,
  image = 1
}

@ComponentV2
export struct MediaLibraryPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: MediaLibraryPageParam = new MediaLibraryPageParam();

  /** 当前激活的 Tab */
  @Local activeTab: MediaTab = MediaTab.video;

  /** 缩略图加载失败的素材 id 集合（用于回退到占位图标） */
  @Local brokenThumbs: string[] = [];

  build() {
    Column({ space: UiTheme.gapL }) {
      // 0 号位 · 页头 + 上传按钮（转场由 RevealCard 内部负责）
      RevealCard({ order: 0 }) {
        Column({ space: UiTheme.gapS }) {
          PageHeader({ title: '素材库', subtitle: '评估用的图片与视频素材' })
          this.uploadBar()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // 1 号位 · 患者筛选 + 类型 Tab
      RevealCard({ order: 1 }) {
        Column({ space: UiTheme.gapS }) {
          this.patientFilterBar()
          this.tabBar()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // 内容区三态（Grid 自己滚动，不参与转场）：加载 / 错误 / 列表
      Column() {
        if (this.pageParam.busy) {
          this.loadingView()
        } else if (this.pageParam.errorMsg.length > 0) {
          ErrorRetryView({
            message: this.pageParam.errorMsg,
            onRetry: (): void => {
              this.pageParam.onRetry();
            }
          })
        } else {
          this.contentView()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ left: UiTheme.pagePadding, right: UiTheme.pagePadding, top: UiTheme.gapL })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }

  // ────────────────── 顶部：标题右侧上传按钮 ──────────────────

  @Builder
  uploadBar() {
    Row() {
      Blank()
      Button('＋ 上传')
        .type(ButtonType.Normal)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.primary)
        .backgroundColor('rgba(13, 148, 136, 0.08)')
        .borderWidth(1)
        .borderColor('rgba(13, 148, 136, 0.32)')
        .borderRadius(UiTheme.buttonRadius)
        .height(32)
        .padding({ left: UiTheme.gapM, right: UiTheme.gapM })
        .onClick(() => {
          this.pageParam.onUpload();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ────────────────── 患者筛选器 ──────────────────

  @Builder
  patientFilterBar() {
    Row({ space: UiTheme.gapS }) {
      Text('患者')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)

      Select(this.patientSelectOptions())
        .selected(this.selectedPatientIndex())
        .value(this.selectedPatientLabel())
        .font({ size: UiTheme.fontSizeCaption })
        .fontColor(UiTheme.textPrimary)
        .selectedOptionFont({ size: UiTheme.fontSizeCaption })
        .selectedOptionFontColor(UiTheme.textPrimary)
        .optionFont({ size: UiTheme.fontSizeCaption })
        .optionFontColor(UiTheme.textPrimary)
        .backgroundColor(UiTheme.cardBackground)
        .borderRadius(UiTheme.buttonRadius)
        .height(32)
        .onSelect((index: number) => {
          const opts: string[] = this.patientLabels();
          if (index >= 0 && index < opts.length) {
            this.pageParam.onSelectPatient(opts[index]);
          }
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 患者标签数组：首项固定「全部患者」，其后接去重患者名 */
  private patientLabels(): string[] {
    const out: string[] = ['全部患者'];
    const patients: string[] = this.pageParam.patients;
    for (let i = 0; i < patients.length; i++) {
      out.push(patients[i]);
    }
    return out;
  }

  /** 患者下拉选项（Select 组件需要 SelectOption[]） */
  private patientSelectOptions(): SelectOption[] {
    const labels: string[] = this.patientLabels();
    const out: SelectOption[] = [];
    for (let i = 0; i < labels.length; i++) {
      const opt: SelectOption = { value: labels[i] };
      out.push(opt);
    }
    return out;
  }

  /** 当前选中患者在选项列表里的下标（0 = 全部患者） */
  private selectedPatientIndex(): number {
    const opts: string[] = this.patientLabels();
    const selected: string = this.pageParam.selectedPatient;
    for (let i = 0; i < opts.length; i++) {
      if (opts[i] === selected) {
        return i;
      }
    }
    return 0;
  }

  /** 当前选中患者的显示文案 */
  private selectedPatientLabel(): string {
    const opts: string[] = this.patientLabels();
    const idx: number = this.selectedPatientIndex();
    return opts[idx];
  }

  // ────────────────── Tab 切换 ──────────────────

  @Builder
  tabBar() {
    Row({ space: UiTheme.gapS }) {
      this.tabChip('视频素材', MediaTab.video)
      this.tabChip('图片素材', MediaTab.image)
    }
    .width('100%')
  }

  @Builder
  tabChip(label: string, tab: MediaTab) {
    Text(label)
      .fontSize(UiTheme.fontSizeBody)
      .fontWeight(this.activeTab === tab ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.activeTab === tab ? UiTheme.primary : UiTheme.textSecondary)
      .padding({
        left: UiTheme.gapM,
        right: UiTheme.gapM,
        top: UiTheme.gapXs,
        bottom: UiTheme.gapXs
      })
      .backgroundColor(this.activeTab === tab ? 'rgba(13, 148, 136, 0.10)' : Color.Transparent)
      .borderRadius(UiTheme.buttonRadius)
      .onClick(() => {
        this.activeTab = tab;
      })
  }

  // ────────────────── 内容区 ──────────────────

  @Builder
  contentView() {
    if (this.activeTab === MediaTab.video) {
      this.gridView(this.pageParam.videos, MediaType.video)
    } else {
      this.gridView(this.pageParam.images, MediaType.image)
    }
  }

  @Builder
  gridView(items: MediaItemModel[], type: MediaType) {
    if (items.length === 0) {
      Column({ space: UiTheme.gapS }) {
        Text(type === MediaType.video ? '暂无视频素材' : '暂无图片素材')
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
      }
      .width('100%')
      .height(200)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      Grid() {
        ForEach(items, (item: MediaItemModel) => {
          GridItem() {
            this.mediaItem(item)
          }
        }, (item: MediaItemModel) => item.id)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(UiTheme.gapS)
      .rowsGap(UiTheme.gapS)
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ bottom: UiTheme.gapXl })
    }
  }

  @Builder
  mediaItem(item: MediaItemModel) {
    Column() {
      Stack() {
        // 缩略图 / 占位
        this.thumbArea(item)

        // 右上角操作按钮组
        Row({ space: UiTheme.gapXs }) {
          // 命名/重命名按钮
          Text('名')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .width(26)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .backgroundColor('rgba(2, 132, 199, 0.75)')
            .onClick(() => {
              this.pageParam.onRename(item.id);
            })

          // 删除按钮
          Text('✕')
            .fontSize(12)
            .fontColor('#F87171')
            .width(26)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .backgroundColor('rgba(0, 0, 0, 0.55)')
            .onClick(() => {
              this.pageParam.onDelete(item.id);
            })
        }
        .padding(4)
      }
      .width('100%')
      .aspectRatio(16 / 10)
      .alignContent(Alignment.TopEnd)

      // 名称
      Text(item.name)
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: UiTheme.gapXs, right: UiTheme.gapXs, top: UiTheme.gapXs })

      // 患者名（未命名时弱化显示）
      Text(item.patient.length > 0 ? `患者：${item.patient}` : '未命名')
        .fontSize(11)
        .fontColor(item.patient.length > 0 ? UiTheme.accent : UiTheme.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: UiTheme.gapXs, right: UiTheme.gapXs })

      // 时长（仅视频）
      if (item.type === MediaType.video && item.duration !== null) {
        Text(`${item.duration}s`)
          .fontSize(11)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .padding({ left: UiTheme.gapXs, right: UiTheme.gapXs, bottom: UiTheme.gapXs })
      }
    }
    .width('100%')
    .borderRadius(UiTheme.cardRadius)
    .borderWidth(1)
    .borderColor(this.pageParam.selectedMediaId === item.id ? UiTheme.primary : UiTheme.divider)
    .backgroundColor('rgba(0, 0, 0, 0.06)')
    .onClick(() => {
      this.pageParam.onOpenMedia(item.id);
    })
  }

  @Builder
  thumbArea(item: MediaItemModel) {
    Column() {
      if (this.isBroken(item.id)) {
        // 加载失败 → 占位字形
        Text(item.type === MediaType.video ? '影' : '图')
          .fontSize(28)
          .fontColor(UiTheme.textSecondary)
      } else if (item.thumbnailUrl.length > 0 || item.url.length > 0) {
        Image(item.thumbnailUrl.length > 0 ? item.thumbnailUrl : item.url)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .onError(() => {
            this.markBroken(item.id);
          })
      } else {
        Text(item.type === MediaType.video ? '影' : '图')
          .fontSize(28)
          .fontColor(UiTheme.textSecondary)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#1A1A1A')
    .borderRadius({ topLeft: UiTheme.cardRadius, topRight: UiTheme.cardRadius })
    .clip(true)
  }

  // ────────────────── 加载骨架 ──────────────────

  @Builder
  loadingView() {
    Column({ space: UiTheme.gapM }) {
      SkeletonBlock({ blockHeight: 96, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 96, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 96, radius: UiTheme.cardRadius })
    }
    .width('100%')
  }

  // ────────────────── 缩略图失败回退 ──────────────────

  private isBroken(id: string): boolean {
    for (let i = 0; i < this.brokenThumbs.length; i++) {
      if (this.brokenThumbs[i] === id) {
        return true;
      }
    }
    return false;
  }

  private markBroken(id: string): void {
    if (this.isBroken(id)) {
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < this.brokenThumbs.length; i++) {
      next.push(this.brokenThumbs[i]);
    }
    next.push(id);
    this.brokenThumbs = next;
  }
}
