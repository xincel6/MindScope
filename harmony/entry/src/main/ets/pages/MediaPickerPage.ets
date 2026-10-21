/**
 * MediaPickerPage · **素材选择页**（工作台二级页面）
 *
 * 页面契约（★ 直接传入参数即可展示本页，页面内不引用任何 store / 不发请求）：
 * ```ts
 * const param = new MediaPickerPageParam();
 * param.onPickRequest = async () => { ... };   // 窗口层打开系统选择器
 * param.onUpload = async (patient: string) => { ... }; // 窗口层上传（带患者名）并出栈回工作台
 * param.pickedName = 'interview.mp4';
 * ```
 *
 * 布局：⓪ 患者姓名（可选）① 选择卡片 ② 已选素材预览 ③ 上传状态（进度 / 错误） ④ 主按钮 ⑤ 格式说明。
 * 页面自己的本地状态只有两个：`submitting`（回调返回前的兜底防连点）与 `patientName`。
 * 其余全部来自参数 —— 因为"选中的素材"属于业务数据，应由窗口层持有。
 *
 * ══════════════════ ★★ 为什么"选完就自动开始"（BUG-11）══════════════════
 * 原本的交互是"选素材 → 再按一次「开始分析」→ 才上传跳转"。这个多出来的一步在真机上
 * 被用户直接理解成"我选了但什么都没发生"（实测反馈：*选了图片后没进入分析页面，
 * 仍旧停在素材选择页，等于没选*）。而在同一时期，参数类不是 `@ObservedV2`，
 * 选完素材后连"预览 + 按钮文案"都不会更新，于是页面上**真的什么都没变**。
 *
 * 现在：
 *   ① `MediaPickerPageParam` 是 `@ObservedV2`（见 `types/PageParams.ets` 的说明），
 *      选完素材立刻能看到预览、按钮变成「开始分析」、错误文案能显示；
 *   ② **选到素材就自动接着上传并回到工作台**（`requestPick → submit`），
 *      用户的心智链路"选完即开始分析"不用再点第二次；
 *   ③ 主按钮保留：上传失败时它就是**重试**入口（此时 `hasPicked` 仍为 true）。
 *
 * ★ 页面的忙碌状态同时看参数里的 `uploading` 与本地 `submitting`：
 *   前者是权威来源（窗口层正在上传），后者只负责"回调还没返回"的那一小段时间，
 *   避免用户在系统选择器弹出前连点两下。
 * ★ 自动上传链路里**不能读 `@Computed` 的 `busy`**，原因见 `isBusyNow()` 的注释。
 */

import { UiTheme } from '../common/UiTheme';
import { Logger } from '../common/Logger';
import { MediaPickerPageParam } from '../types/PageParams';
import { PageHeader } from '../components/PageHeader';
import { RippleCard } from '../components/RippleCard';
import { ProgressBar } from '../components/common/ProgressBar';

@ComponentV2
export struct MediaPickerPage {
  /** ★ 本页唯一入参 */
  @Param pageParam: MediaPickerPageParam = new MediaPickerPageParam();

  /** 调回调期间按钮禁用，避免连点弹出两次系统选择器 */
  @Local submitting: boolean = false;

  /**
   * 患者姓名（可选）· 提交时随上传一起带给窗口层
   *
   * ★ 为什么放在这一页而不是参数类：它只在这一页存活、只在 `onUpload` 那一刻被读取，
   *   重进页面本来就该清空 —— 用 `@Local` 语义最直白。
   * ★ 页面不会等它非空才上传：素材选完就自动上传（见 BUG-11），
   *   所以输入框放在最上面，用户先看到"可以命名"，再点下面的素材卡片。
   */
  @Local patientName: string = '';

  /** 是否处于忙碌（仅用于 UI 的禁用与样式） */
  @Computed
  get busy(): boolean {
    return this.pageParam.uploading || this.submitting;
  }

  /**
   * 逻辑分支用的忙碌判定 · 读**原始字段**，不要读上面的 `busy`
   *
   * ★ 坑（实机定位）：`@Computed` 只在渲染期刷新。`requestPick()` 的 `.then` 回调
   *   在渲染之外执行，此时 `busy` 还是"等待选择器"那一帧的缓存值 `true`，
   *   于是 `submit()` 的第一行 `if (this.busy) return` 把自动上传永久挡掉 ——
   *   表现就是"选完素材后页面停在已选状态，必须手动再点一次开始分析"。
   */
  private isBusyNow(): boolean {
    return this.submitting || this.pageParam.uploading;
  }

  /** 主按钮文案 */
  @Computed
  get actionLabel(): string {
    if (this.pageParam.uploading) {
      return '上传中…';
    }
    return this.pageParam.hasPicked ? '开始分析' : '选择素材';
  }

