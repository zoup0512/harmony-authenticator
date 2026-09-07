import { AccountStore } from '../store/AccountStore';
import { AccountInfo, OtpType } from '../model/Account';
import { OtpEngine } from '../otp/OtpEngine';
import { Theme, Palette } from '../common/Theme';
import { ClipboardUtil } from '../common/ClipboardUtil';
import { AccountCard, CardVm } from '../components/AccountCard';
import { EmptyView } from '../components/EmptyView';

/** 每个账户仅保留当前状态的验证码，不依赖防御性副本的对象身份。 */
interface CodeCacheEntry {
  secret: string;
  algorithm: string;
  digits: number;
  type: OtpType;
  period: number;
  state: number;
  code: string;
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
  @State loadFailed: boolean = false;
  @State now: number = Date.now();
  private store: AccountStore = AccountStore.getInstance();
  private accounts: AccountInfo[] = [];
  private codeCache: Map<number, CodeCacheEntry> = new Map<number, CodeCacheEntry>();
  private timerId: number = -1;
  private copiedTimeoutToken: number = 0;
  private copiedTimerId: number = -1;
  private unsubscribe: (() => void) | null = null;
  private renameTarget: AccountInfo | undefined = undefined;
  private renameDialog: CustomDialogController = new CustomDialogController({
    builder: RenameDialog({
      onConfirm: (issuer: string, name: string) => {
        if (this.renameTarget !== undefined) {
          this.renameAccount(this.renameTarget.id, name, issuer);
        }
      }
    }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    if (this.unsubscribe === null) {
      this.unsubscribe = this.store.subscribe(() => {
        this.refreshAccounts();
      });
    }
    this.refreshAccounts();
  }

  aboutToDisappear(): void {
    this.stopTimer();
    this.clearCopied();
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    this.codeCache.clear();
  }

  onPageShow(): void {
    this.refreshAccounts();
    this.startTimer();
  }

  onPageHide(): void {
    this.stopTimer();
    this.clearCopied();
  }

  private startTimer(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      this.now = Date.now();
      this.rebuild();
    }, 250);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private clearCopied(): void {
    if (this.copiedTimerId >= 0) {
      clearTimeout(this.copiedTimerId);
      this.copiedTimerId = -1;
    }
    this.copiedTimeoutToken++;
    this.copiedId = -1;
  }

  build() {
    Column() {
      this.TitleBar()
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.loadFailed) {
          EmptyView({
            title: '账户加载失败',
            subtitle: '无法读取账户，请重启应用后重试'
          })
        } else if (this.vms.length === 0) {
          EmptyView({
            title: this.ready ? '暂无账户' : '正在加载…',
            subtitle: this.ready ? '点击右下角按钮添加第一个验证账户' : ''
          })
        } else {
          List({ space: 10 }) {
            ForEach(this.vms, (vm: CardVm) => {
              ListItem() {
                AccountCard({
                  vm: vm,
                  copiedTick: this.copiedId === vm.account.id ? 1 : 0,
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
                    this.moveAccount(account.id, -1);
                  },
                  onMoveDown: (account: AccountInfo) => {
                    this.moveAccount(account.id, 1);
                  }
                })
              }
            }, (vm: CardVm) => `acct-${vm.account.id}`)
          }
          .width('100%')
          .height('100%')
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
      Image($r('sys.media.ohos_ic_public_add'))
        .width(24)
        .height(24)
        .fillColor(this.pal().onPrimary)
    }
    .accessibilityText('添加账户')
    .width(56)
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

  /** 仅在进入页面或存储通知时获取、排序账户副本并使缓存失效。 */
  private refreshAccounts(): void {
    this.accounts = this.store.getAccounts()
      .sort((a: AccountInfo, b: AccountInfo) => a.sortOrder - b.sortOrder);
    this.codeCache.clear();
    this.ready = this.store.isLoaded();
    this.loadFailed = this.store.getLoadError().length > 0;
    this.now = Date.now();
    this.rebuild();
  }

  private cachedCode(account: AccountInfo, now: number): string {
    const state = account.type === OtpType.TOTP ?
      OtpEngine.timeSlice(now, account.period) : account.counter;
    const cached = this.codeCache.get(account.id);
    if (cached !== undefined && cached.secret === account.secret &&
      cached.algorithm === account.algorithm && cached.digits === account.digits &&
      cached.type === account.type && cached.period === account.period && cached.state === state) {
      return cached.code;
    }
    const code = account.type === OtpType.TOTP ?
      OtpEngine.totp(account, now) : OtpEngine.hotp(account);
    this.codeCache.set(account.id, {
      secret: account.secret,
      algorithm: account.algorithm,
      digits: account.digits,
      type: account.type,
      period: account.period,
      state: state,
      code: code
    });
    return code;
  }

  /** 250ms 更新倒计时；仅缓存失效或 OTP 状态变化时解码和计算 HMAC。 */
  private rebuild(): void {
    const now = this.now;
    const existing: Map<number, CardVm> = new Map<number, CardVm>();
    for (const vm of this.vms) {
      existing.set(vm.account.id, vm);
    }
    const next: CardVm[] = [];
    for (const a of this.accounts) {
      const code = this.cachedCode(a, now);
      const remainMs = a.type === OtpType.TOTP ? OtpEngine.remainingMillis(now, a.period) : 0;
      let vm = existing.get(a.id);
      if (vm === undefined) {
        vm = new CardVm(a, code, remainMs);
      } else {
        // ForEach 的稳定 key 不会重新执行已有条目的 builder，必须更新原对象。
        vm.account = a;
        vm.code = code;
        vm.remainMs = remainMs;
      }
      next.push(vm);
    }
    this.vms = next;
  }

  private onCopyCode(account: AccountInfo, code: string): void {
    ClipboardUtil.copyText(this.getUIContext(), code, '验证码已复制');
    this.clearCopied();
    this.copiedId = account.id;
    const token = ++this.copiedTimeoutToken;
    this.copiedTimerId = setTimeout(() => {
      this.copiedTimerId = -1;
      if (this.copiedTimeoutToken === token && this.copiedId === account.id) {
        this.copiedId = -1;
      }
    }, 1500);
  }

  private showFailure(): void {
    this.getUIContext().getPromptAction().showToast({ message: '操作失败，请稍后重试' });
  }

  private onNextCode(account: AccountInfo): void {
    this.store.incrementCounter(account.id).then((counter: number) => {
      if (counter < 0) {
        this.showFailure();
      }
    }).catch(() => this.showFailure());
  }

  private moveAccount(id: number, offset: number): void {
    this.store.moveAccount(id, offset).catch(() => this.showFailure());
  }

  private renameAccount(id: number, name: string, issuer: string): void {
    this.store.renameAccount(id, name, issuer).then((renamed: boolean) => {
      if (!renamed) {
        this.showFailure();
      }
    }).catch(() => this.showFailure());
  }

  private onRename(account: AccountInfo): void {
    this.renameTarget = account;
    this.renameDialog = new CustomDialogController({
      builder: RenameDialog({
        account: account,
        onConfirm: (issuer: string, name: string) => {
          this.renameAccount(account.id, name, issuer);
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
          this.store.deleteAccount(account.id).catch(() => this.showFailure());
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
