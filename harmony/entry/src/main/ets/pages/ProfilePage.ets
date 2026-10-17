/**
 * ProfilePage · 我的（一级页签）· **本轮实装**
 *
 * 页面契约：`@Param pageParam: ProfilePageParam`（定义在 `types/PageParams.ets`）
 *   - 继承 `TabPageParam` 的全部字段（activeTab / busy / errorMsg / pathStack）
 *   - 账户信息：`userName` / `email` / `accountId` / `registeredAt` / `serverLabel` / `appVersion`
 *   - 动作：`onLogout(): Promise<void>`（由窗口层实现，登出=客户端删令牌）
 *
 * ══════════════════ 本轮（我的页搭建轮）交付 ══════════════════
 * ① **账户信息卡**：头像占位（用户名首字）+ 用户名 + 邮箱；下面四行只读信息
 *    （账号 ID / 注册日期 / 服务端地址 / 应用版本）。
 * ② **退出登录**：与全应用一致的两段式交互 —— 先弹 `ConfirmSheet` 二次确认
 *    （说明"会清除本机登录状态与业务缓存"），确认后按钮进入"正在退出…"，
 *    完成后由窗口层切回登录流。
 * ③ 视觉全部取 `common/UiTheme.ets`：卡片 16vp 圆角 + 1px 描边 + 极淡投影（白卡浮在灰页底上），
 *    主/次按钮与登录页同款。
 *
 * ★ 页面纪律：不 import 任何 store、不发请求、不碰路由栈 —— 登出只调 `pageParam.onLogout()`。
 * ★ 数据是"进页面时一次性拿到"的静态投影，所以走参数契约（不存在 BUG-10/11 那类
 *   "挂载后改字段不刷新"的问题）。页签切换到本页时会重新投影一次。
 */

import { UiTheme } from '../common/UiTheme';
import { ProfilePageParam } from '../types/PageParams';
import { RevealCard } from '../components/RevealCard';
import { PageHeader } from '../components/PageHeader';
import { AppCard } from '../components/AppCard';
import { ConfirmSheet } from '../components/ConfirmSheet';

/** 头像占位圆的直径 */
const AVATAR_SIZE: number = 56;

/** 信息行的取数模型 · 只在 build 里用一次（见下方 `infoRows`） */
class InfoRow {
  label: string = '';
  value: string = '';

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value.length > 0 ? value : '—';
  }
}

@ComponentV2
export struct ProfilePage {
  /** ★ 本页唯一入参 */
  @Param pageParam: ProfilePageParam = new ProfilePageParam();

  /** 二次确认弹层是否显示 */
  @Local confirmVisible: boolean = false;

  /** 是否正在退出（禁用按钮 + 改文案） */
  @Local loggingOut: boolean = false;

  /** 头像里的首字 · 没取到用户名时用"我"占位 */
  @Computed
  get avatarText(): string {
    const name: string = this.pageParam.userName;
    if (name.length === 0) {
      return '我';
    }
    return name.substring(0, 1).toUpperCase();
  }

  /** 用户名（为空时给一句可读的占位，而不是留白） */
  @Computed
  get displayName(): string {
    return this.pageParam.userName.length > 0 ? this.pageParam.userName : '未取到账号信息';
  }

  /** 邮箱（后端可为 null，窗口层已统一转成空串） */
  @Computed
  get emailLabel(): string {
    return this.pageParam.email.length > 0 ? this.pageParam.email : '未填写邮箱';
  }

  /** 退出按钮文案 */
  @Computed
  get logoutLabel(): string {
    return this.loggingOut ? '正在退出…' : '退出登录';
  }

  /**
   * 四行只读信息
   * ★ 取数放在 `@Computed` 里，`ForEach` 直接渲染 —— 不使用带参数的 `@Builder`
   *   （BUG-19：builder 参数不在响应式依赖链上，会"停在首次构建的值"）。
   */
  @Computed
  get infoRows(): InfoRow[] {
    const p: ProfilePageParam = this.pageParam;
    return [
      new InfoRow('账号 ID', p.accountId),
      new InfoRow('注册日期', p.registeredAt),
      new InfoRow('服务端', p.serverLabel),
      new InfoRow('应用版本', p.appVersion)
    ];
  }

  /** 点「退出登录」：先要二次确认，避免误触把登录态清掉 */
  private askLogout(): void {
    if (this.loggingOut) {
      return;
    }
    this.confirmVisible = true;
  }