  /**
   * 点「选择素材」· 交给窗口层开系统选择器
   *
   * ★ 选到素材后**立刻**接着走 `submit()`（上传 + 出栈回工作台）。
   *   `submitting` 必须先落回 false 再调 `submit()`，否则会被它自己的 `busy` 挡掉。
   * ★ 用户取消（回调返回 false）则什么都不做：取消不是错误，不能弹红字。
   */
  private requestPick(): void {
    if (this.isBusyNow()) {
      Logger.i('[MediaPicker] requestPick 被 busy 挡下');
      return;
    }
    this.submitting = true;
    this.pageParam.onPickRequest()
      .then((picked: boolean) => {
        this.submitting = false;
        Logger.i(`[MediaPicker] 选择器返回 picked=${picked} hasPicked=${this.pageParam.hasPicked}`);
        // ★ 再确认一次 `hasPicked`：回调说"选到了"但参数没被回填时，
        //   直接进 submit() 会因为它自己的分支又去开一次系统选择器。
        if (picked && this.pageParam.hasPicked) {
          this.submit();
        }
      })
      .catch(() => {
        Logger.e('[MediaPicker] 选择回调抛异常（详情见窗口层日志）');
        this.submitting = false;
      });
  }

  /** 点「开始分析」· 交给窗口层上传 + 返回工作台 */
  private submit(): void {
    Logger.i(`[MediaPicker] submit busy=${this.isBusyNow()} uploading=${this.pageParam.uploading} hasPicked=${this.pageParam.hasPicked} patient="${this.patientName}"`);
    if (this.isBusyNow()) {
      return;
    }
    if (!this.pageParam.hasPicked) {
      this.requestPick();
      return;
    }
    this.submitting = true;
    this.pageParam.onUpload(this.patientName.trim())
      .then((ok: boolean) => {
        this.submitting = false;
        Logger.i(`[MediaPicker] 上传回调返回 ok=${ok} errorMsg="${this.pageParam.errorMsg}"`);
      })
      .catch(() => {
        Logger.e('[MediaPicker] 上传回调抛异常（详情见窗口层日志）');
        this.submitting = false;
      });
  }

  /**
   * 卡片前的类型图标（本轮从"单字占位"换成 SVG 资源）
   *
   * ★ 为什么换：`素` / `图` / `视` 三个汉字当图标，在真机上就是三个不同宽度的方块字，
   *   摆在 44×44 的浅薄荷底砖里既不像图标，也和底部页签那套线性图标不是一套东西；
   *   空态那个"素"尤其容易被读成页面名而不是动作。
   * ★ 三份 SVG 的颜色都烤成主色（`#0D9488`），没有走 `Image.fillColor()`：
   *   它只改填充不改描边，线性图标会"换了个色还是灰的"（同 `PageRoutes.MAIN_TABS` 的注释）。
   */
  private pickIcon(): Resource {
    if (!this.pageParam.hasPicked) {
      return $r('app.media.media_add');
    }
    return this.pageParam.pickedIsVideo ? $r('app.media.media_video') : $r('app.media.media_image');
  }

