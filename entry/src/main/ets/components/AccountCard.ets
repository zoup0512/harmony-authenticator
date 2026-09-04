import { OtpType, AccountInfo } from '../model/Account';
import { Palette, Theme } from '../common/Theme';
import { CountdownRing } from './CountdownRing';
import { promptAction } from '@kit.ArkUI';

/**
 * 账户卡片：头像 + 名称 + 大号验证码 + 倒计时环（TOTP）/ 下一个码按钮（HOTP）。
 * 点击卡片复制验证码；长按弹出操作菜单。
 */
@Component
export struct AccountCard {
  @Prop account: AccountInfo;
  @Prop code: string;
  @Prop remainMs: number = 30000;
  @Prop copiedTick: number = 0;
  @StorageProp(Theme.KEY_DARK_MODE) private isDark: boolean = false;
  onCopy: (account: AccountInfo, code: string) => void = () => {};
  onNextCode: (account: AccountInfo) => void = () => {};
  onRename: (account: AccountInfo) => void = () => {};
  onDelete: (account: AccountInfo) => void = () => {};
  onMoveUp: (account: AccountInfo) => void = () => {};
  onMoveDown: (account: AccountInfo) => void = () => {};

  build() {
    Row({ space: 12 }) {
      this.Avatar()
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          if (this.displayIssuer().length > 0) {
            Text(this.displayIssuer())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        Text(this.account.name)
          .fontSize(12)
          .fontColor(this.pal().onSurfaceVariant)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ right: 4 })

      Column({ space: 4 }) {
        Text(this.formattedCode())
          .fontSize(this.account.digits > 6 ? 24 : 28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isCopied() ? this.pal().primary : this.pal().onSurface)
          .letterSpacing(this.account.digits > 6 ? 1 : 2)
          .fontFamily('monospace')
          .maxLines(1)
        if (this.account.type === OtpType.HOTP) {
          Text(`计数器 ${this.account.counter}`)
            .fontSize(10)
            .fontColor(this.pal().onSurfaceVariant)
        }
      }
      .alignItems(HorizontalAlign.End)

      if (this.account.type === OtpType.TOTP) {
        CountdownRing({
          remainMs: this.remainMs,
          periodMs: this.account.period * 1000,
          color: this.pal().primary,
          warnColor: this.pal().error,
          trackColor: this.pal().surfaceContainerHighest,
          ringSize: 30
        })
      } else {
        Button() {
          Image($r('sys.media.ohos_ic_public_play_next'))
            .width(20)
            .height(20)
            .fillColor(this.pal().primary)
        }
        .buttonStyle(ButtonStyleMode.NORMAL)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.pal().primaryContainer)
        .onClick((event: ClickEvent) => {
          this.onNextCode(this.account);
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 14, top: 14, bottom: 14 })
    .borderRadius(16)
    .backgroundColor(this.pal().surfaceContainerHigh)
    .onClick(() => {
      if (this.code.length > 0) {
        this.onCopy(this.account, this.code);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 450 })
        .onAction((event: GestureEvent) => {
          this.openMenu();
        })
    )
  }

  @Builder Avatar() {
    Text(this.avatarLetter())
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .width(44)
      .height(44)
      .borderRadius(22)
      .textAlign(TextAlign.Center)
      .backgroundColor(Theme.avatarColor(this.account.issuer + '|' + this.account.name, this.isDark))
  }

  private pal(): Palette {
    return Theme.palette(this.isDark);
  }

  private displayIssuer(): string {
    return this.account.issuer.length > 0 ? this.account.issuer : this.account.name;
  }

  private avatarLetter(): string {
    const src = this.account.issuer.length > 0 ? this.account.issuer : this.account.name;
    const trimmed = src.trim();
    return trimmed.length > 0 ? trimmed.charAt(0).toUpperCase() : '?';
  }

  /** 6 位码显示为 "123 456"，8 位码 "1234 5678" */
  private formattedCode(): string {
    const c = this.code.length > 0 ? this.code : '------';
    const half = Math.floor(c.length / 2);
    return `${c.substring(0, half)} ${c.substring(half)}`;
  }

  /** 刚复制过的卡片高亮 1.5 秒 */
  private isCopied(): boolean {
    return this.copiedTick > 0;
  }

  private openMenu(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: this.displayIssuer(),
      buttons: [
        { text: '复制验证码', color: this.pal().primary },
        { text: '上移', color: this.pal().onSurface },
        { text: '下移', color: this.pal().onSurface },
        { text: '重命名', color: this.pal().onSurface },
        { text: '删除', color: this.pal().error }
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse) => {
      if (res.index === 0) {
        this.onCopy(this.account, this.code);
      } else if (res.index === 1) {
        this.onMoveUp(this.account);
      } else if (res.index === 2) {
        this.onMoveDown(this.account);
      } else if (res.index === 3) {
        this.onRename(this.account);
      } else if (res.index === 4) {
        this.onDelete(this.account);
      }
    }).catch(() => {
      // 用户取消或弹窗失败时静默
    });
  }
}
