import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountInfo, OtpType, cloneAccount } from '../model/Account';
import { OtpEngine } from '../otp/OtpEngine';

const TAG: string = 'Authenticator/Store';
const STORE_NAME: string = 'authenticator_accounts';
const KEY_ACCOUNTS: string = 'accounts';
const KEY_NEXT_ID: string = 'nextId';

/** All mutations (including loading) share one queue; only durable snapshots are published. */
export class AccountStore {
  private static instance: AccountStore | null = null;
  private prefs: preferences.Preferences | null = null;
  private accounts: AccountInfo[] = [];
  private nextId: number = 1;
  private loaded: boolean = false;
  private loadError: string = '';
  // A failed put/flush may leave dirty data in the Preferences cache. Never reuse it.
  private writeError: string = '';
  private queue: Promise<void> = Promise.resolve();
  private listeners: Array<() => void> = [];

  static getInstance(): AccountStore {
    if (AccountStore.instance === null) {
      AccountStore.instance = new AccountStore();
    }
    return AccountStore.instance;
  }

  private constructor() {
  }

  init(context: common.Context): Promise<void> {
    return this.enqueue<void>(async (): Promise<void> => {
      if (this.loaded || this.writeError !== '') {
        return;
      }
      try {
        const prefs = await preferences.getPreferences(context, STORE_NAME);
        const text = prefs.getSync(KEY_ACCOUNTS, '[]') as string;
        if (typeof text !== 'string') {
          throw new Error('Saved accounts must be JSON text');
        }
        const accounts = this.decode(text);
        const savedNextId = prefs.getSync(KEY_NEXT_ID, 1) as number;
        if (!Number.isSafeInteger(savedNextId) || savedNextId < 1) {
          throw new Error('Invalid saved nextId');
        }
        let nextId = savedNextId;
        for (const account of accounts) {
          if (account.id >= Number.MAX_SAFE_INTEGER) {
            throw new Error('Account ID space exhausted');
          }
          nextId = Math.max(nextId, account.id + 1);
        }
        this.prefs = prefs;
        this.accounts = accounts;
        this.nextId = nextId;
        this.loaded = true;
        this.loadError = '';
      } catch (e) {
        this.prefs = null;
        this.loadError = 'Unable to load accounts; existing data has not been modified';
        hilog.error(0, TAG, this.loadError);
      }
      this.notify();
    });
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  getLoadError(): string {
    return this.loadError;
  }

  getAccounts(): AccountInfo[] {
    return this.accounts.map((a: AccountInfo): AccountInfo => cloneAccount(a));
  }

  addAccount(name: string, issuer: string, secret: string, type: OtpType,
    digits: number, algorithm: string, period: number, counter: number): Promise<AccountInfo> {
    return this.enqueue<AccountInfo>(async (): Promise<AccountInfo> => {
      this.requireWritable();
      if (this.nextId >= Number.MAX_SAFE_INTEGER) {
        throw new Error('Account ID space exhausted');
      }
      let maxSort = 0;
      for (const account of this.accounts) {
        maxSort = Math.max(maxSort, account.sortOrder);
      }
      const account: AccountInfo = {
        id: this.nextId, name: name, issuer: issuer, secret: secret, type: type,
        counter: counter, digits: digits, algorithm: algorithm, period: period,
        createdAt: Date.now(), sortOrder: maxSort + 1
      };
      this.validateAccount(account);
      await this.persist(this.accounts.concat([account]), this.nextId + 1);
      return cloneAccount(account);
    });
  }

  deleteAccount(id: number): Promise<void> {
    return this.enqueue<void>(async (): Promise<void> => {
      this.requireWritable();
      this.validateId(id);
      const next = this.accounts.filter((a: AccountInfo): boolean => a.id !== id);
      if (next.length !== this.accounts.length) {
        await this.persist(next, this.nextId);
      }
    });
  }

  renameAccount(id: number, newName: string, newIssuer: string): Promise<boolean> {
    return this.enqueue<boolean>(async (): Promise<boolean> => {
      this.requireWritable();
      this.validateId(id);
      if (typeof newName !== 'string' || typeof newIssuer !== 'string') {
        throw new Error('Invalid account name or issuer');
      }
      const next = this.getAccounts();
      const account = next.find((a: AccountInfo): boolean => a.id === id);
      if (account === undefined) {
        return false;
      }
      account.name = newName;
      account.issuer = newIssuer;
      this.validateAccount(account);
      await this.persist(next, this.nextId);
      return true;
    });
  }

  incrementCounter(id: number): Promise<number> {
    return this.enqueue<number>(async (): Promise<number> => {
      this.requireWritable();
      this.validateId(id);
      const next = this.getAccounts();
      const account = next.find((a: AccountInfo): boolean => a.id === id);
      if (account === undefined) {
        return -1;
      }
      if (account.type !== OtpType.HOTP || account.counter >= Number.MAX_SAFE_INTEGER) {
        throw new Error('Only HOTP counters with remaining capacity can be incremented');
      }
      account.counter++;
      this.validateAccount(account);
      await this.persist(next, this.nextId);
      return account.counter;
    });
  }

  moveAccount(id: number, offset: number): Promise<void> {
    return this.enqueue<void>(async (): Promise<void> => {
      this.requireWritable();
      this.validateId(id);
      if (!Number.isSafeInteger(offset)) {
        throw new Error('Invalid move offset');
      }
      const next = this.getAccounts().sort((x: AccountInfo, y: AccountInfo): number => x.sortOrder - y.sortOrder);
      const index = next.findIndex((a: AccountInfo): boolean => a.id === id);
      const target = index + offset;
      if (index < 0 || target < 0 || target >= next.length || offset === 0) {
        return;
      }
      const temp = next[index];
      next[index] = next[target];
      next[target] = temp;
      for (let i = 0; i < next.length; i++) {
        next[i].sortOrder = i + 1;
      }
      await this.persist(next, this.nextId);
    });
  }

  subscribe(listener: () => void): () => void {
    this.listeners = this.listeners.concat([listener]);
    return () => {
      this.listeners = this.listeners.filter((l: () => void): boolean => l !== listener);
    };
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.queue.then(operation);
    // A rejected operation must not poison the scheduling queue.
    this.queue = result.then((): void => {}, (): void => {});
    return result;
  }

  private requireWritable(): void {
    if (this.writeError !== '') {
      throw new Error(this.writeError);
    }
    if (!this.loaded || this.prefs === null) {
      throw new Error(this.loadError || 'Account store is not loaded');
    }
  }

  private async persist(accounts: AccountInfo[], nextId: number): Promise<void> {
    this.requireWritable();
    const prefs = this.prefs;
    if (prefs === null) {
      throw new Error('Account store is not loaded');
    }
    const text = JSON.stringify(accounts);
    try {
      prefs.putSync(KEY_ACCOUNTS, text);
      prefs.putSync(KEY_NEXT_ID, nextId);
      await prefs.flush();
    } catch (e) {
      this.writeError = 'Saving accounts failed; writes are disabled until the app restarts';
      this.prefs = null;
      hilog.error(0, TAG, this.writeError);
      throw new Error(`${this.writeError}: ${(e as Error).message}`);
    }
    this.accounts = accounts;
    this.nextId = nextId;
    this.notify();
  }

  private notify(): void {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch (e) {
        hilog.error(0, TAG, `listener failed: ${JSON.stringify(e)}`);
      }
    }
  }