  /** 确认退出：交给窗口层，登出完成后界面会自动回到登录流 */
  private confirmLogout(): void {
    if (this.loggingOut) {
      return;
    }
    this.loggingOut = true;
    this.pageParam.onLogout()
      .then((): void => {
        // 成功时本页马上会被卸载（窗口层切成登录流），这里只是兜底复位
        this.loggingOut = false;
        this.confirmVisible = false;
      })
      .catch((): void => {
        this.loggingOut = false;
        this.confirmVisible = false;
      });
  }

  // ══════════════════ 界面 ══════════════════

  /** 账户头（头像 + 用户名 + 邮箱） */
  @Builder
  accountHeader() {
    Row({ space: UiTheme.gapM }) {
      // 头像占位：主色圆 + 用户名首字（拿到真人像再说，这里不引入图片资源）
      Text(this.avatarText)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(UiTheme.cardBackground)
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(AVATAR_SIZE / 2)
        .backgroundColor(UiTheme.primary)
        .textAlign(TextAlign.Center)

      Column({ space: UiTheme.gapXs }) {
        Text(this.displayName)
          .fontSize(UiTheme.fontSizeSection)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.emailLabel)
          .fontSize(UiTheme.fontSizeBody)
          .fontColor(UiTheme.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ── 页面本体 ──
      Scroll() {
        Column({ space: UiTheme.gapL }) {
          // 0 号位 · 转场由 RevealCard 内部负责
          RevealCard({ order: 0 }) {
            Column() {
              PageHeader({ title: '我的', subtitle: '账号与设置' })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ① 账号信息（1 号位）
          RevealCard({ order: 1 }) {
            AppCard({ title: '账号信息' }) {
              Column({ space: UiTheme.gapL }) {
                this.accountHeader()

                // 分隔线：卡片内部不再叠一层底，只用一条 divider 划开（见 UiTheme 顶部纪律）
                Divider().color(UiTheme.divider)

                Column({ space: UiTheme.gapM }) {
                  ForEach(this.infoRows, (row: InfoRow) => {
                    Row({ space: UiTheme.gapM }) {
                      Text(row.label)
                        .fontSize(UiTheme.fontSizeBody)
                        .fontColor(UiTheme.textSecondary)
                        .width(76)
                        .textAlign(TextAlign.Start)

                      Text(row.value)
                        .fontSize(UiTheme.fontSizeBody)
                        .fontColor(UiTheme.textPrimary)
                        .layoutWeight(1)
                        .textAlign(TextAlign.End)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                  }, (row: InfoRow) => row.label)
                }
                .width('100%')
              }
              .width('100%')
            }
          }

          // ② 退出登录（2 号位 · 与全应用一致的次按钮：白底 + 描边）
          RevealCard({ order: 2 }) {
            Column({ space: UiTheme.gapS }) {
              Button(this.logoutLabel)
                .width('100%')
                .height(UiTheme.controlHeight)
                .fontSize(UiTheme.fontSizeSection)
                // 危险动作归 danger：这是"会清掉本机登录态"的操作，不能用正文色被读成普通次按钮
                .fontColor(UiTheme.danger)
                .backgroundColor(UiTheme.cardBackground)
                .borderWidth(1)
                .borderColor(UiTheme.divider)
                .borderRadius(UiTheme.buttonRadius)
                .enabled(!this.loggingOut)
                .onClick(() => {
                  this.askLogout();
                })

              Text('退出后会清除本机的登录状态与业务缓存，需要重新登录才能继续使用。')
                .fontSize(UiTheme.fontSizeCaption)
                .fontColor(UiTheme.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .padding({
          left: UiTheme.pagePadding,
          right: UiTheme.pagePadding,
          top: UiTheme.gapL,
          bottom: UiTheme.gapXl
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .backgroundColor(UiTheme.pageBackground)

      // ── 二次确认弹层（覆盖全页）──
      if (this.confirmVisible) {
        ConfirmSheet({
          title: '退出登录',
          message: '退出后需要重新输入用户名和密码才能继续使用 MindScope。',
          confirmLabel: this.loggingOut ? '正在退出…' : '确认退出',
          cancelLabel: '取消',
          busy: this.loggingOut,
          onCancel: () => {
            this.confirmVisible = false;
          },
          onConfirm: () => {
            this.confirmLogout();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.pageBackground)
  }
}
