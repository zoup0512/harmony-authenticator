// 用 RFC 4226/6238 官方测试向量验证 OTP 实现。
// 做法：把 ArkTS 源码做最小转换（保留相对 import、enum→const 对象、去掉 private/readonly 修饰符）
// 复制为 .ts，再以 Node 原生 type-stripping 导入执行，保证被测代码与工程内代码逐行一致。
const fs = require('fs');
const path = require('path');
const os = require('os');
const { pathToFileURL } = require('url');
const { createHmac, createHash } = require('crypto');

const root = path.join(__dirname, '..', 'entry/src/main/ets');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'otp-test-'));

function transform(src) {
  // Preserve actual model and OTP imports; interfaces have no runtime export.
  src = src.replace(/^import \{([^}]*)\} from '(\.[^']+)';$/gm,
    (m, names, file) => `import { ${names.split(',').map(n => n.trim())
      .map(n => n === 'AccountInfo' ? `type ${n}` : n).join(', ')} } from '${file}.ts';`);
  // Node type-stripping does not support enums; retain each source enum's values.
  src = src.replace(/export enum (\w+) \{([\s\S]*?)\}/g,
    (m, name, members) => `export const ${name} = {${members.replace(/=/g, ':')}};`);
  src = src.replace(/\bprivate\s+/g, '');
  src = src.replace(/\breadonly\s+/g, '');
  return src;
}

function prepare(file) {
  const src = transform(fs.readFileSync(path.join(root, file), 'utf8'));
  const out = path.join(tmp, file.replace('.ets', '.ts'));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, src);
  return out;
}

