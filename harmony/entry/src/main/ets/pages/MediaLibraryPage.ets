/**
 * MediaLibraryPage · 素材库
 *
 * 素材按名称聚合为纵向卡片；每张卡上方展示上传时填写的患者信息，
 * 下方把同名素材放进一条可横向滑动的素材带。页面顶部支持实时搜索，
 * 排序按钮可在“按时间 / 按姓名”之间切换。
 */

import { UiTheme } from '../common/UiTheme';
import { MediaLibraryPageParam } from '../types/PageParams';
import { MediaItemModel, MediaType } from '../types/Index';
import { ErrorRetryView } from '../components/ErrorRetryView';
import { RippleCard } from '../components/RippleCard';
import { SkeletonBlock } from '../components/SkeletonView';

enum MediaSortMode {
  time = 0,
  name = 1
}

interface MediaNameGroupModel {
  key: string;
  /** 组标题：有患者名用患者名，没有才用素材名 */
  name: string;
  /** 组内最新一条的原始文件名，作副标题用 */
  fileName: string;
  items: MediaItemModel[];
}

const MEDIA_TILE_WIDTH: number = 176;
const MEDIA_TILE_IMAGE_HEIGHT: number = 108;

@ComponentV2
export struct MediaLibraryPage {
  @Param pageParam: MediaLibraryPageParam = new MediaLibraryPageParam();

  @Local searchText: string = '';
  @Local sortMode: MediaSortMode = MediaSortMode.time;
  @Local brokenThumbs: string[] = [];

  @Computed
  get visibleGroups(): MediaNameGroupModel[] {
    const groups: MediaNameGroupModel[] = this.buildGroups();
    const query: string = this.searchText.trim().toLowerCase();
    if (query.length === 0) {
      groups.sort((a: MediaNameGroupModel, b: MediaNameGroupModel): number => {
        return this.compareGroups(a, b, query);
      });
      return groups;
    }

    const matched: MediaNameGroupModel[] = [];
    for (let i = 0; i < groups.length; i++) {
      if (this.groupSearchScore(groups[i], query) >= 0) {
        matched.push(groups[i]);
      }
    }
    matched.sort((a: MediaNameGroupModel, b: MediaNameGroupModel): number => {
      return this.compareGroups(a, b, query);
    });
    return matched;
  }

  @Computed
  get countText(): string {
    let fileCount: number = 0;
    const groups: MediaNameGroupModel[] = this.visibleGroups;
    for (let i = 0; i < groups.length; i++) {
      fileCount += groups[i].items.length;
    }
    return `共 ${groups.length} 组素材 · ${fileCount} 个文件`;
  }

