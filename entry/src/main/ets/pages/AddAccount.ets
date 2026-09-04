

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
  @State remainTick: number = 0;
  private store: AccountStore = AccountStore.getInstance();
  private timerId: number = -1;

  aboutToAppear(): void {
    // 预览验证码的倒计时环每秒刷新
    this.timerId = setInterval(() => {
      this.remainTick = Date.now();
    }, 250);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column() {
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
      TextInput({ placeholder: '例如：GitHub' })
        .onChange((value: string) => {
          this.issuerInput = value;
        })
        .height(48)
        .borderRadius(14)
        .backgroundColor(this.pal().surfaceContainerHigh)

      this.FieldLabel('账户名称')
      TextInput({ placeholder: '例如：alice@example.com' })
        .onChange((value: string) => {
          this.nameInput = value;
        })
        .height(48)
        .borderRadius(14)
        .backgroundColor(this.pal().surfaceContainerHigh)

      this.FieldLabel('密钥（Base32，设置两步验证时提供）')
      TextInput({ placeholder: '例如：JBSWY3DPEHPK3PXP' })
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
        options: ['6 位', '8 位'],
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
          options: ['30 秒', '60 秒'],
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
        Text('在电脑或其他手机上打开两步验证设置页，把二维码对应的 otpauth:// 链接复制过来即可导入。支持 TOTP / HOTP、SHA1 / SHA256、6 / 8 位、30 / 60 秒周期。')
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
      if (this.previewCode().length > 0) {
        Row({ space: 14 }) {
          CountdownRing({
            remainMs: this.previewRemainMs(),
            periodMs: this.previewPeriod() * 1000,
            color: this.pal().primary,
            warnColor: this.pal().error,
            trackColor: this.pal().surfaceContainerHighest,
            ringSize: 34
          })
          Column({ space: 2 }) {
            Text('当前验证码预览')
              .fontSize(12)
              .fontColor(this.pal().onSurfaceVariant)
            Text(this.previewCode())
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
    Button(this.mode === 0 ? '保存账户' : '解析并保存')
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
    return this.periodIndex === 1 ? 60 : 30;
  }

  private previewDigits(): number {
    return this.digitsIndex === 1 ? 8 : 6;
  }

  private previewAlgorithm(): string {
    return this.algIndex === 1 ? 'SHA256' : 'SHA1';
  }

  private previewCode(): string {
    const secret = this.normalizedSecret();
    const name = this.nameInput.trim();
    if (name.length === 0 || !OtpEngine.isValidSecret(secret)) {
      return '';
    }
    return OtpEngine.totp(this.draftAccount(), Date.now());
  }

  private previewRemainMs(): number {
    return OtpEngine.remainingMillis(Date.now(), this.previewPeriod());
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

  /** 解析粘贴的 otpauth:// 链接并回填到手动表单 */
  private parseUri(): void {
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
    // 回填表单并切回手动页签供用户核对
    this.issuerInput = result.issuer;
    this.nameInput = result.name;
    this.secretInput = result.secret;
    this.typeIndex = result.type === OtpType.HOTP ? 1 : 0;
    this.digitsIndex = result.digits === 8 ? 1 : 0;
    this.algIndex = result.algorithm === 'SHA256' ? 1 : 0;
    this.periodIndex = result.period === 60 ? 1 : 0;
    this.counterInput = `${result.counter}`;
    this.mode = 0;
    this.toast('已解析链接，请核对后保存', 2000);
  }

  private save(): void {
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
      this.store.addAccount(result.name, result.issuer, result.secret, result.type,
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
    this.store.addAccount(name, issuer, secret, this.typeIndex === 1 ? OtpType.HOTP : OtpType.TOTP,
      this.previewDigits(), this.previewAlgorithm(), this.previewPeriod(), isNaN(counter) ? 0 : counter);
    this.toast('账户已添加', 1500);
    this.getUIContext().getRouter().back();
  }
}
