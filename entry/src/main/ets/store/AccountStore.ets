import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountInfo, OtpType } from '../model/Account';

const TAG: string = 'Authenticator/Store';
const STORE_NAME: string = 'authenticator_accounts';
const KEY_ACCOUNTS: string = 'accounts';
const KEY_NEXT_ID: string = 'nextId';

/** JSON 反序列化时的中间形状 */
interface AccountSeri {
  id: number;
  name: string;
  issuer: string;
  secret: string;
  type: number;
  counter: number;
  digits: number;
  algorithm: string;
  period: number;
  createdAt: number;
  sortOrder: number;
}

/**
 * 账户存储：基于 preferences 的单例仓库。
 * 参照 Android 版 AccountDb 提供增删改查、重命名与 HOTP 计数器递增。
 */
export class AccountStore {
  private static instance: AccountStore | null = null;

  private prefs: preferences.Preferences | null = null;
  private accounts: AccountInfo[] = [];
  private nextId: number = 1;
  private loaded: boolean = false;
  private listeners: Array<() => void> = [];

  static getInstance(): AccountStore {
    if (AccountStore.instance === null) {
      AccountStore.instance = new AccountStore();
    }
    return AccountStore.instance;
  }

  private constructor() {
  }

  /** 在 EntryAbility.onCreate 中调用，加载本地数据 */
  async init(context: common.Context): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME);
      const text = this.prefs.getSync(KEY_ACCOUNTS, '[]') as string;
      this.accounts = this.decode(text);
      const nextIdValue = this.prefs.getSync(KEY_NEXT_ID, 1) as number;
      this.nextId = Math.max(1, Number(nextIdValue));
      this.loaded = true;
      hilog.info(0, TAG, `loaded ${this.accounts.length} accounts`);
    } catch (e) {
      hilog.error(0, TAG, `init failed: ${JSON.stringify(e)}`);
      this.accounts = [];
      this.loaded = true;
    }
    this.notify();
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  getAccounts(): AccountInfo[] {
    return this.accounts;
  }

  /** 新增账户，返回完整记录 */
  addAccount(name: string, issuer: string, secret: string, type: OtpType,
    digits: number, algorithm: string, period: number, counter: number): AccountInfo {
    const now = Date.now();
    let maxSort = 0;
    for (const a of this.accounts) {
      if (a.sortOrder > maxSort) {
        maxSort = a.sortOrder;
      }
    }
    const account: AccountInfo = {
      id: this.nextId++,
      name: name,
      issuer: issuer,
      secret: secret,
      type: type,
      counter: counter,
      digits: digits,
      algorithm: algorithm,
      period: period,
      createdAt: now,
      sortOrder: maxSort + 1
    };
    this.accounts = this.accounts.concat([account]);
    this.persist();
    return account;
  }

  deleteAccount(id: number): void {
    this.accounts = this.accounts.filter((a: AccountInfo) => a.id !== id);
    this.persist();
  }

  renameAccount(id: number, newName: string, newIssuer: string): boolean {
    let hit = false;
    const next = this.accounts.map((a: AccountInfo): AccountInfo => {
      if (a.id === id) {
        hit = true;
        const copy: AccountInfo = {
          id: a.id,
          name: newName,
          issuer: newIssuer,
          secret: a.secret,
          type: a.type,
          counter: a.counter,
          digits: a.digits,
          algorithm: a.algorithm,
          period: a.period,
          createdAt: a.createdAt,
          sortOrder: a.sortOrder
        };
        return copy;
      }
      return a;
    });
    if (hit) {
      this.accounts = next;
      this.persist();
    }
    return hit;
  }

  /** HOTP：递增计数器并返回新计数器值 */
  incrementCounter(id: number): number {
    let newCounter = -1;
    const next = this.accounts.map((a: AccountInfo): AccountInfo => {
      if (a.id === id) {
        newCounter = a.counter + 1;
        const copy: AccountInfo = {
          id: a.id,
          name: a.name,
          issuer: a.issuer,
          secret: a.secret,
          type: a.type,
          counter: newCounter,
          digits: a.digits,
          algorithm: a.algorithm,
          period: a.period,
          createdAt: a.createdAt,
          sortOrder: a.sortOrder
        };
        return copy;
      }
      return a;
    });
    if (newCounter >= 0) {
      this.accounts = next;
      this.persist();
    }
    return newCounter;
  }

  /** 上移/下移排序 */
  moveAccount(id: number, offset: number): void {
    const sorted = this.accounts.slice().sort((x: AccountInfo, y: AccountInfo) => x.sortOrder - y.sortOrder);
    const idx = sorted.findIndex((a: AccountInfo) => a.id === id);
    const target = idx + offset;
    if (idx < 0 || target < 0 || target >= sorted.length) {
      return;
    }
    const tmp = sorted[idx];
    sorted[idx] = sorted[target];
    sorted[target] = tmp;
    this.accounts = sorted.map((a: AccountInfo, i: number): AccountInfo => {
      const copy: AccountInfo = {
        id: a.id,
        name: a.name,
        issuer: a.issuer,
        secret: a.secret,
        type: a.type,
        counter: a.counter,
        digits: a.digits,
        algorithm: a.algorithm,
        period: a.period,
        createdAt: a.createdAt,
        sortOrder: i + 1
      };
      return copy;
    });
    this.persist();
  }

  /** 订阅变更，返回取消订阅函数 */
  subscribe(listener: () => void): () => void {
    this.listeners = this.listeners.concat([listener]);
    return () => {
      this.listeners = this.listeners.filter((l: () => void) => l !== listener);
    };
  }

  private persist(): void {
    if (this.prefs !== null) {
      try {
        this.prefs.putSync(KEY_ACCOUNTS, this.encode(this.accounts));
        this.prefs.putSync(KEY_NEXT_ID, this.nextId);
        this.prefs.flush();
      } catch (e) {
        hilog.error(0, TAG, `persist failed: ${JSON.stringify(e)}`);
      }
    }
    this.notify();
  }

  private notify(): void {
    for (const l of this.listeners) {
      try {
        l();
      } catch (e) {
        hilog.error(0, TAG, `listener failed: ${JSON.stringify(e)}`);
      }
    }
  }

  private encode(accounts: AccountInfo[]): string {
    const arr: AccountSeri[] = accounts.map((a: AccountInfo): AccountSeri => {
      const s: AccountSeri = {
        id: a.id,
        name: a.name,
        issuer: a.issuer,
        secret: a.secret,
        type: a.type,
        counter: a.counter,
        digits: a.digits,
        algorithm: a.algorithm,
        period: a.period,
        createdAt: a.createdAt,
        sortOrder: a.sortOrder
      };
      return s;
    });
    return JSON.stringify(arr);
  }

  private decode(text: string): AccountInfo[] {
    let raw: AccountSeri[] = [];
    try {
      raw = JSON.parse(text) as AccountSeri[];
    } catch (e) {
      hilog.error(0, TAG, 'decode failed, start with empty store');
      return [];
    }
    const result: AccountInfo[] = [];
    for (const r of raw) {
      const a: AccountInfo = {
        id: r.id,
        name: r.name,
        issuer: r.issuer !== undefined ? r.issuer : '',
        secret: r.secret,
        type: r.type === 1 ? OtpType.HOTP : OtpType.TOTP,
        counter: r.counter !== undefined ? r.counter : 0,
        digits: r.digits !== undefined ? r.digits : 6,
        algorithm: r.algorithm !== undefined ? r.algorithm : 'SHA1',
        period: r.period !== undefined ? r.period : 30,
        createdAt: r.createdAt !== undefined ? r.createdAt : 0,
        sortOrder: r.sortOrder !== undefined ? r.sortOrder : 0
      };
      result.push(a);
    }
    // 按 sortOrder 排序展示
    result.sort((x: AccountInfo, y: AccountInfo) => x.sortOrder - y.sortOrder);
    return result;
  }
}