  build() {
    Scroll() {
      Column({ space: UiTheme.gapM }) {
        this.headerBar()
        this.searchBox()
        this.sortBar()

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
          Row({ space: UiTheme.gapS }) {
            Text('素材分组')
              .fontSize(UiTheme.fontSizeBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.textPrimary)

            Text(this.countText)
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.visibleGroups.length === 0) {
            this.emptyView()
          } else {
            ForEach(this.visibleGroups, (group: MediaNameGroupModel) => {
              this.groupCard(group)
            }, (group: MediaNameGroupModel) => group.key)
          }
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
    .scrollBar(BarState.Off)
    .backgroundColor(UiTheme.pageBackground)
  }

  @Builder
  headerBar() {
    Row({ space: UiTheme.gapS }) {
      Column({ space: UiTheme.gapXs }) {
        Text('素材库')
          .fontSize(UiTheme.fontSizeTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('＋ 上传')
        .type(ButtonType.Normal)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.primary)
        .backgroundColor('rgba(13, 148, 136, 0.08)')
        .borderWidth(1)
        .borderColor('rgba(13, 148, 136, 0.32)')
        .borderRadius(UiTheme.buttonRadius)
        .height(34)
        .padding({ left: UiTheme.gapM, right: UiTheme.gapM })
        .onClick(() => {
          this.pageParam.onUpload();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  searchBox() {
    Row({ space: UiTheme.gapS }) {
      Text('⌕')
        .fontSize(20)
        .fontColor(UiTheme.textSecondary)
        .width(22)
        .textAlign(TextAlign.Center)

      TextInput({ placeholder: '搜索素材名称或患者姓名', text: this.searchText })
        .layoutWeight(1)
        .height(40)
        .padding(0)
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.textPrimary)
        .placeholderColor(UiTheme.textSecondary)
        .backgroundColor(Color.Transparent)
        .border({ width: 0 })
        .maxLength(64)
        .onChange((value: string) => {
          this.searchText = value;
        })

      if (this.searchText.length > 0) {
        Text('×')
          .fontSize(22)
          .fontColor(UiTheme.textSecondary)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.searchText = '';
          })
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: UiTheme.gapM, right: UiTheme.gapS })
    .backgroundColor(UiTheme.cardBackground)
    .borderRadius(UiTheme.buttonRadius)
    .border({ width: 1, color: UiTheme.divider })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sortBar() {
    Row({ space: UiTheme.gapS }) {
      Text('排序')
        .fontSize(UiTheme.fontSizeCaption)
        .fontColor(UiTheme.textSecondary)

      Select(this.sortOptions())
        .selected(this.sortMode as number)
        .value(this.sortMode === MediaSortMode.time ? '按时间' : '按姓名')
        .font({ size: UiTheme.fontSizeBody })
        .fontColor(UiTheme.textPrimary)
        .selectedOptionFont({ size: UiTheme.fontSizeBody })
        .selectedOptionFontColor(UiTheme.textPrimary)
        .optionFont({ size: UiTheme.fontSizeBody })
        .optionFontColor(UiTheme.textPrimary)
        .backgroundColor(UiTheme.cardBackground)
        .borderWidth(1)
        .borderColor(UiTheme.divider)
        .borderRadius(UiTheme.buttonRadius)
        .height(34)
        .onSelect((index: number) => {
          this.sortMode = index === MediaSortMode.name as number
            ? MediaSortMode.name
            : MediaSortMode.time;
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private sortOptions(): SelectOption[] {
    const time: SelectOption = { value: '按时间' };
    const name: SelectOption = { value: '按姓名' };
    return [time, name];
  }

  @Builder
  groupCard(group: MediaNameGroupModel) {
    RippleCard({
      _enabled: false,
      _clickable: false,
      _padding: UiTheme.cardPadding
    }) {
      Column({ space: UiTheme.gapM }) {
        Row({ space: UiTheme.gapM }) {
          Column({ space: 4 }) {
            if (this.singlePatientOf(group).length === 0) {
              Text(`患者：${this.patientSummaryOf(group)}`)
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(UiTheme.accent)
                .padding({ left: UiTheme.gapS, right: UiTheme.gapS, top: 3, bottom: 3 })
                .backgroundColor('rgba(2, 132, 199, 0.08)')
                .borderRadius(10)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }

            Text(this.groupTitleOf(group))
              .fontSize(UiTheme.fontSizeSection)
              .fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.groupSubtitleOf(group).length > 0) {
              Text(this.groupSubtitleOf(group))
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(UiTheme.textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 1 }) {
            Text(`${group.items.length}`)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(UiTheme.primary)

            Text('个素材')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.groupSummaryOf(group))
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Scroll() {
          Row({ space: UiTheme.gapM }) {
            ForEach(group.items, (item: MediaItemModel) => {
              this.materialTile(item)
            }, (item: MediaItemModel) => item.id)
          }
        }
        .width('100%')
        .height(174)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  materialTile(item: MediaItemModel) {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Text(item.type === MediaType.video ? '视频' : '图片')
            .fontSize(UiTheme.fontSizeSection)
            .fontColor(UiTheme.textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#1A1A1A')

        if (!this.isBroken(item.id) && this.imageSourceOf(item).length > 0) {
          Image(this.imageSourceOf(item))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .onError(() => {
              this.markBroken(item.id);
            })
        }

        Row({ space: UiTheme.gapXs }) {
          Text('改')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .width(28)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(7)
            .backgroundColor('rgba(2, 132, 199, 0.82)')
            .onClick(() => {
              this.pageParam.onRename(item.id);
            })

          Text('删')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .width(28)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(7)
            .backgroundColor('rgba(0, 0, 0, 0.58)')
            .onClick(() => {
              this.pageParam.onDelete(item.id);
            })
        }
        .width('100%')
        .padding(UiTheme.gapXs)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(MEDIA_TILE_IMAGE_HEIGHT)
      .clip(true)

      Column({ space: 4 }) {
        Row({ space: UiTheme.gapXs }) {
          Text(item.type === MediaType.video ? '视频' : '图片')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.primary)

          Text(item.createdAt.length > 0 ? item.createdAt : '日期未知')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .layoutWeight(1)
            .maxLines(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')

        Text(item.type === MediaType.video && item.duration !== null
          ? `时长 ${item.duration}s`
          : '图片素材')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
      }
      .width('100%')
      .padding(UiTheme.gapS)
      .alignItems(HorizontalAlign.Start)
    }
    .width(MEDIA_TILE_WIDTH)
    .borderRadius(12)
    .borderWidth(this.pageParam.selectedMediaId === item.id ? 2 : 1)
    .borderColor(this.pageParam.selectedMediaId === item.id ? UiTheme.primary : UiTheme.divider)
    .backgroundColor(UiTheme.cardBackground)
    .clip(true)
    .onClick(() => {
      this.pageParam.onOpenMedia(item.id);
    })
  }

  @Builder
  loadingView() {
    Column({ space: UiTheme.gapM }) {
      SkeletonBlock({ blockHeight: 210, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 210, radius: UiTheme.cardRadius })
      SkeletonBlock({ blockHeight: 210, radius: UiTheme.cardRadius })
    }
    .width('100%')
  }

  @Builder
  emptyView() {
    RippleCard({ _enabled: false, _clickable: false }) {
      Column({ space: UiTheme.gapS }) {
        Text(this.searchText.trim().length > 0 ? '没有找到匹配的素材' : '素材库还是空的')
          .fontSize(UiTheme.fontSizeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')

        Text(this.searchText.trim().length > 0
          ? '可以按素材名称或患者姓名重新搜索。'
          : '上传一张图片或一段视频后，会按名称自动归组显示。')
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private sourceMedia(): MediaItemModel[] {
    const out: MediaItemModel[] = [];
    const all: MediaItemModel[] = this.pageParam.mediaItems;
    if (all.length > 0) {
      for (let i = 0; i < all.length; i++) {
        out.push(all[i]);
      }
      return out;
    }

    // 兼容页面参数刚挂载、完整列表尚未同步的一帧。
    for (let i = 0; i < this.pageParam.videos.length; i++) {
      out.push(this.pageParam.videos[i]);
    }
    for (let i = 0; i < this.pageParam.images.length; i++) {
      out.push(this.pageParam.images[i]);
    }
    return out;
  }

  /**
   * 按"同一个人"分组：**患者名优先**，没有患者名才退回素材名。
   *
   * ★ BUG-32：以前只按素材名分组，上传时文件被规范成 `test1_20261022_002822.jpg`
   *   和 `test1_20261022_003140.jpg`，同一个患者被拆成两组。患者名是人填的，
   *   语义上才是"人"，所以同名的素材必须归到一组。
   */
  private buildGroups(): MediaNameGroupModel[] {
    const source: MediaItemModel[] = this.sourceMedia();
    const groups: MediaNameGroupModel[] = [];
    const indexByKey: Record<string, number> = {};

    for (let i = 0; i < source.length; i++) {
      const item: MediaItemModel = source[i];
      const fileName: string = item.name.trim().length > 0 ? item.name.trim() : '未命名素材';
      const patient: string = item.patient.trim();
      const title: string = patient.length > 0 ? patient : fileName;
      const key: string = patient.length > 0 ? `p:${patient.toLowerCase()}` : `n:${fileName.toLowerCase()}`;
      const hit: number | undefined = indexByKey[key];
      if (hit !== undefined) {
        groups[hit].items.push(item);
        continue;
      }

      indexByKey[key] = groups.length;
      const group: MediaNameGroupModel = {
        key: key,
        name: title,
        fileName: fileName,
        items: [item]
      };
      groups.push(group);
    }

    for (let i = 0; i < groups.length; i++) {
      groups[i].items.sort((a: MediaItemModel, b: MediaItemModel): number => {
        if (a.createdAt !== b.createdAt) {
          return a.createdAt < b.createdAt ? 1 : -1;
        }
        return Number(b.id) - Number(a.id);
      });
    }
    return groups;
  }

  private compareGroups(a: MediaNameGroupModel, b: MediaNameGroupModel, query: string): number {
    if (query.length > 0) {
      const aScore: number = this.groupSearchScore(a, query);
      const bScore: number = this.groupSearchScore(b, query);
      if (aScore !== bScore) {
        return bScore - aScore;
      }
    }

    if (this.sortMode === MediaSortMode.name) {
      const aName: string = a.name.toLowerCase();
      const bName: string = b.name.toLowerCase();
      if (aName !== bName) {
        return aName < bName ? -1 : 1;
      }
    }

    const aDate: string = a.items.length > 0 ? a.items[0].createdAt : '';
    const bDate: string = b.items.length > 0 ? b.items[0].createdAt : '';
    if (aDate !== bDate) {
      return aDate < bDate ? 1 : -1;
    }
    const aId: number = a.items.length > 0 ? Number(a.items[0].id) : 0;
    const bId: number = b.items.length > 0 ? Number(b.items[0].id) : 0;
    return bId - aId;
  }

  private groupSearchScore(group: MediaNameGroupModel, query: string): number {
    const nameScore: number = this.textSearchScore(group.name, query, 0);
    const fileScore: number = this.textSearchScore(group.fileName, query, 60);
    const patientScore: number = this.textSearchScore(this.patientSummaryOf(group), query, 120);
    return Math.max(Math.max(nameScore, fileScore), patientScore);
  }

  private textSearchScore(raw: string, query: string, penalty: number): number {
    const text: string = raw.trim().toLowerCase();
    if (text.length === 0) {
      return -1;
    }
    if (text === query) {
      return 1000 - penalty;
    }
    if (text.startsWith(query)) {
      return 900 - penalty - Math.min(text.length - query.length, 80);
    }
    const index: number = text.indexOf(query);
    if (index < 0) {
      return -1;
    }
    return 600 - penalty - Math.min(index, 100);
  }

  private patientSummaryOf(group: MediaNameGroupModel): string {
    const patients: string[] = [];
    for (let i = 0; i < group.items.length; i++) {
      const patient: string = group.items[i].patient.trim();
      const label: string = patient.length > 0 ? patient : '未命名患者';
      if (patients.indexOf(label) < 0) {
        patients.push(label);
      }
    }
    return patients.length > 0 ? patients.join('、') : '未命名患者';
  }

  /**
   * 分组里**唯一的**患者名（没有患者名、或混着多个患者名 → 空串）
   *
   * ★ 分组键是素材名，所以一组里通常只有一个患者；只有这种情况下才敢把
   *   患者名当卡片标题，否则会张冠李戴（BUG-29）。
   */
  private singlePatientOf(group: MediaNameGroupModel): string {
    let found: string = '';
    for (let i = 0; i < group.items.length; i++) {
      const patient: string = group.items[i].patient.trim();
      if (patient.length === 0) {
        return '';
      }
      if (found.length === 0) {
        found = patient;
      } else if (found !== patient) {
        return '';
      }
    }
    return found;
  }

  /** 素材库卡片标题：认得出患者就用患者名，否则回退素材名（BUG-29） */
  private groupTitleOf(group: MediaNameGroupModel): string {
    const patient: string = this.singlePatientOf(group);
    if (patient.length > 0) {
      return patient;
    }
    return group.name.trim().length > 0 ? group.name : '未命名素材';
  }

  /** 卡片副标题：原始文件名；同名多条素材时补一句"共 N 个文件" */
  private groupSubtitleOf(group: MediaNameGroupModel): string {
    const fileName: string = group.fileName.trim();
    const title: string = this.groupTitleOf(group).trim();
    const count: number = group.items.length;
    let text: string = fileName;
    if (count > 1) {
      text = `${fileName} 等 ${count} 个文件`;
    }
    if (text.toLowerCase() === title.toLowerCase()) {
      return '';
    }
    return text;
  }

  private groupSummaryOf(group: MediaNameGroupModel): string {
    let imageCount: number = 0;
    let videoCount: number = 0;
    for (let i = 0; i < group.items.length; i++) {
      if (group.items[i].type === MediaType.video) {
        videoCount++;
      } else {
        imageCount++;
      }
    }

    const parts: string[] = [];
    if (imageCount > 0) {
      parts.push(`图片 ${imageCount}`);
    }
    if (videoCount > 0) {
      parts.push(`视频 ${videoCount}`);
    }
    if (group.items.length > 0 && group.items[0].createdAt.length > 0) {
      parts.push(`最近 ${group.items[0].createdAt}`);
    }
    return parts.join(' · ');
  }

  private imageSourceOf(item: MediaItemModel): string {
    if (item.thumbnailUrl.length > 0) {
      return item.thumbnailUrl;
    }
    return item.type === MediaType.image ? item.url : '';
  }

  private isBroken(id: string): boolean {
    return this.brokenThumbs.indexOf(id) >= 0;
  }

  private markBroken(id: string): void {
    if (this.isBroken(id)) {
      return;
    }
    const next: string[] = this.brokenThumbs.slice();
    next.push(id);
    this.brokenThumbs = next;
  }
}