  build() {
    Column({ space: UiTheme.gapL }) {
      PageHeader({
        title: this.pageParam.title,
        subtitle: '支持图片与视频，选择后立即上传并开始辅助评估',
        showBack: true,
        onBack: () => {
          this.pageParam.onBack();
        }
      })

      Scroll() {
        Column({ space: UiTheme.gapL }) {
          // ── ⓪ 患者姓名（可选）· 上传时随请求带给服务端 ──
          // ★ 放在素材卡片之前：素材一选完就自动上传，用户来不及回头补名字
          Column({ space: UiTheme.gapS }) {
            Text('患者姓名')
              .fontSize(UiTheme.fontSizeSection)
              .fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Start)

            TextInput({ text: this.patientName, placeholder: '选填，例如：张三' })
              .type(InputType.Normal)
              .maxLength(64)
              .height(UiTheme.controlHeight)
              .fontSize(UiTheme.fontSizeBody)
              .fontColor(UiTheme.textPrimary)
              .placeholderColor(UiTheme.textSecondary)
              .backgroundColor(UiTheme.fillSoft)
              .borderRadius(UiTheme.cardRadius)
              .padding({ left: UiTheme.gapM, right: UiTheme.gapM })
              .enabled(!this.pageParam.uploading)
              .onChange((value: string) => {
                this.patientName = value;
              })

            Text('留空则不命名，之后可在素材库补填')
              .fontSize(UiTheme.fontSizeCaption)
              .fontColor(UiTheme.textSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .padding(UiTheme.cardPadding)
          .backgroundColor(UiTheme.cardBackground)
          .borderRadius(UiTheme.cardRadius)
          .alignItems(HorizontalAlign.Start)

          // ── ① 选择卡片：整卡可点，等价于点"选择/重新选择" ──
          RippleCard({
            onTap: () => {
              this.requestPick();
            }
          }) {
            Row({ space: UiTheme.gapM }) {
              // 素材图标底：空态画"加一张图"，选中后按类型换成图片 / 视频图标
              Column() {
                Image(this.pickIcon())
                  .width(22)
                  .height(22)
                  .objectFit(ImageFit.Contain)
                  .draggable(false)
                  .interpolation(ImageInterpolation.High)
              }
              .width(44)
              .height(44)
              .borderRadius(UiTheme.cardRadius)
              .backgroundColor(UiTheme.fillSoft)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Column({ space: UiTheme.gapXs }) {
                Text(this.pageParam.hasPicked ? this.pageParam.pickedName : '尚未选择素材')
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .textAlign(TextAlign.Start)

                Text(this.pageParam.hasPicked ? '点击卡片可重新选择' : '点击卡片打开系统相册')
                  .fontSize(UiTheme.fontSizeCaption)
                  .fontColor(UiTheme.textSecondary)
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text('›')
                .fontSize(24)
                .fontColor(UiTheme.textSecondary)
                .width(20)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }

          // ── ② 已选素材预览 ──
          if (this.pageParam.hasPicked) {
            RippleCard({ _padding: UiTheme.cardPadding }) {
              Column({ space: UiTheme.gapM }) {
                Text('已选素材')
                  .fontSize(UiTheme.fontSizeSection)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(UiTheme.textPrimary)
                  .width('100%')
                  .textAlign(TextAlign.Start)

                // 图片能直接预览本地 URI；视频本轮不给播放器，用占位块表达类型
                if (this.pageParam.pickedIsVideo) {
                  Column({ space: UiTheme.gapS }) {
                    // 视频没有缩略图可画，用一枚视频图标表达类型（播放器下轮实现）
                    Image($r('app.media.media_video'))
                      .width(40)
                      .height(40)
                      .objectFit(ImageFit.Contain)
                      .draggable(false)
                      .interpolation(ImageInterpolation.High)
                    Text('视频素材 · 播放器下轮实现')
                      .fontSize(UiTheme.fontSizeCaption)
                      .fontColor(UiTheme.textSecondary)
                  }
                  .width('100%')
                  .height(160)
                  .borderRadius(UiTheme.cardRadius)
                  .backgroundColor(UiTheme.fillSoft)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                } else {
                  Image(this.pageParam.pickedUri)
                    .width('100%')
                    .height(160)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(UiTheme.cardRadius)
                    .backgroundColor(UiTheme.fillSoft)
                }

                Text(this.pageParam.pickedName)
                  .fontSize(UiTheme.fontSizeBody)
                  .fontColor(UiTheme.textSecondary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .textAlign(TextAlign.Start)

                // 命名会随上传写进服务端，这里回显让用户确认自己填对了
                if (this.patientName.trim().length > 0) {
                  Text(`患者：${this.patientName.trim()}`)
                    .fontSize(UiTheme.fontSizeBody)
                    .fontColor(UiTheme.primary)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }

          // ── ③ 上传进度（服务端不返回百分比，所以这里是"不确定进度"的表达） ──
          if (this.pageParam.uploading) {
            Column({ space: UiTheme.gapS }) {
              Text('正在上传到服务端…')
                .fontSize(UiTheme.fontSizeBody)
                .fontColor(UiTheme.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Start)
              // ★ 上传接口拿不到进度回调（HttpClient 未暴露 flush 回调），
              //   这里用一条"进行中"的满色条表达状态，不做假动画 —— 假装有进度更糟。
              // ★ 轨道色显式指定 fillSoft：组件默认的 progressTrack 是给旧纯白页底配的，
              //   在白卡上会淡到看不出是条进度条（见共享验收清单第 4 条）。
              ProgressBar({ ratio: 1, barColor: UiTheme.primary, barHeight: 6, trackColor: UiTheme.fillSoft })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ── ④ 错误提示（规范：失败要有明确出口） ──
          if (this.pageParam.errorMsg.length > 0) {
            Row({ space: UiTheme.gapS }) {
              Text(this.pageParam.errorMsg)
                .fontSize(UiTheme.fontSizeBody)
                .fontColor(UiTheme.danger)
                .layoutWeight(1)
                .textAlign(TextAlign.Start)
            }
            .width('100%')
          }

          // ── ⑤ 主按钮 ──
          Button(this.actionLabel)
            .width('100%')
            .height(UiTheme.controlHeight)
            .fontSize(UiTheme.fontSizeSection)
            .fontColor(UiTheme.cardBackground)
            .backgroundColor(UiTheme.primary)
            .borderRadius(UiTheme.buttonRadius)
            .enabled(!this.busy)
            .onClick(() => {
              this.submit();
            })

          // ── ⑥ 格式说明（把后端的白名单前置到 UI，避免上传后才被 400 拒掉） ──
          Text('支持的格式：jpg / jpeg / png / bmp / mp4 / avi / mov / webm')
            .fontSize(UiTheme.fontSizeCaption)
            .fontColor(UiTheme.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
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
