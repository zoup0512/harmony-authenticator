// Node 22.6+: execute production methods with a fake wall clock/store/timers.
// This models keyed ForEach retention, NOT an ArkUI runtime or device test.
const fs = require('fs');
const path = require('path');
const os = require('os');
const assert = require('assert/strict');
const { stripTypeScriptTypes } = require('module');
const { pathToFileURL } = require('url');
const root = path.join(__dirname, '../entry/src/main/ets');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'refresh-test-'));
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

function block(source, start) {
  const open = source.indexOf('{', start);
  let depth = 1, end = open + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  assert.equal(depth, 0);
  return source.slice(start, end);
}
function method(source, name) {
  const match = new RegExp(`^  (?:private )?${name}\\([^\\n]*`, 'm').exec(source);
  assert.ok(match, `production method ${name} exists`);
  return block(source, match.index);
}
function prepare(file) {
  let source = read(file).replace(/^import \{([^}]*)\} from '(\.[^']+)';$/gm,
    (_, names, target) => `import { ${names.split(',').map(n => n.trim())
      .map(n => n === 'AccountInfo' ? `type ${n}` : n).join(', ')} } from '${target}.ts';`);
  source = source.replace(/export enum (\w+) \{([\s\S]*?)\}/g,
    (_, name, members) => `export const ${name} = {${members.replace(/=/g, ':')}};`);
  const out = path.join(tmp, file.replace('.ets', '.ts'));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, source);
  return pathToFileURL(out).href;
}
async function main() {
  for (const file of ['otp/Digest.ets', 'otp/Base32.ets', 'model/Account.ets']) prepare(file);
  const { OtpEngine } = await import(prepare('otp/OtpEngine.ets'));
  const OtpType = { TOTP: 0, HOTP: 1 };
  const indexSource = read('pages/Index.ets');
  const index = indexSource.slice(indexSource.indexOf('struct Index {'));
  const card = read('components/AccountCard.ets');
  assert.match(card, /@Observed\s+export class CardVm/);
  assert.match(card, /@ObjectLink vm: CardVm/);
  assert.match(index, /AccountCard\(\{\s+vm: vm,/);
  assert.match(index, /`acct-\$\{vm.account.id\}`/);
  assert.match(card, /remainMs: this.vm.remainMs/);
  assert.match(card, /this.onCopy\(this.vm.account, this.vm.code\)/);
  assert.doesNotMatch(card.slice(card.indexOf('export struct AccountCard')), /this\.(?:account|code|remainMs)\b/);
  const vmClass = block(card, card.indexOf('export class CardVm')).replace('export ', '');
  const methods = ['aboutToAppear', 'aboutToDisappear', 'onPageShow', 'onPageHide',
    'startTimer', 'stopTimer', 'clearCopied', 'refreshAccounts', 'cachedCode', 'rebuild',
    'onCopyCode', 'onNextCode'].map(name => method(index, name)).join('\n');
  let now = 29750, nextTimer = 0, copied = '', increments = 0, reads = 0;
  const intervals = new Map(), timeouts = new Map(), listeners = new Set();
  const account = (id, type = 0, period = 30) => ({ id, type, period, counter: 0, digits: 6,
    algorithm: 'SHA1', secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
    name: 'fixture', issuer: 'RFC', sortOrder: id, createdAt: 0 });
  let accounts = [account(1), account(2, 0, 60), account(3, 1)];
  const notify = () => listeners.forEach(fn => fn());
  const store = {
    getAccounts() { reads++; return accounts.map(a => ({ ...a })); },
    isLoaded: () => true, getLoadError: () => '',
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    async incrementCounter(id) {
      const a = accounts.find(a => a.id === id);
      assert.equal(a.type, OtpType.HOTP); increments++; a.counter++; notify(); return a.counter;
    }
  };
  const source = `${vmClass}\nclass Page { ${methods} }\nclass Card { ${method(card, 'formattedCode')} }`;
  const { Page, Card } = new Function('OtpEngine', 'OtpType', 'Date', 'setInterval', 'clearInterval',
    'setTimeout', 'clearTimeout', 'ClipboardUtil', stripTypeScriptTypes(source) + '\nreturn { Page, Card };')(
    OtpEngine, OtpType, { now: () => now },
    (fn, ms) => { assert.equal(ms, 250); const id = nextTimer++; intervals.set(id, fn); return id; },
    id => intervals.delete(id),
    fn => { const id = nextTimer++; timeouts.set(id, fn); return id; }, id => timeouts.delete(id),
    { copyText(_, code) { copied = code; } });
  const page = Object.assign(new Page(), { store, accounts: [], vms: [], codeCache: new Map(),
    now, timerId: -1, copiedId: -1, copiedTimerId: -1, copiedTimeoutToken: 0, unsubscribe: null,
    getUIContext: () => ({}), showFailure() { throw new Error('unexpected operation failure'); } });
  // Retain the first card/VM for an ID, just as stable keyed ForEach does.
  const cards = new Map();
  const sync = () => {
    for (const id of cards.keys()) if (!page.vms.some(vm => vm.account.id === id)) cards.delete(id);
    for (const vm of page.vms) if (!cards.has(vm.account.id)) cards.set(vm.account.id, Object.assign(new Card(), { vm }));
  };
  const tick = time => { now = time; intervals.forEach(fn => fn()); sync(); };
  const verify = () => {
    sync();
    for (const a of accounts) {
      const c = cards.get(a.id);
      const expected = a.type === 0 ? OtpEngine.totp(a, now) : OtpEngine.hotp(a);
      assert.equal(c.formattedCode().replace(' ', ''), expected, 'retained card must display current code');
      assert.equal(c.vm.remainMs, a.type === 0 ? OtpEngine.remainingMillis(now, a.period) : 0);
      assert.equal(c.vm.account.counter, a.counter);
    }
  };
  page.aboutToAppear(); page.onPageShow(); page.onPageShow();
  assert.equal(listeners.size, 1); assert.equal(intervals.size, 1); verify();
  const first = cards.get(1), oldCode = first.vm.code, readCount = reads;
  for (const time of [29999, 30000, 30250, 59999, 60000, 90000, 120000]) { tick(time); verify(); }
  assert.equal(cards.get(1), first); assert.notEqual(first.vm.code, oldCode);
  assert.equal(reads, readCount); assert.equal(increments, 0);
  console.log('PASS retained cards refresh across 30/60-second boundaries; HOTP stays fixed');

  // Negative control: the pre-fix replacement-only rebuild leaves a retained card stale.
  const retained = first.vm;
  page.vms = page.vms.map(vm => ({ ...vm }));
  tick(150000);
  assert.throws(verify, /retained card must display current code/);
  assert.equal(first.vm, retained);
  cards.clear(); sync(); verify();
  console.log('PASS regression detects replacement-only CardVm snapshot bug');

  page.onCopyCode(cards.get(1).vm.account, cards.get(1).vm.code);
  assert.equal(copied, OtpEngine.totp(accounts[0], now));
  page.onPageHide(); assert.equal(intervals.size, 0); assert.equal(timeouts.size, 0);
  assert.equal(page.copiedId, -1);
  now = 360001; page.onPageShow(); verify(); assert.equal(intervals.size, 1);
  tick(30000); verify(); // wall clock adjustment backwards, not accumulated ticks
  tick(900001); verify(); // delayed timer skips many periods
  assert.equal(increments, 0);
  console.log('PASS hide/show resumes immediately; delayed ticks and clock rollback use wall time');

  await page.onNextCode(accounts[2]); verify(); assert.equal(increments, 1);
  tick(930000); verify(); assert.equal(accounts[2].counter, 1);
  accounts[0] = { ...accounts[0], name: 'renamed', digits: 8, algorithm: 'SHA256', period: 60 };
  accounts.reverse(); notify(); verify(); assert.equal(cards.get(1).vm.account.name, 'renamed');
  accounts = accounts.filter(a => a.id !== 2); notify(); verify(); assert.equal(cards.has(2), false);
  accounts.push(account(4)); notify(); verify();
  console.log('PASS manual HOTP increment, account parameter changes, reorder, delete and add');

  page.aboutToDisappear(); assert.equal(intervals.size, 0); assert.equal(listeners.size, 0);
  assert.equal(page.codeCache.size, 0); assert.equal(timeouts.size, 0);
  now = 1200000; page.aboutToAppear(); page.onPageShow(); verify();
  assert.equal(intervals.size, 1); assert.equal(listeners.size, 1);
  page.aboutToDisappear();
  console.log('PASS disposal/reappearance clears and restores timer and subscription');
}
main().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => fs.rmSync(tmp, { recursive: true, force: true }));
