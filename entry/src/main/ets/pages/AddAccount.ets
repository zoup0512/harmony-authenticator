

import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AccountStore } from '../store/AccountStore';
import { OtpType, AccountInfo } from '../model/Account';
import { OtpEngine } from '../otp/OtpEngine';
import { OtpUri } from '../otp/OtpUri';
import { Theme, Palette } from '../common/Theme';
import { SegmentedButtons } from '../components/SegmentedButtons';
import { CountdownRing } from '../components/CountdownRing';

@Entry
@Component
struct AddAccount {
  @StorageProp(Theme.KEY_DARK_MODE) private isDark: boolean = false;
  /** 0 手动输入 / 1 链接导入 */
  @State mode: number = 0;
  @State issuerInput: string = '';
  @State nameInput: string = '';
  @State secretInput: string = '';
  @State typeIndex: number = 0;
  @State digitsIndex: number = 0;
  @State algIndex: number = 0;
  @State periodIndex: number = 0;
  @State counterInput: string = '0';
  @State uriInput: string = '';
  @State uriError: string = '';
  @State remainTick: number = Date.now();
  @State saving: boolean = false;
  @State scanning: boolean = false;
  private disposed: boolean = false;
  @State importedDigits: number = 6;
  @State importedPeriod: number = 30;
  private previewCacheKey: string = '';
  private previewCacheCode: string = '';

  onPageShow(): void { this.startTimer(); }
  onPageHide(): void { this.stopTimer(); }
  private store: AccountStore = AccountStore.getInstance();
  private timerId: number = -1;

