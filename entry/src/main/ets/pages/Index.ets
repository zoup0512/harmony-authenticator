import { AccountStore } from '../store/AccountStore';
import { AccountInfo, OtpType } from '../model/Account';
import { OtpEngine } from '../otp/OtpEngine';
import { Theme, Palette } from '../common/Theme';
import { ClipboardUtil } from '../common/ClipboardUtil';
import { AccountCard } from '../components/AccountCard';
import { EmptyView } from '../components/EmptyView';

/** 列表条目的视图模型 */
interface CardVm {
  account: AccountInfo;
  code: string;
  remainMs: number;
}

/** 重命名对话框 */
@CustomDialog
struct RenameDialog {
  controller?: CustomDialogController;
  account: AccountInfo | undefined = undefined;
  onConfirm: (issuer: string, name: string) => void = () => {};
  @StorageProp(Theme.KEY_DARK_MODE) private isDark: boolean = false;
  @State issuerInput: string = '';
  @State nameInput: string = '';
  @State nameError: string = '';

  aboutToAppear(): void {
    if (this.account !== undefined) {
      this.issuerInput = this.account.issuer;
      this.nameInput = this.account.name;
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('重命名账户')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().onSurface)
        .width('100%')
      TextInput({ placeholder: '服务名称（可选）', text: this.issuerInput })
        .onChange((value: string) => {
          this.issuerInput = value;
        })
        .height(48)
        .borderRadius(12)
        .backgroundColor(this.pal().surfaceContainerHigh)
      TextInput({ placeholder: '账户名称', text: this.nameInput })
        .onChange((value: string) => {
          this.nameInput = value;
          this.nameError = '';
        })
        .height(48)
        .borderRadius(12)
        .backgroundColor(this.pal().surfaceContainerHigh)
      if (this.nameError.length > 0) {
        Text(this.nameError)
          .fontSize(12)
          .fontColor(this.pal().error)
          .width('100%')
      }
      Row({ space: 8 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.controller?.close();
          })
        Button('确定')
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.pal().primary)
          .onClick(() => {
            const name = this.nameInput.trim();
            if (name.length === 0) {
              this.nameError = '账户名称不能为空';
              return;
            }
            this.onConfirm(this.issuerInput.trim(), name);
            this.controller?.close();
          })
      }
      .width('100%')
    }
    .padding(24)
    .backgroundColor(this.pal().surfaceContainerHigh)
    .borderRadius(28)
  }

  private pal(): Palette {
    return Theme.palette(this.isDark);
  }
}

