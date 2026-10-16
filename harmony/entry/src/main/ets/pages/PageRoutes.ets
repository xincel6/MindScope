/**
 * PageRoutes · **全部路由名与页签元数据的唯一文件**
 *
 * 页面名（字符串）是在 `Navigation` 的 `navDestination` 分发器里硬比对的，
 * 一旦两处写得不一致就会"点了没反应"且不报错 —— 所以名字只在这里定义一次。
 *
 * 三份内容：
 *   ① 登录流两个页面的路由名常量
 *   ② 五个一级页签的顺序 / 中文名 / 字形的元数据表（`MAIN_TABS`）
 *   ③ 按枚举取中文名与字形的小工具
 *
 * ★ 一级页签直接用 `MainTab` 枚举值当路由名（页签名与路由名本就是同一批字符串），
 *   不再单独维护一份 `MainRoute`，避免两处漂移。
 * ★ 其它页面（后续的"素材详情""报告详情"）在本文件继续追加。
 * ★ 本文件放在 `pages/` 下：它是"页面之间怎么走"的约定，与页面代码同域；
 *   页面参数契约在 `types/PageParams.ets`，视觉令牌在 `common/UiTheme.ets`。
 */

import { MainTab } from '../types/PageParams';

// ══════════════════ ① 路由名常量 ══════════════════

/** 登录页路由名 */
export const LOGIN_ROUTE: string = 'login';

/** 注册页路由名 */
export const REGISTER_ROUTE: string = 'register';

/**
 * 素材选择页路由名（工作台二级页）
 * ★ 二级页面用 `pushPathByName` 入栈，系统返回键即可回到工作台，
 *   所以页面**不需要**自己实现"返回上一页"的栈操作。
 */
export const MEDIA_PICKER_ROUTE: string = 'mediaPicker';

/**
 * 分析详情页路由名（工作台二级页）
 * ★ 本轮它是**占位页**（图表组件未实现），但进度的数据是真的（走 WS）。
 */
export const ANALYSIS_DETAIL_ROUTE: string = 'analysisDetail';


// ══════════════════ ② 页签元数据 ══════════════════

/** 一个底部页签的展示元数据 */
export class MainTabMeta {
  /** 页签标识 · 同时是路由名 */
  public tab: MainTab = MainTab.workbench;
  /** 底部按钮与页面标题的中文名 */
  public label: string = '';
  /** 底部按钮的字形（本轮不引入图片资源，用单字代替图标） */
  public glyph: string = '';

  constructor(tab: MainTab, label: string, glyph: string) {
    this.tab = tab;
    this.label = label;
    this.glyph = glyph;
  }
}

/**
 * 五个一级页签 · **顺序即底部导航栏的展示顺序**
 * ★ 用户指定顺序：工作台 / 素材库 / 历史报告 / 统计 / 我的
 */
export const MAIN_TABS: MainTabMeta[] = [
  new MainTabMeta(MainTab.workbench, '工作台', '析'),
  new MainTabMeta(MainTab.media, '素材库', '库'),
  new MainTabMeta(MainTab.reports, '历史报告', '报'),
  new MainTabMeta(MainTab.stats, '统计', '统'),
  new MainTabMeta(MainTab.profile, '我的', '我')
];

// ══════════════════ ③ 小工具 ══════════════════

/** 取页签的中文名（找不到时回退为第一项，保证界面不出现空白标题） */
export function mainTabLabel(tab: MainTab): string {
  return metaOf(tab).label;
}

/** 取页签的字形 */
export function mainTabGlyph(tab: MainTab): string {
  return metaOf(tab).glyph;
}

/** 按枚举找元数据 · 找不到时返回第一项兜底 */
function metaOf(tab: MainTab): MainTabMeta {
  for (let i = 0; i < MAIN_TABS.length; i++) {
    if (MAIN_TABS[i].tab === tab) {
      return MAIN_TABS[i];
    }
  }
  return MAIN_TABS[0];
}
