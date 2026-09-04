/**
 * Base32 编解码，移植自 Android 版 Google Authenticator 的 Base32String。
 * 解码时忽略空格、连字符与结尾填充符（"="），大小写不敏感；
 * 编码时不添加填充——与 Google Authenticator 的行为保持一致。
 */

const DIGITS: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export class Base32String {
  static decode(encoded: string): Uint8Array {
    // 去掉空白与分隔符
    let s = encoded.trim().split('-').join('').split(' ').join('');
    // 去掉结尾的填充符
    while (s.length > 0 && s.charAt(s.length - 1) === '=') {
      s = s.substring(0, s.length - 1);
    }
    s = s.toUpperCase();
    if (s.length === 0) {
      return new Uint8Array(0);
    }
    const shift = 5; // 每个字符 5 比特
    const outLength = Math.floor(s.length * shift / 8);
    const result = new Uint8Array(outLength);
    let buffer = 0;
    let next = 0;
    let bitsLeft = 0;
    for (let i = 0; i < s.length; i++) {
      const c = s.charAt(i);
      const val = DIGITS.indexOf(c);
      if (val < 0) {
        throw new Error(`非法的 Base32 字符: ${c}`);
      }
      buffer = ((buffer << shift) | val) >>> 0;
      bitsLeft += shift;
      if (bitsLeft >= 8) {
        result[next++] = (buffer >> (bitsLeft - 8)) & 0xff;
        bitsLeft -= 8;
      }
    }
    // 末尾不足 8 比特的余数忽略（与 Android 版一致）
    return result;
  }

  static encode(data: Uint8Array): string {
    if (data.length === 0) {
      return '';
    }
    let result = '';
    let buffer = data[0];
    let next = 1;
    let bitsLeft = 8;
    while (bitsLeft > 0 || next < data.length) {
      if (bitsLeft < 5) {
        if (next < data.length) {
          buffer = ((buffer << 8) | data[next++]) >>> 0;
          bitsLeft += 8;
        } else {
          const pad = 5 - bitsLeft;
          buffer = (buffer << pad) >>> 0;
          bitsLeft += pad;
        }
      }
      const index = 31 & (buffer >>> (bitsLeft - 5));
      bitsLeft -= 5;
      result += DIGITS.charAt(index);
    }
    return result;
  }
}