async function main() {
  const digestUrl = pathToFileURL(prepare('otp/Digest.ets')).href;
  const base32Url = pathToFileURL(prepare('otp/Base32.ets')).href;
  const engineUrl = pathToFileURL(prepare('otp/OtpEngine.ets')).href;
  const accountUrl = pathToFileURL(prepare('model/Account.ets')).href;
  const uriUrl = pathToFileURL(prepare('otp/OtpUri.ets')).href;
  const { OtpType, cloneAccount } = await import(accountUrl);
  const { OtpUri } = await import(uriUrl);
  const { Digest, Hmac, HashAlg } = await import(digestUrl);
  const { Base32String } = await import(base32Url);
  const { OtpEngine } = await import(engineUrl);
  const makeAccount = (type = OtpType.TOTP) => ({ id: 1, name: 'alice@example.com', issuer: 'Example', secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', type, counter: 0, digits: 6, algorithm: 'SHA1', period: 30, createdAt: 0, sortOrder: 0 });

  let failures = 0;
  const check = (name, ok, detail = '') => {
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : '  ' + detail}`);
    if (!ok) failures++;
  };
  const hex = (u8) => Buffer.from(u8).toString('hex');

  // ---- Base32 ----
  const secretBytes = Base32String.decode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
  check(`[Base32] decode RFC 密钥`, Buffer.from(secretBytes).toString() === '12345678901234567890');
  const roundTrip = Base32String.encode(Base32String.decode('jbsw y3dp-ehpk 3pxp=='));
  check(`[Base32] 容错解码(小写/空格/连字符/填充)`, roundTrip === 'JBSWY3DPEHPK3PXP', roundTrip);

  // ---- RFC 4226 附录 D：HOTP-SHA1 ----
  const hotpExpected = ['755224', '287082', '359152', '969429', '338314',
    '254676', '287922', '162583', '399871', '520489'];
  let allOk = true;
  for (let i = 0; i < 10; i++) {
    const code = OtpEngine.computeCode(secretBytes, HashAlg.SHA1, 6, i);
    if (code !== hotpExpected[i]) {
      allOk = false;
      console.log(`  counter=${i} got=${code} want=${hotpExpected[i]}`);
    }
  }
  check('[HOTP] RFC4226 10 组官方向量', allOk);

  // ---- RFC 6238 附录 B：TOTP-SHA1（8 位） ----
  const totpVectors = [
    [59, '94287082'], [1111111109, '07081804'], [1111111111, '14050471'],
    [1234567890, '89005924'], [2000000000, '69279037'], [20000000000, '65353130']
  ];
  let totpOk = true;
  for (const [t, want] of totpVectors) {
    const code = OtpEngine.computeCode(secretBytes, HashAlg.SHA1, 8, Math.floor(t / 30));
    if (code !== want) {
      totpOk = false;
      console.log(`  T=${t} got=${code} want=${want}`);
    }
  }
  check('[TOTP] RFC6238 6 组官方向量', totpOk);

  // ---- 摘要自检 ----
  check('[SHA1] digest("abc")',
    hex(Digest.hash(HashAlg.SHA1, new Uint8Array([97, 98, 99]))) === 'a9993e364706816aba3e25717850c26c9cd0d89d');
  check('[SHA256] digest("abc")',
    hex(Digest.hash(HashAlg.SHA256, new Uint8Array([97, 98, 99]))) === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');

  // ---- HMAC RFC 2202 官方向量 ----
  const hmacCase1 = hex(Hmac.digest(HashAlg.SHA1, new Uint8Array(Array(20).fill(0x0b)),
    new Uint8Array(Buffer.from('Hi There'))));
  check('[HMAC-SHA1] RFC2202 case1', hmacCase1 === 'b617318655057264e28bc0b6fb378c8ef146be00', hmacCase1);
  const hmacCase2 = hex(Hmac.digest(HashAlg.SHA1, new Uint8Array(Buffer.from('Jefe')),
    new Uint8Array(Buffer.from('what do ya want for nothing?'))));
  check('[HMAC-SHA1] RFC2202 case2', hmacCase2 === 'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79', hmacCase2);
  const hmacCase4 = hex(Hmac.digest(HashAlg.SHA1, new Uint8Array(Array.from({ length: 25 }, (_, i) => i + 1)),
    new Uint8Array(Array(50).fill(0xcd))));
  check('[HMAC-SHA1] RFC2202 case4', hmacCase4 === '4c9007f4026250c6bc8414f9bf50c86c2d7235da', hmacCase4);

  // ---- 与 Node crypto 交叉验证（含跨分组长消息、随机 key/msg） ----
  for (const alg of ['SHA1', 'SHA256']) {
    let ok = true;
    for (let trial = 0; trial < 20; trial++) {
      const keyLen = [16, 63, 64, 65, 100][trial % 5];
      const key = Buffer.from(Array.from({ length: keyLen }, () => Math.floor(Math.random() * 256)));
      const msg = Buffer.from(Array.from({ length: trial * 37 + 1 }, () => Math.floor(Math.random() * 256)));
      const mine = hex(Hmac.digest(HashAlg[alg], new Uint8Array(key), new Uint8Array(msg)));
      const ref = createHmac(alg === 'SHA1' ? 'sha1' : 'sha256', key).update(msg).digest('hex');
      if (mine !== ref) {
        ok = false;
        console.log(`  trial=${trial} keyLen=${keyLen} msgLen=${msg.length} mine=${mine} ref=${ref}`);
        break;
      }
    }
    check(`[HMAC-${alg}] vs node crypto 随机 20 组(含边界 key 长度)`, ok);
  }

  // ---- 64 位状态高位（state > 2^32）验证 ----
  const bigState = Math.floor(20000000000 / 30); // 666666666 仍在 32 位内，构造一个超过的
  const big = 0x1_0000_0000 + 7; // 2^32 + 7
  const msgBytes = new Uint8Array(8);
  new DataView(msgBytes.buffer).setUint32(0, Math.floor(big / 0x100000000), false);
  new DataView(msgBytes.buffer).setUint32(4, big % 0x100000000, false);
  const bigMine = hex(Hmac.digest(HashAlg.SHA1, secretBytes, msgBytes));
  const bigRef = createHmac('sha1', Buffer.from(secretBytes)).update(msgBytes).digest('hex');
  check('[状态编码] 64 位大端(state>2^32) 与 crypto 一致', bigMine === bigRef);
  console.log(`  (交叉对照 bigState=${bigState})`);

  // Exercise wrappers using the real Account module and hashAlgOf mapping.
  for (let counter = 0; counter < hotpExpected.length; counter++) {
    check(`[HOTP wrapper] counter=${counter}`, OtpEngine.hotp({ ...makeAccount(OtpType.HOTP), counter }) === hotpExpected[counter]);
  }
  const sha256Expected = ['46119246', '68084774', '67062674', '91819424', '90698825', '77737706'];
  for (const [i, [time, expected]] of totpVectors.entries()) {
    const account = { ...makeAccount(), digits: 8 };
    check(`[TOTP SHA1 wrapper] ${time}`, OtpEngine.totp(cloneAccount(account), time * 1000) === expected);
    account.algorithm = 'SHA256';
    account.secret = Base32String.encode(Buffer.from('12345678901234567890123456789012'));
    check(`[TOTP SHA256 RFC6238] ${time}`, OtpEngine.totp(account, time * 1000) === sha256Expected[i]);
  }
  const invalidFields = {
    secret: ['', 'A', '====', 'INVALID!'], type: [-1, 2, 'TOTP'],
    digits: [0, 10, 6.5, NaN, Infinity, '6'], algorithm: ['', 'SHA512', 'sha1'],
    period: [0, 3601, 1.5, NaN, Infinity, '30'],
    counter: [-1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '0']
  };
  for (const [field, values] of Object.entries(invalidFields)) {
    for (const value of values) {
      const account = { ...makeAccount(), [field]: value };
      check(`[invalid account] ${field}=${String(value)}`, !OtpEngine.isValidParameters(account)
        && OtpEngine.totp(account, 59000) === '' && OtpEngine.hotp(account) === '');
    }
  }
  for (const state of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    check(`[invalid state] ${state}`, OtpEngine.computeCode(secretBytes, HashAlg.SHA1, 6, state) === '');
  }
  for (const digits of [0, 10, 1.5, NaN, Infinity]) {
    check(`[invalid digits] ${digits}`, OtpEngine.computeCode(secretBytes, HashAlg.SHA1, digits, 0) === '');
  }
  check('[invalid engine algorithm/secret]', OtpEngine.computeCode(secretBytes, 'SHA512', 6, 0) === ''
    && OtpEngine.computeCode(new Uint8Array(), HashAlg.SHA1, 6, 0) === '');
  for (const now of [-1, NaN, Infinity, Number.MAX_VALUE]) {
    check(`[invalid time] ${now}`, OtpEngine.totp(makeAccount(), now) === '');
  }
  for (const digits of [1, 9]) {
    for (const period of [1, 3600]) {
      const account = { ...makeAccount(), digits, period, counter: Number.MAX_SAFE_INTEGER };
      check(`[valid bounds] ${digits}/${period}`, OtpEngine.isValidParameters(account)
        && new RegExp(`^[0-9]{${digits}}$`).test(OtpEngine.hotp(account)));
    }
  }
  const baseUri = 'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP';
  check('[URI defaults]', OtpUri.parse(baseUri).ok && OtpUri.parse(baseUri).period === 30);
  const badQueries = ['secret=', 'secret=A', 'secret=INVALID!', 'algorithm=', 'algorithm=SHA512', 'algorithm=MD5',
    'issuer=Other', 'issuer=', 'issuer=%ZZ', 'unknown=%ZZ', 'se%ZZcret=x',
    'digits=6&digits=6', 'DIGITS=6&%64igits=8', 'issuer=Example&issuer=Example',
    'algorithm=SHA1&algorithm=SHA256', 'period=30&period=30', 'counter=0&counter=1'];
  for (const field of ['digits', 'period', 'counter']) {
    for (const value of ['', '-1', '1.5', '1e2', '0x10', '%201', '1%20', '%2B1', 'NaN', 'Infinity', '9007199254740992']) {
      badQueries.push(`${field}=${value}`);
    }
  }
  badQueries.push('digits=0', 'digits=10', 'period=0', 'period=3601', 'digits');
  for (const query of badQueries) {
    const parsed = OtpUri.parse(`${baseUri}&${query}`);
    check(`[URI rejects] ${query}`, !parsed.ok && parsed.error.length > 0);
  }
  for (const uri of ['otpauth://totp/a?secret=A', 'otpauth://totp/a?secret=INVALID!',
    'otpauth://hotp/a?secret=JBSWY3DPEHPK3PXP', 'otpauth://totp/%ZZ?secret=JBSWY3DPEHPK3PXP',
    'otpauth://totp/a', 'otpauth://other/a?secret=MY', 'https://totp/a?secret=MY']) {
    check(`[URI invalid] ${uri}`, !OtpUri.parse(uri).ok);
  }
  for (const type of [OtpType.TOTP, OtpType.HOTP]) {
    for (const digits of [1, 9]) {
      const account = { ...makeAccount(type), name: '爱丽丝 + & / %', issuer: '示例 & + %',
        secret: 'MY======', algorithm: 'SHA256', digits, period: 3600, counter: Number.MAX_SAFE_INTEGER };
      const uri = OtpUri.build(account);
      const parsed = OtpUri.parse(uri);
      check(`[URI roundtrip] type=${type} digits=${digits}`, uri.includes('secret=MY%3D%3D%3D%3D%3D%3D')
        && parsed.ok && ['name', 'issuer', 'secret', 'algorithm', 'digits', 'type', type === OtpType.TOTP ? 'period' : 'counter']
          .every(field => parsed[field] === account[field]));
    }
  }
  check('[URI decimal boundaries]', OtpUri.parse(`${baseUri}&digits=01&period=1&counter=9007199254740991`).ok);
  check('[URI case and encoded keys]', OtpUri.parse('OTPAUTH://TOTP/a?%73ecret=MY&algorithm=sha256').ok);
  console.log(failures === 0 ? '\n=== ALL TESTS PASSED ===' : `\n=== ${failures} FAILURES ===`);
  process.exitCode = failures === 0 ? 0 : 1;
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
}).finally(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});
