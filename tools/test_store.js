// Node 22.6+ (native TypeScript stripping): node tools/test_store.js
// Executes transformed production ArkTS, including cloneAccount and OTP validation.
const fs = require('fs');
const path = require('path');
const os = require('os');
const assert = require('assert/strict');
const { pathToFileURL } = require('url');
const root = path.join(__dirname, '..', 'entry/src/main/ets');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'store-test-'));

function prepare(file, prefix = '') {
  let source = fs.readFileSync(path.join(root, file), 'utf8');
  source = source.replace(/^import .* from '@kit\.[^']+';$/gm, '');
  source = source.replace(/from '(?:\.\/|\.\.\/\w+\/)(\w+)'/g, "from './$1.ts'");
  source = source.replace(/export enum OtpType \{[\s\S]*?\}/,
    'export const OtpType = { TOTP: 0, HOTP: 1 };');
  source = source.replace(/export enum HashAlg \{[\s\S]*?\}/,
    "export const HashAlg = { SHA1: 'SHA1', SHA256: 'SHA256' };");
  // Model interfaces are type-only imports in ArkTS; Node requires explicit type imports.
  source = source.replace(/import \{ AccountInfo, /g, 'import { ');
  const out = path.join(tmp, path.basename(file).replace('.ets', '.ts'));
  fs.writeFileSync(out, prefix + source);
  return pathToFileURL(out).href;
}

function preferencesMock(initial = {}) {
  return {
    cache: { ...initial }, disk: { ...initial }, puts: 0, flushes: 0, failPut: false,
    onFlush: async () => {},
    getSync(key, fallback) { return this.cache[key] === undefined ? fallback : this.cache[key]; },
    putSync(key, value) {
      this.puts++;
      this.cache[key] = value;
      if (this.failPut) throw new Error('put failed');
    },
    async flush() {
      this.flushes++;
      await this.onFlush();
      this.disk = { ...this.cache };
    }
  };
}
function gate() {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
}
const record = (overrides = {}) => ({ id: 2, name: 'n', secret: 'JBSWY3DPEHPK3PXP', type: 0, ...overrides });
const add = (store, name = 'x', type = 0, counter = 0) =>
  store.addAccount(name, '', 'JBSWY3DPEHPK3PXP', type, 6, 'SHA1', 30, counter);

async function main() {
  for (const file of ['otp/Digest.ets', 'otp/Base32.ets', 'model/Account.ets', 'otp/OtpEngine.ets']) prepare(file);
  const url = prepare('store/AccountStore.ets',
    'let selected; export function selectPreferences(value) { selected = value; }\n' +
    'const preferences = { getPreferences: async () => { if (selected instanceof Error) throw selected; return selected; } };\n' +
    'const hilog = { info() {}, error() {} };\n');
  let sequence = 0;
  async function fixture(initial = {}, init = true) {
    // Unique module instances isolate singleton, queue, mock, and failure latch per test.
    const module = await import(`${url}?case=${sequence++}`);
    const prefs = preferencesMock(initial);
    module.selectPreferences(prefs);
    const store = module.AccountStore.getInstance();
    if (init) await store.init({});
    return { store, prefs, select: module.selectPreferences };
  }
  let passed = 0;
  async function test(name, run) { await run(); passed++; console.log(`PASS ${name}`); }

  await test('legacy defaults, safe nextId repair, defensive clones', async () => {
    const { store, prefs } = await fixture({ accounts: JSON.stringify([record()]), nextId: 1 });
    assert.equal(store.isLoaded(), true);
    assert.equal(store.getLoadError(), '');
    const snapshot = store.getAccounts();
    assert.equal(snapshot[0].digits, 6); assert.equal(snapshot[0].issuer, '');
    snapshot[0].name = 'outside'; snapshot.length = 0;
    assert.equal(store.getAccounts()[0].name, 'n');
    const created = await add(store);
    assert.equal(created.id, 3);
    created.name = 'outside';
    assert.equal(store.getAccounts()[1].name, 'x');
    assert.equal(prefs.disk.nextId, 4);
  });

  await test('queue serializes all operations and publishes only after flush', async () => {
    const { store, prefs } = await fixture();
    const entered = gate(), release = gate();
    prefs.onFlush = async () => { entered.resolve(); await release.promise; };
    let notifications = 0;
    store.subscribe(() => { notifications++; assert.deepEqual(store.getAccounts(), JSON.parse(prefs.disk.accounts)); });
    const first = add(store, 'first', 1);
    const second = add(store, 'second');
    const rename = store.renameAccount(1, 'renamed', 'issuer');
    const count = store.incrementCounter(1);
    const move = store.moveAccount(1, 1);
    const remove = store.deleteAccount(2);
    await entered.promise;
    assert.deepEqual(store.getAccounts(), []); assert.equal(prefs.flushes, 1); assert.equal(notifications, 0);
    release.resolve();
    const results = await Promise.all([first, second, rename, count, move, remove]);
    assert.equal(results[0].id, 1); assert.equal(results[1].id, 2); assert.equal(results[2], true); assert.equal(results[3], 1);
    assert.equal(notifications, 6);
    assert.equal(store.getAccounts()[0].name, 'renamed'); assert.equal(store.getAccounts()[0].counter, 1);
    assert.equal(store.getAccounts()[0].sortOrder, 2);
    assert.deepEqual(await Promise.all([store.incrementCounter(1), store.incrementCounter(1)]), [2, 3]);
  });

  for (const failure of ['flush', 'put']) {
    await test(`${failure} failure rejects, preserves state, permanently blocks dirty cache reuse`, async () => {
      const { store, prefs } = await fixture();
      await add(store, 'original', 1);
      const before = store.getAccounts(); const disk = { ...prefs.disk };
      let notifications = 0; store.subscribe(() => notifications++);
      if (failure === 'flush') prefs.onFlush = async () => { throw new Error('flush failed'); };
      else prefs.failPut = true;
      const first = store.renameAccount(1, 'lost', '');
      const queued = add(store);
      await assert.rejects(first, /writes are disabled/); await assert.rejects(queued, /writes are disabled/);
      assert.deepEqual(store.getAccounts(), before); assert.deepEqual(prefs.disk, disk); assert.equal(notifications, 0);
      assert.notEqual(prefs.cache.accounts, prefs.disk.accounts);
      const puts = prefs.puts, flushes = prefs.flushes;
      await store.init({});
      for (const operation of [() => add(store), () => store.deleteAccount(1), () => store.renameAccount(1, 'x', ''),
        () => store.incrementCounter(1), () => store.moveAccount(1, 1)]) await assert.rejects(operation(), /writes are disabled/);
      assert.equal(prefs.puts, puts); assert.equal(prefs.flushes, flushes);
    });
  }

  await test('invalid saved data rejects the whole snapshot, never silently drops records', async () => {
    const invalidRecords = [null, [], 42, record({ id: 0 }), record({ id: 1.5 }), record({ id: Number.MAX_SAFE_INTEGER }),
      record({ name: null }), record({ issuer: 2 }), record({ secret: '!' }), record({ type: 4 }),
      record({ digits: 0 }), record({ digits: 1.5 }), record({ algorithm: 'MD5' }), record({ period: 3601 }),
      record({ counter: -1 }), record({ counter: Number.MAX_SAFE_INTEGER + 1 }),
      record({ createdAt: -1 }), record({ sortOrder: '1' })];
    const texts = ['{bad', 'null', '{}', '1', JSON.stringify([record(), record()]),
      ...invalidRecords.map(r => JSON.stringify([record({ id: 1 }), r]))];
    for (const accounts of texts) {
      const { store, prefs } = await fixture({ accounts });
      assert.equal(store.isLoaded(), false, accounts); assert.ok(store.getLoadError());
      assert.deepEqual(store.getAccounts(), []); await assert.rejects(add(store)); assert.equal(prefs.puts, 0);
    }
    for (const nextId of [0, -1, 1.5, '3', null, Infinity, NaN, Number.MAX_SAFE_INTEGER + 1]) {
      const { store } = await fixture({ nextId }); assert.equal(store.isLoaded(), false); await assert.rejects(add(store));
    }
  });

  await test('uninitialized/load failure blocks writes; explicit clean retry succeeds', async () => {
    const { store, prefs, select } = await fixture({}, false);
    await assert.rejects(add(store), /not loaded/);
    select(new Error('open failed')); await store.init({});
    assert.equal(store.isLoaded(), false); assert.match(store.getLoadError(), /Unable to load accounts/);
    assert.ok(!store.getLoadError().includes('open failed'));
    await assert.rejects(store.deleteAccount(1));
    select(prefs); await store.init({}); assert.equal(store.isLoaded(), true); assert.equal(store.getLoadError(), '');
    await add(store);
  });

  await test('invalid inputs do not poison queue; HOTP-only, no counter or ID overflow', async () => {
    const { store, prefs } = await fixture();
    await assert.rejects(store.addAccount('x', '', '!', 0, 6, 'SHA1', 30, 0));
    await assert.rejects(store.addAccount('x', '', 'JBSWY3DPEHPK3PXP', 0, 2.5, 'SHA1', 30, 0));
    await assert.rejects(store.deleteAccount(NaN)); await assert.rejects(store.moveAccount(1, 0.5));
    assert.equal(prefs.puts, 0);
    const totp = await add(store); assert.equal(totp.id, 1);
    await assert.rejects(store.incrementCounter(totp.id), /Only HOTP/);
    const hotp = await add(store, 'max', 1, Number.MAX_SAFE_INTEGER);
    await assert.rejects(store.incrementCounter(hotp.id), /remaining capacity/);
    assert.equal(await store.incrementCounter(99), -1); assert.equal(await store.renameAccount(99, 'x', ''), false);
    const last = await fixture({ nextId: Number.MAX_SAFE_INTEGER - 1 });
    assert.equal((await add(last.store)).id, Number.MAX_SAFE_INTEGER - 1);
    await assert.rejects(add(last.store), /exhausted/); assert.equal(last.prefs.disk.nextId, Number.MAX_SAFE_INTEGER);
  });
  console.log(`${passed} store test groups passed`);
}
main().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => fs.rmSync(tmp, { recursive: true, force: true }));
