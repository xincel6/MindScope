import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppBootstrap } from '../common/AppBootstrap';
import { Logger } from '../common/Logger';
import { LOG_DOMAIN, LOG_TAG } from '../types/Index';

export default class EntryAbility extends UIAbility {
  /**
   * 生命周期最开始 · **从这里启动数据层**
   *
   * ★ `AppBootstrap.start()` 是同步返回的：内部用 Promise 自跑「读本地缓存 → 校验令牌 →
   *   并发拉取 media / reports / stats」，不会拖慢首帧。
   * ★ 这里不 await、不跳路由、不碰 windowStage —— 本方法**不含任何 UI 内容**，
   *   页面该渲染什么由 UI 读 `AppStore.get().bootPhase` 自行决定。
   */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      Logger.e('设置色彩模式失败', err as Object);
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onCreate');

    // 数据存储类 + 服务端取数：全部在这里点火
    AppBootstrap.start(this.context);
  }

  onDestroy(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onDestroy');
    // 释放 WS 连接与 RDB 句柄
    AppBootstrap.shutdown();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', 'Ability onBackground');
  }
}