  aboutToAppear(): void { this.disposed = false; this.startTimer(); }
  aboutToDisappear(): void { this.disposed = true; this.stopTimer(); }
  private startTimer(): void {
    if (this.timerId >= 0) return;
    this.remainTick = Date.now();
    this.timerId = setInterval(() => { this.remainTick = Date.now(); }, 250);
  }
  private stopTimer(): void {
    if (this.timerId >= 0) { clearInterval(this.timerId); this.timerId = -1; }
  }

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column() {
          Button(this.scanning ? '扫描中…' : '扫描二维码')
            .enabled(!this.scanning && !this.saving)
            .width('100%')
            .height(48)
            .borderRadius(24)
            .backgroundColor(this.pal().secondaryContainer)
            .fontColor(this.pal().onSecondaryContainer)
            .margin({ bottom: 20 })
            .onClick(() => { this.scanAccount(); })

          SegmentedButtons({
            options: ['手动输入', '链接导入'],
            selected: this.mode,
            onSelect: (index: number) => {
              this.mode = index;
            }
          })
          .margin({ bottom: 20 })

          if (this.mode === 0) {
            this.ManualForm()
          } else {
            this.UriForm()
          }
        }
        .padding({ left: 20, right: 20, top: 6, bottom: 32 })
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      this.SaveButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surface)
  }

  @Builder TopBar() {
    Row({ space: 4 }) {
      Button() {
        Image($r('sys.media.ohos_ic_back'))
          .width(24)
          .height(24)
          .fillColor(this.pal().onSurface)
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor('transparent')
      .onClick(() => {
        this.getUIContext().getRouter().back();
      })
      Text('添加账户')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().onSurface)
    }
    .width('100%')
    .padding({ left: 8, right: 16, top: 10, bottom: 12 })
  }

  @Builder FieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.pal().onSurfaceVariant)
      .margin({ top: 16, bottom: 6 })
  }

  @Builder ManualForm() {
    Column() {
      this.FieldLabel('服务名称（可选，如 GitHub）')
      TextInput({ placeholder: '例如：GitHub', text: this.issuerInput })
        .onChange((value: string) => {
          this.issuerInput = value;
        })
        .height(48)
        .borderRadius(14)
        .backgroundColor(this.pal().surfaceContainerHigh)

      this.FieldLabel('账户名称')
      TextInput({ placeholder: '例如：alice@example.com', text: this.nameInput })
        .onChange((value: string) => {
          this.nameInput = value;
        })
        .height(48)
        .borderRadius(14)
        .backgroundColor(this.pal().surfaceContainerHigh)

      this.FieldLabel('密钥（Base32，设置两步验证时提供）')
      TextInput({ placeholder: '例如：JBSWY3DPEHPK3PXP', text: this.secretInput })
        .onChange((value: string) => {
          this.secretInput = value;
        })
        .height(48)
        .borderRadius(14)
        .backgroundColor(this.pal().surfaceContainerHigh)
        .fontFamily('monospace')
        .maxLength(128)

      this.FieldLabel('类型')
      SegmentedButtons({
        options: ['基于时间 (TOTP)', '基于计数器 (HOTP)'],
        selected: this.typeIndex,
        onSelect: (index: number) => {
          this.typeIndex = index;
        }
      })

      this.FieldLabel('位数')
      SegmentedButtons({
        options: this.importedDigits === 6 || this.importedDigits === 8 ?
          ['6 位', '8 位'] : ['6 位', '8 位', `${this.importedDigits} 位`],
        selected: this.digitsIndex,
        onSelect: (index: number) => {
          this.digitsIndex = index;
        }
      })

      this.FieldLabel('算法')
      SegmentedButtons({
        options: ['SHA1', 'SHA256'],
        selected: this.algIndex,
        onSelect: (index: number) => {
          this.algIndex = index;
        }
      })

      if (this.typeIndex === 0) {
        this.FieldLabel('刷新周期')
        SegmentedButtons({
          options: this.importedPeriod === 30 || this.importedPeriod === 60 ?
            ['30 秒', '60 秒'] : ['30 秒', '60 秒', `${this.importedPeriod} 秒`],
          selected: this.periodIndex,
          onSelect: (index: number) => {
            this.periodIndex = index;
          }
        })
      } else {
        this.FieldLabel('初始计数器')
        TextInput({ text: this.counterInput })
          .onChange((value: string) => {
            this.counterInput = value.replace(/[^0-9]/g, '');
          })
          .type(InputType.Number)
          .height(48)
          .borderRadius(14)
          .backgroundColor(this.pal().surfaceContainerHigh)
      }

      this.PreviewCard()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder UriForm() {
    Column() {
      this.FieldLabel('粘贴 otpauth:// 链接')
      TextArea({ placeholder: 'otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub', text: this.uriInput })
        .onChange((value: string) => {
          this.uriInput = value;
          this.uriError = '';
        })
        .height(110)
        .borderRadius(14)
        .backgroundColor(this.pal().surfaceContainerHigh)
        .fontFamily('monospace')
        .fontSize(13)
        .maxLength(1024)

      if (this.uriError.length > 0) {
        Text(this.uriError)
          .fontSize(12)
          .fontColor(this.pal().error)
          .margin({ top: 8 })
          .width('100%')
      }

      Button('解析链接')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.pal().secondaryContainer)
        .fontColor(this.pal().onSecondaryContainer)
        .margin({ top: 16 })
        .onClick(() => {
          this.parseUri();
        })

      Column({ space: 6 }) {
        Text('说明')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().onSurfaceVariant)
        Text('在电脑或其他手机上打开两步验证设置页，把二维码对应的 otpauth:// 链接复制过来即可导入。支持 TOTP / HOTP、SHA1 / SHA256、1–9 位、1–3600 秒周期。')
          .fontSize(13)
          .fontColor(this.pal().onSurfaceVariant)
          .lineHeight(20)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 24 })
      .padding(16)
      .borderRadius(16)
      .backgroundColor(this.pal().surfaceContainer)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 实时预览当前验证码 */
  @Builder PreviewCard() {
    Column({ space: 10 }) {
      if (this.previewCode(this.remainTick).length > 0) {
        Row({ space: 14 }) {
          if (this.typeIndex === 0) {
            CountdownRing({
              remainMs: this.previewRemainMs(this.remainTick),
              periodMs: this.previewPeriod() * 1000,
              color: this.pal().primary,
              warnColor: this.pal().error,
              trackColor: this.pal().surfaceContainerHighest,
              ringSize: 34
            })
          }
          Column({ space: 2 }) {
            Text('当前验证码预览')
              .fontSize(12)
              .fontColor(this.pal().onSurfaceVariant)
            Text(this.previewCode(this.remainTick))
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().onSurface)
              .letterSpacing(3)
              .fontFamily('monospace')
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      } else {
        Text('填写名称与密钥后可预览验证码')
          .fontSize(12)
          .fontColor(this.pal().onSurfaceVariant)
      }
    }
    .width('100%')
    .margin({ top: 24 })
    .padding(18)
    .borderRadius(16)
    .backgroundColor(this.pal().surfaceContainer)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder SaveButton() {
    Button(this.saving ? '保存中…' : (this.mode === 0 ? '保存账户' : '解析并保存'))
      .enabled(!this.saving && !this.scanning)
      .buttonStyle(ButtonStyleMode.EMPHASIZED)
      .width('100%')
      .height(52)
      .borderRadius(26)
      .backgroundColor(this.pal().primary)
      .fontColor(this.pal().onPrimary)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .margin({ left: 20, right: 20, bottom: 20, top: 8 })
      .onClick(() => {
        this.save();
      })
  }

  private pal(): Palette {
    return Theme.palette(this.isDark);
  }

  private toast(message: string, duration: number): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: duration });
  }

  private normalizedSecret(): string {
    return this.secretInput.replace(/[\s-]/g, '').toUpperCase();
  }

  private previewPeriod(): number {
    return this.periodIndex === 2 ? this.importedPeriod : (this.periodIndex === 1 ? 60 : 30);
  }

  private previewDigits(): number {
    return this.digitsIndex === 2 ? this.importedDigits : (this.digitsIndex === 1 ? 8 : 6);
  }

  private previewAlgorithm(): string {
    return this.algIndex === 1 ? 'SHA256' : 'SHA1';
  }

  private previewCode(nowMillis: number): string {
    const account = this.draftAccount();
    const step = account.type === OtpType.HOTP ? account.counter :
      Math.floor(nowMillis / (account.period * 1000));
    // Cache validation and HMAC across duplicate builder reads and countdown ticks.
    const key = `${JSON.stringify(account)}:${step}`;
    if (key === this.previewCacheKey) {
      return this.previewCacheCode;
    }
    this.previewCacheKey = key;
    this.previewCacheCode = '';
    if (account.name.length === 0 || !Number.isSafeInteger(account.counter) || account.counter < 0 ||
      !OtpEngine.isValidParameters(account) || !OtpEngine.isValidSecret(account.secret)) {
      return '';
    }
    this.previewCacheCode = account.type === OtpType.HOTP ? OtpEngine.hotp(account) :
      OtpEngine.totp(account, nowMillis);
    return this.previewCacheCode;
  }

  private previewRemainMs(nowMillis: number): number {
    return OtpEngine.remainingMillis(nowMillis, this.previewPeriod());
  }

  /** 用当前表单内容构造一个临时账户用于预览 */
  private draftAccount(): AccountInfo {
    const secret = this.normalizedSecret();
    const issuer = this.issuerInput.trim();
    let name = this.nameInput.trim();
    if (name.length === 0) {
      name = issuer.length > 0 ? issuer : '';
    }
    const account: AccountInfo = {
      id: 0,
      name: name,
      issuer: issuer,
      secret: secret,
      type: this.typeIndex === 1 ? OtpType.HOTP : OtpType.TOTP,
      counter: Number(this.counterInput.length > 0 ? this.counterInput : '0'),
      digits: this.previewDigits(),
      algorithm: this.previewAlgorithm(),
      period: this.previewPeriod(),
      createdAt: 0,
      sortOrder: 0
    };
    return account;
  }

  private async scanAccount(): Promise<void> {
    if (this.scanning || this.saving) return;
    this.scanning = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.toast('无法启动扫码，请重试或使用手动输入', 2200);
        return;
      }
      const result = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      });
      if (this.disposed) return;
      this.parseUri(result.originalValue);
    } catch (error) {
      if (!this.disposed && (error as BusinessError).code !== scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED) {
        this.toast('扫码失败，请重试或使用手动输入、链接导入', 2500);
      }
    } finally {
      this.scanning = false;
    }
  }

  /** 解析链接或扫码结果并回填，供用户核对后保存。 */
  private parseUri(scannedUri?: string): void {
    const text = (scannedUri === undefined ? this.uriInput : scannedUri).trim();
    if (scannedUri !== undefined && text.length === 0) {
      this.toast('未识别到有效的账户二维码，请重试', 2200);
      return;
    }
    if (text.length === 0) {
      this.uriError = '请先粘贴链接';
      return;
    }
    const result = OtpUri.parse(text);
    if (!result.ok) {
      if (scannedUri !== undefined) {
        this.toast('二维码不是有效或受支持的 otpauth 账户，请检查后重试', 2500);
      } else {
        this.uriError = result.error;
      }
      return;
    }
    this.uriError = '';
    // 回填表单并切回手动页签供用户核对
    this.issuerInput = result.issuer;
    this.nameInput = result.name;
    this.secretInput = result.secret;
    this.typeIndex = result.type === OtpType.HOTP ? 1 : 0;
    this.importedDigits = result.digits;
    this.digitsIndex = result.digits === 8 ? 1 : (result.digits === 6 ? 0 : 2);
    this.importedPeriod = result.period;
    this.algIndex = result.algorithm === 'SHA256' ? 1 : 0;
    this.periodIndex = result.period === 60 ? 1 : (result.period === 30 ? 0 : 2);
    this.counterInput = `${result.counter}`;
    this.mode = 0;
    this.toast('已解析链接，请核对后保存', 2000);
  }

  private async save(): Promise<void> {
    if (this.saving || this.scanning) return;
    this.saving = true;
    try {
      if (this.mode === 1) {
      // 链接模式下先解析回填
      const text = this.uriInput.trim();
      if (text.length === 0) {
        this.uriError = '请先粘贴链接';
        return;
      }
      const result = OtpUri.parse(text);
      if (!result.ok) {
        this.uriError = result.error;
        return;
      }
      if (!Number.isSafeInteger(result.counter) || result.counter < 0) {
        this.uriError = '计数器必须为安全范围内的非负整数';
        return;
      }
      await this.store.addAccount(result.name, result.issuer, result.secret, result.type,
        result.digits, result.algorithm, result.period, result.counter);
      this.toast('账户已添加', 1500);
      this.getUIContext().getRouter().back();
      return;
    }

    const secret = this.normalizedSecret();
    const issuer = this.issuerInput.trim();
    let name = this.nameInput.trim();
    if (name.length === 0 && issuer.length > 0) {
      name = issuer;
    }
    if (name.length === 0) {
      this.toast('请填写账户名称', 1800);
      return;
    }
    if (secret.length === 0) {
      this.toast('请填写密钥', 1800);
      return;
    }
    if (!OtpEngine.isValidSecret(secret)) {
      this.toast('密钥格式无效（仅支持 Base32 字符 A-Z 与 2-7）', 2200);
      return;
    }
    const counter = Number(this.counterInput.length > 0 ? this.counterInput : '0');
    if (!Number.isSafeInteger(counter) || counter < 0) {
      this.toast('计数器必须为安全范围内的非负整数', 2200);
      return;
    }
    if (!OtpEngine.isValidParameters(this.draftAccount())) {
      this.toast('验证码参数无效，请检查后重试', 2200);
      return;
    }
    await this.store.addAccount(name, issuer, secret, this.typeIndex === 1 ? OtpType.HOTP : OtpType.TOTP,
      this.previewDigits(), this.previewAlgorithm(), this.previewPeriod(), counter);
    this.toast('账户已添加', 1500);
    this.getUIContext().getRouter().back();
    } catch {
      this.toast('保存失败，请重试', 2200);
    } finally {
      this.saving = false;
    }
  }
}
