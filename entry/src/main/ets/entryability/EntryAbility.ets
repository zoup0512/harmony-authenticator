import { AbilityConstant, UIAbility, Want, common, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountStore } from '../store/AccountStore';
import { Theme } from '../common/Theme';

const TAG: string = 'Authenticator/Ability';
const DOMAIN: number = 0x1002;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    // 首帧前把深浅色灌进 AppStorage，页面第一帧就能按正确色板渲染
    this.syncColorMode(this.context.config);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');
    this.mainWindow = windowStage.getMainWindowSync();

    // 先加载本地账户，再进首页，避免首页读到空数据闪一下空状态
    AccountStore.getInstance().init(this.context).catch((err: Object) => {
      hilog.error(DOMAIN, TAG, `store init error: ${JSON.stringify(err)}`);
    }).then(() => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, `loadContent failed: ${JSON.stringify(err)}`);
          return;
        }
        hilog.info(DOMAIN, TAG, 'loadContent succeed');
      });
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, `onConfigurationUpdate colorMode=${newConfig.colorMode}`);
    this.syncColorMode(newConfig);
  }

  /** 系统深浅色同步到 AppStorage，组件通过 @StorageProp 自动重绘 */
  private syncColorMode(config: Configuration): void {
    const dark: boolean = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate(Theme.KEY_DARK_MODE, dark);
    this.applySystemBarColor(dark);
  }

  /** 状态栏/导航栏图标色随深浅色切换 */
  private applySystemBarColor(dark: boolean): void {
    if (this.mainWindow === undefined) {
      return;
    }
    const c: string = dark ? '#E2E2E9' : '#191C20';
    this.mainWindow.setWindowSystemBarProperties({
      statusBarContentColor: c,
      isStatusBarLightIcon: !dark,
      navigationBarContentColor: c,
      isNavigationBarLightIcon: !dark
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }
}
