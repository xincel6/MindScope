/**
 * SkeletonView · 骨架屏（规范：加载时显示骨架屏）
 *
 * 两个用途：
 *  ① `AuthSkeleton`   —— 登录/注册页的骨架（冷启动引导中，还不知道该显示登录页还是主界面时）
 *  ② `MainSkeleton`   —— 主界面的骨架（页签内容加载中；本轮占位页无数据源，由参数 busy 驱动）
 *
 * ★ 骨架块用一个浅色圆角矩形实现，不做流光动画：
 *   规范要求"少用大面积效果"，静止的色块足够表达"正在加载"。
 */

import { UiTheme } from '../common/UiTheme';

/** 骨架块 · 一个浅色圆角矩形 */
@ComponentV2
export struct SkeletonBlock {
  @Param blockWidth: string = '100%';
  @Param blockHeight: number = 16;
  @Param radius: number = UiTheme.gapXs;

  build() {
    Row()
      .width(this.blockWidth)
      .height(this.blockHeight)
      .borderRadius(this.radius)
      .backgroundColor(UiTheme.fillSoft)
  }
}

/** 登录/注册页的骨架屏 · 与真实登录页同构，避免加载完成时布局跳动 */
@ComponentV2
export struct AuthSkeleton {
  build() {
    Column({ space: UiTheme.gapXl }) {
      SkeletonBlock({ blockWidth: '96vp', blockHeight: UiTheme.logoSize, radius: UiTheme.logoRadius })

      Column({ space: UiTheme.gapS }) {
        SkeletonBlock({ blockWidth: '70%', blockHeight: 24 })
        SkeletonBlock({ blockWidth: '45%', blockHeight: 14 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: UiTheme.gapM }) {
        SkeletonBlock({ blockHeight: UiTheme.controlHeight, radius: UiTheme.cardRadius })
        SkeletonBlock({ blockHeight: UiTheme.controlHeight, radius: UiTheme.cardRadius })
        SkeletonBlock({ blockHeight: UiTheme.controlHeight, radius: UiTheme.cardRadius })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(UiTheme.pagePadding)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }
}

/** 主界面的骨架屏 · 标题 + 若干卡片占位 */
@ComponentV2
export struct MainSkeleton {
  build() {
    Column({ space: UiTheme.gapL }) {
      SkeletonBlock({ blockWidth: '40%', blockHeight: 24 })

      Column({ space: UiTheme.gapM }) {
        SkeletonBlock({ blockHeight: 96, radius: UiTheme.cardRadius })
        SkeletonBlock({ blockHeight: 96, radius: UiTheme.cardRadius })
        SkeletonBlock({ blockHeight: 96, radius: UiTheme.cardRadius })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(UiTheme.pagePadding)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.pageBackground)
  }
}