  private validateId(id: number): void {
    if (!Number.isSafeInteger(id) || id < 1) {
      throw new Error('Invalid account ID');
    }
  }

  private validateAccount(account: AccountInfo): void {
    this.validateId(account.id);
    if (typeof account.name !== 'string' || typeof account.issuer !== 'string' ||
      !Number.isSafeInteger(account.createdAt) || account.createdAt < 0 ||
      !Number.isSafeInteger(account.sortOrder) || account.sortOrder < 0 ||
      !OtpEngine.isValidParameters(account)) {
      throw new Error(`Invalid account fields for ID ${account.id}`);
    }
  }

  private decode(text: string): AccountInfo[] {
    const raw = JSON.parse(text) as AccountInfo[];
    if (!Array.isArray(raw)) {
      throw new Error('Saved accounts must be an array');
    }
    const result: AccountInfo[] = [];
    const ids: Set<number> = new Set<number>();
    for (const record of raw) {
      if (record === null || typeof record !== 'object' || Array.isArray(record)) {
        throw new Error('Invalid saved account record');
      }
      const account: AccountInfo = {
        id: record.id,
        name: record.name,
        issuer: record.issuer !== undefined ? record.issuer : '',
        secret: record.secret,
        type: record.type !== undefined ? record.type : OtpType.TOTP,
        counter: record.counter !== undefined ? record.counter : 0,
        digits: record.digits !== undefined ? record.digits : 6,
        algorithm: record.algorithm !== undefined ? record.algorithm : 'SHA1',
        period: record.period !== undefined ? record.period : 30,
        createdAt: record.createdAt !== undefined ? record.createdAt : 0,
        sortOrder: record.sortOrder !== undefined ? record.sortOrder : 0
      };
      this.validateAccount(account);
      if (ids.has(account.id)) {
        throw new Error(`Duplicate account ID ${account.id}`);
      }
      ids.add(account.id);
      result.push(account);
    }
    return result.sort((x: AccountInfo, y: AccountInfo): number => x.sortOrder - y.sortOrder);
  }
}
