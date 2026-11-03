import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SourceRegistry } from '../source/SourceRegistry';
import { Library } from '../store/Library';
import { Trace } from '../util/Trace';

const DOMAIN: number = 0x0001;
const TAG: string = 'Manyu';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    Trace.init(this.context.filesDir);
    // 应用采用深色主题，统一设置系统状态栏与导航栏，避免启动页出现白色条带。
    try {
      const mainWindow = await windowStage.getMainWindow();
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#0D1117',
        navigationBarColor: '#0D1117',
        isStatusBarLightIcon: true,
        isNavigationBarLightIcon: true,
        statusBarContentColor: '#F4F7FB',
        navigationBarContentColor: '#F4F7FB'
      });
    } catch (error) {
      // 部分设备/模拟器不支持运行时设置时，保持系统默认，不阻塞页面启动。
      Trace.write('window', 'system bar style unavailable: ' + String(error));
    }
    // 图源与本地库在首帧之前准备好，避免页面拿到空列表
    try {
      await SourceRegistry.get().init(this.context);
      await Library.get().init(this.context);
      Trace.write('boot', 'sources+' + SourceRegistry.get().count() + ' library ok');
    } catch (error) {
      Trace.write('boot', 'init failed ' + String(error));
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s', JSON.stringify(error));
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'content loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }
}
