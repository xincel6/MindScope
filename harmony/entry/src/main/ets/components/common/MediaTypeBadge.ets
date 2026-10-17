/**
 * MediaTypeBadge · 素材类型徽标（"图" / "视"）
 *
 * ────────────────── 为什么需要它 ──────────────────
 * 用户反馈「分析页面分不清图片和视频」。旧实现里类型只是状态行中的一行灰字
 * （"图片 · 素材 id 12 · 10 帧"），而图片被服务端推成 10 帧后，看起来更像一段视频。
 * 现在：
 *   · 类型做成**有颜色的徽标**（图片 = 主色 / 视频 = 辅助蓝），一眼能认；
 *   · 页面里所有"随类型变化"的文案（帧数、曲线、分布、逐帧列表）都与它同源，
 *     不会出现"徽标说图片、逐帧列表按视频渲染"的自相矛盾。
 *
 * ★ 配色只从 `UiTheme` 取（本工程纪律：设计色板只在 `common/UiTheme.ets`）：
 *   图片 → `primary`（#0D9488），视频 → `accent`（#0284C7）。
 *   这两种颜色是"功能色"，与严重度色阶（数据表达色）语义不同，不得混用。
 */

import { UiTheme } from '../../common/UiTheme';
import { MediaType, UiConstant } from '../../types/Index';

/** 字形块边长（vp）· 与 12fp 的辅助文字等高，视觉上像个"小标签" */
const GLYPH_SIZE: number = 18;

@ComponentV2
export struct MediaTypeBadge {
  /** 素材类型 */
  @Param mediaType: MediaType = MediaType.image;

  /** 是否显示"图片 / 视频"文字（false 时只有字形块，用于极窄场景） */
  @Param showLabel: boolean = true;

  @Computed
  get isVideo(): boolean {
    return this.mediaType === MediaType.video;
  }

  /** 字形：字形块里放的字（不依赖图标资源，避免缺图裂开） */
  @Computed
  get glyph(): string {
    return this.isVideo ? '视' : '图';
  }

  @Computed
  get label(): string {
    return UiConstant.mediaTypeLabelOf(this.mediaType);
  }

  /** 主色（类型色） */
  @Computed
  get tone(): string {
    return this.isVideo ? UiTheme.accent : UiTheme.primary;
  }

  build() {
    Row({ space: UiTheme.gapXs }) {
      // 字形块：实心色底 + 白字，比"图标 + 文字"更容易在纯白背景上认出来
      Row() {
        Text(this.glyph)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor('#FFFFFF')
      }
      .width(GLYPH_SIZE)
      .height(GLYPH_SIZE)
      .borderRadius(UiTheme.gapXs)
      .backgroundColor(this.tone)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      if (this.showLabel) {
        Text(this.label)
          .fontSize(UiTheme.fontSizeCaption)
          .fontColor(this.tone)
      }
    }
    .padding({ left: 3, right: UiTheme.gapS, top: 2, bottom: 2 })
    .border({ width: 1, color: this.tone })
    .borderRadius(UiTheme.gapM)
    .alignItems(VerticalAlign.Center)
  }
}
