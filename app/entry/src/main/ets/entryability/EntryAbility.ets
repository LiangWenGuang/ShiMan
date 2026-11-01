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