@Entry
@Component
struct Index {
  @StorageProp(Theme.KEY_DARK_MODE) private isDark: boolean = false;
  @State vms: CardVm[] = [];
  @State copiedId: number = -1;
  @State ready: boolean = false;
  private store: AccountStore = AccountStore.getInstance();
  private timerId: number = -1;
  private unsubscribe: (() => void) | null = null;
  private renameTarget: AccountInfo | undefined = undefined;
  private renameDialog: CustomDialogController = new CustomDialogController({
    builder: RenameDialog({
      onConfirm: (issuer: string, name: string) => {
        if (this.renameTarget !== undefined) {
          this.store.renameAccount(this.renameTarget.id, name, issuer);
        }
      }
    }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    this.ready = this.store.isLoaded();
    this.rebuild();
    this.unsubscribe = this.store.subscribe(() => {
      this.rebuild();
    });
    this.timerId = setInterval(() => {
      this.rebuild();
    }, 250);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  onPageShow(): void {
    this.rebuild();
  }

  build() {
    Column() {
      this.TitleBar()
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.vms.length === 0) {
          EmptyView({
            title: this.ready ? '暂无账户' : '正在加载…',
            subtitle: this.ready ? '点击右下角按钮添加第一个验证账户' : ''
          })
        } else {
          List({ space: 10 }) {
            ForEach(this.vms, (vm: CardVm) => {
              ListItem() {
                AccountCard({
                  account: vm.account,
                  code: vm.code,
                  remainMs: vm.remainMs,
                  copiedTick: this.copiedId === vm.account.id ? Date.now() : 0,
                  onCopy: (account: AccountInfo, code: string) => {
                    this.onCopyCode(account, code);
                  },
                  onNextCode: (account: AccountInfo) => {
                    this.onNextCode(account);
                  },
                  onRename: (account: AccountInfo) => {
                    this.onRename(account);
                  },
                  onDelete: (account: AccountInfo) => {
                    this.onDelete(account);
                  },
                  onMoveUp: (account: AccountInfo) => {
                    this.store.moveAccount(account.id, -1);
                  },
                  onMoveDown: (account: AccountInfo) => {
                    this.store.moveAccount(account.id, 1);
                  }
                })
              }
            }, (vm: CardVm) => `acct-${vm.account.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 6, bottom: 96 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        this.Fab()
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surface)
  }

  @Builder TitleBar() {
    Row() {
      Text('验证器')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().onSurface)
      Blank()
      Button() {
        Image($r('sys.media.ohos_ic_public_more'))
          .width(24)
          .height(24)
          .fillColor(this.pal().onSurfaceVariant)
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor('transparent')
      .onClick(() => {
        this.showAbout();
      })
    }
    .width('100%')
    .padding({ left: 20, right: 12, top: 14, bottom: 10 })
  }

  @Builder Fab() {
    Button() {
      Row({ space: 8 }) {
        Image($r('sys.media.ohos_ic_public_add'))
          .width(22)
          .height(22)
          .fillColor(this.pal().onPrimary)
        Text('添加账户')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().onPrimary)
      }
      .padding({ left: 18, right: 22 })
    }
    .height(56)
    .borderRadius(28)
    .backgroundColor(this.pal().primary)
    .shadow({
      radius: 12,
      color: this.isDark ? '#66000000' : '#330B57D0',
      offsetX: 0,
      offsetY: 6
    })
    .margin({ right: 20, bottom: 28 })
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/AddAccount' });
    })
  }

  private pal(): Palette {
    return Theme.palette(this.isDark);
  }

  /** 每 0.25s 重建视图模型：重算验证码与剩余时间（纯计算，开销可忽略） */
  private rebuild(): void {
    const now = Date.now();
    const accounts = this.store.getAccounts().slice()
      .sort((a: AccountInfo, b: AccountInfo) => a.sortOrder - b.sortOrder);
    const next: CardVm[] = [];
    for (const a of accounts) {
      const vm: CardVm = {
        account: a,
        code: a.type === OtpType.TOTP ? OtpEngine.totp(a, now) : OtpEngine.hotp(a),
        remainMs: a.type === OtpType.TOTP ? OtpEngine.remainingMillis(now, a.period) : 0
      };
      next.push(vm);
    }
    this.vms = next;
    this.ready = this.store.isLoaded();
  }

  private onCopyCode(account: AccountInfo, code: string): void {
    ClipboardUtil.copyText(this.getUIContext(), code, '验证码已复制');
    this.copiedId = account.id;
    setTimeout(() => {
      if (this.copiedId === account.id) {
        this.copiedId = -1;
      }
    }, 1500);
  }

  private onNextCode(account: AccountInfo): void {
    this.store.incrementCounter(account.id);
  }

  private onRename(account: AccountInfo): void {
    this.renameTarget = account;
    this.renameDialog = new CustomDialogController({
      builder: RenameDialog({
        account: account,
        onConfirm: (issuer: string, name: string) => {
          this.store.renameAccount(account.id, name, issuer);
        }
      }),
      autoCancel: true,
      customStyle: true
    });
    this.renameDialog.open();
  }

  private onDelete(account: AccountInfo): void {
    this.getUIContext().showAlertDialog({
      title: '删除账户',
      message: `确定删除「${account.issuer.length > 0 ? `${account.issuer}:` : ''}${account.name}」吗？删除后将无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.pal().error,
        action: () => {
          this.store.deleteAccount(account.id);
        }
      },
      cancel: () => {}
    });
  }

  private showAbout(): void {
    this.getUIContext().showAlertDialog({
      title: '关于验证器',
      message: '单机版动态口令验证器 v1.0.0\n\n完全离线运行，支持 TOTP（RFC 6238）与 HOTP（RFC 4226），数据仅保存在本机。\n算法实现参考 Google Authenticator 开源版。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      confirm: {
        value: '知道了',
        action: () => {}
      },
      cancel: () => {}
    });
  }
}
