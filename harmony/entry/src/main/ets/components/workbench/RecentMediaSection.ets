/**
 * RecentMediaSection · 工作台「最近使用的素材」区块
 *
 * 一行一条素材，右侧跟一条**严重度进度条**：
 *   分数 = BDI（0–63），条长 = 分数 / 63（**越长越严重**，用户本轮确认的口径），
 *   颜色 = 四档严重度色（正常绿 / 轻度蓝 / 中度橙 / 重度红）。
 *
 * ★ 数据来源是 `AppStore.recentMedia()`（报告 + 媒体库拼出来的），
 *   组件本身不做任何合并/去重，只负责画。
 *
 * ★ 缩略图降级：视频素材后端**不生成缩略图**（`thumbnail_url` 为空），
 *   此时 `thumbnailUrl` 为空串，画一个带字形的浅灰块而不是裂图。
 */

import { UiTheme } from '../../common/UiTheme';
import { MediaType, RecentMediaModel } from '../../types/Index';
import { RippleCard } from '../RippleCard';
import { ProgressBar } from '../common/ProgressBar';

@ComponentV2
export struct RecentMediaSection {
  /** 最近使用的素材（已按时间倒序、按素材去重） */
  @Param items: RecentMediaModel[] = [];

  /** 是否正在加载（首次进入且还没有缓存） */
  @Param loading: boolean = false;

  /** 错误文案 · 非空即展示 */
  @Param errorMsg: string = '';

  /** 点「查看全部」· 窗口层切到历史报告页签 */
  @Param onViewAll: () => void = () => {};

  /** 点某一条素材 · 窗口层打开该素材的分析详情页 */
  @Param onSelect: (mediaId: string) => void = (mediaId: string) => {};

  // ══════════════════ 派生文案 ══════════════════

  /** 空态文案 · 区分"加载中""出错""真的没有" */
  @Computed
  get emptyHint(): string {
    if (this.loading) {
      return '加载中…';
    }
    if (this.errorMsg.length > 0) {
      return this.errorMsg;
    }
    return '还没有使用过的素材，先在上方选择一段图片或视频';
  }

  /** 分数文案 · 保留一位小数 */
  private scoreTextOf(item: RecentMediaModel): string {
    return item.bdiScore.toFixed(1);
  }

  /** 缩略图退化时的字形 */
  private glyphOf(item: RecentMediaModel): string {
    return item.type === MediaType.video ? '视' : '图';
  }

  // ══════════════════ 片段 ══════════════════

  /** 区块标题行：标题 + 查看全部 */
  @Builder
  sectionHeader() {
    Row() {
      Text('最近使用的素材')
        .fontSize(UiTheme.fontSizeSection)
        .fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      // 「查看全部」用文字按钮，与刷新按钮同样的"贴合背景"处理
      Text('查看全部')
        .fontSize(UiTheme.fontSizeBody)
        .fontColor(UiTheme.accent)
        .padding({ left: UiTheme.gapS, right: UiTheme.gapXs, top: UiTheme.gapXs, bottom: UiTheme.gapXs })
        .onClick(() => {
          this.onViewAll();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 缩略图（无图时降级为字形块） */
  @Builder
  thumbnail(item: RecentMediaModel) {
    if (item.thumbnailUrl.length > 0) {
      Image(item.thumbnailUrl)
        .width(UiTheme.thumbSize)
        .height(UiTheme.thumbSize)
        .objectFit(ImageFit.Cover)
        .borderRadius(UiTheme.cardRadius)
        .backgroundColor(UiTheme.fillSoft)
    } else {
      Column() {
        Text(this.glyphOf(item))
          .fontSize(20)
          .fontColor(UiTheme.textSecondary)
      }
      .width(UiTheme.thumbSize)
      .height(UiTheme.thumbSize)
      .borderRadius(UiTheme.cardRadius)
      .backgroundColor(UiTheme.fillSoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /**
   * 一行素材（**独立可点卡片**）
   *
   * ★ 关键：这里必须是"每条一张卡"，而不是"整块一张卡"。
   *   本轮修掉的 bug 就是整块被包成一张可点卡片，导致点任意一行都会先触发整块的动作
   *   （表现为"点单条素材却跳去了历史报告页"）。
   */
  @Builder
  mediaRow(item: RecentMediaModel) {
    RippleCard({
      _padding: UiTheme.gapM,
      onTap: () => {
        this.onSelect(item.mediaId);
      }
    }) {
      Row({ space: UiTheme.gapM }) {
        this.thumbnail(item)

        Column({ space: UiTheme.gapS }) {
          // 文件名
          Text(item.name)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textPrimary)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)

          // 分数 + 档位标签
          Row({ space: UiTheme.gapS }) {
            Text(this.scoreTextOf(item))
              .fontSize(UiTheme.fontSizeSection)
              .fontWeight(FontWeight.Bold)
              .fontColor(item.severityColor)

            Text(item.severityLabel)
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(item.severityColor)

            Text('BDI')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // 严重度进度条：越长越严重
          ProgressBar({
            ratio: item.scoreRatio,
            barColor: item.severityColor,
            barHeight: 6
          })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Column({ space: UiTheme.gapM }) {
      this.sectionHeader()

      if (this.items.length > 0) {
        // ★ 每一行都是**独立**的 RippleCard：按压反馈只作用在被点的那一行，
        //   且该行的点击只会触发自己的 `onTap`（不会再冒泡出一个"整块"的动作）。
        ForEach(this.items, (item: RecentMediaModel) => {
          this.mediaRow(item)
        }, (item: RecentMediaModel) => item.mediaId)
      } else {
        // 空态本身不可点（没有可跳转的目标），但仍画出卡片以保持"全是卡片"的统一风格
        RippleCard({ _enabled: false, _clickable: false }) {
          Text(this.emptyHint)
            .fontSize(UiTheme.fontSizeBody)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
