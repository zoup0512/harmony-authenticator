import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'Authenticator/Util';

export class ClipboardUtil {
  /** 复制文本到系统剪贴板并提示 */
  static copyText(ui: UIContext, text: string, toast: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      ui.getPromptAction().showToast({ message: toast, duration: 1800, bottom: '36%' });
    }).catch((err: BusinessError) => {
      hilog.error(0, TAG, `copy failed: ${err.code} ${err.message}`);
      ui.getPromptAction().showToast({ message: '复制失败', duration: 1800, bottom: '36%' });
    });
  }
}
