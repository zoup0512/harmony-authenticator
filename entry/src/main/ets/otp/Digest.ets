/**
 * 纯 ArkTS 实现的 SHA-1 / SHA-256 / HMAC。
 * 移植自 RFC 3174 (SHA-1)、FIPS 180-4 (SHA-256)、RFC 2104 (HMAC)，
 * 与 Android 版 Google Authenticator 使用的 JCE 结果完全一致。
 * 采用同步纯计算实现，方便每秒刷新验证码且不依赖异步 crypto 框架。
 */

export enum HashAlg {
  SHA1 = 'SHA1',
  SHA256 = 'SHA256'
}

export class Digest {
  private static readonly K256: number[] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  private static readonly ROTR = (x: number, n: number): number => ((x >>> n) | (x << (32 - n))) >>> 0;

  /** 计算摘要，返回原始字节（SHA1: 20 字节，SHA256: 32 字节） */
  static hash(alg: HashAlg, data: Uint8Array): Uint8Array {
    if (alg === HashAlg.SHA1) {
      return Digest.sha1(data);
    }
    return Digest.sha256(data);
  }

  /** 摘要输出字节数 */
  static digestLength(alg: HashAlg): number {
    return alg === HashAlg.SHA1 ? 20 : 32;
  }

  /** 分组大小：SHA1 与 SHA256 均为 64 字节 */
  static blockSize(alg: HashAlg): number {
    return 64;
  }

  private static sha1(data: Uint8Array): Uint8Array {
    const h = new Int32Array([0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]);
    const padded = Digest.pad(data);
    const dv = new DataView(padded.buffer);
    const w = new Int32Array(80);
    for (let off = 0; off < padded.length; off += 64) {
      for (let i = 0; i < 16; i++) {
        w[i] = dv.getInt32(off + i * 4, false);
      }
      for (let i = 16; i < 80; i++) {
        const n = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
        w[i] = ((n << 1) | (n >>> 31)) | 0;
      }
      let a = h[0];
      let b = h[1];
      let c = h[2];
      let d = h[3];
      let e = h[4];
      for (let i = 0; i < 80; i++) {
        let f: number;
        let k: number;
        if (i < 20) {
          f = (b & c) | (~b & d);
          k = 0x5a827999;
        } else if (i < 40) {
          f = b ^ c ^ d;
          k = 0x6ed9eba1;
        } else if (i < 60) {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8f1bbcdc;
        } else {
          f = b ^ c ^ d;
          k = 0xca62c1d6;
        }
        const tmp = ((((a << 5) | (a >>> 27)) + f) + e + k + w[i]) | 0;
        e = d;
        d = c;
        c = ((b << 30) | (b >>> 2)) | 0;
        b = a;
        a = tmp;
      }
      h[0] = (h[0] + a) | 0;
      h[1] = (h[1] + b) | 0;
      h[2] = (h[2] + c) | 0;
      h[3] = (h[3] + d) | 0;
      h[4] = (h[4] + e) | 0;
    }
    const out = new Uint8Array(20);
    const odv = new DataView(out.buffer);
    for (let i = 0; i < 5; i++) {
      odv.setInt32(i * 4, h[i], false);
    }
    return out;
  }

  private static sha256(data: Uint8Array): Uint8Array {
    const h: number[] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    const padded = Digest.pad(data);
    const dv = new DataView(padded.buffer);
    const w = new Array<number>(64);
    for (let off = 0; off < padded.length; off += 64) {
      for (let i = 0; i < 16; i++) {
        w[i] = dv.getUint32(off + i * 4, false);
      }
      for (let i = 16; i < 64; i++) {
        const s0 = Digest.ROTR(w[i - 15], 7) ^ Digest.ROTR(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        const s1 = Digest.ROTR(w[i - 2], 17) ^ Digest.ROTR(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
      }
      let a = h[0];
      let b = h[1];
      let c = h[2];
      let d = h[3];
      let e = h[4];
      let f = h[5];
      let g = h[6];
      let hh = h[7];
      for (let i = 0; i < 64; i++) {
        const s1 = Digest.ROTR(e, 6) ^ Digest.ROTR(e, 11) ^ Digest.ROTR(e, 25);
        const ch = (e & f) ^ (~e & g);
        const t1 = (hh + s1 + ch + Digest.K256[i] + w[i]) >>> 0;
        const s0 = Digest.ROTR(a, 2) ^ Digest.ROTR(a, 13) ^ Digest.ROTR(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = (s0 + maj) >>> 0;
        hh = g;
        g = f;
        f = e;
        e = (d + t1) >>> 0;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) >>> 0;
      }
      h[0] = (h[0] + a) >>> 0;
      h[1] = (h[1] + b) >>> 0;
      h[2] = (h[2] + c) >>> 0;
      h[3] = (h[3] + d) >>> 0;
      h[4] = (h[4] + e) >>> 0;
      h[5] = (h[5] + f) >>> 0;
      h[6] = (h[6] + g) >>> 0;
      h[7] = (h[7] + hh) >>> 0;
    }
    const out = new Uint8Array(32);
    const odv = new DataView(out.buffer);
    for (let i = 0; i < 8; i++) {
      odv.setUint32(i * 4, h[i], false);
    }
    return out;
  }

  /** Merkle–Damgård 填充：0x80 + 0…0 + 8 字节大端比特长度 */
  private static pad(data: Uint8Array): Uint8Array {
    const len = data.length;
    const total = (((len + 8) >> 6) + 1) << 6;
    const buf = new Uint8Array(total);
    buf.set(data);
    buf[len] = 0x80;
    const dv = new DataView(buf.buffer);
    // 消息不会超过 512MB，高 32 位恒为 0
    dv.setUint32(total - 4, (len * 8) >>> 0, false);
    dv.setUint32(total - 8, Math.floor(len / 536870912), false);
    return buf;
  }
}

/**
 * HMAC（RFC 2104）：H(K XOR opad, H(K XOR ipad, m))
 */
export class Hmac {
  static digest(alg: HashAlg, key: Uint8Array, message: Uint8Array): Uint8Array {
    const block = Digest.blockSize(alg);
    let k = key;
    if (k.length > block) {
      k = Digest.hash(alg, k);
    }
    const innerLen = block + message.length;
    const ipad = new Uint8Array(innerLen);
    const opad = new Uint8Array(block + Digest.digestLength(alg));
    for (let i = 0; i < block; i++) {
      const kb = i < k.length ? k[i] : 0;
      ipad[i] = (kb ^ 0x36) & 0xff;
      opad[i] = (kb ^ 0x5c) & 0xff;
    }
    ipad.set(message, block);
    const inner = Digest.hash(alg, ipad);
    opad.set(inner, block);
    return Digest.hash(alg, opad);
  }
}
