import { Hmac, HashAlg } from './Digest';
import { Base32String } from './Base32';
import { AccountInfo, hashAlgOf } from '../model/Account';

/**
 * OTP 计算引擎，移植自 Android 版 Google Authenticator 的
 * PasscodeGenerator / OtpProvider（RFC 4226 HOTP + RFC 6238 TOTP）。
 */
export class OtpEngine {
  /** 10 的幂，避免浮点幂运算误差（与 RFC 6238 参考实现一致） */
  private static readonly DIGITS_POWER: number[] =
    [1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000];

  /**
   * RFC 4226：给定状态（HOTP 计数器或 TOTP 时间片）计算验证码。
   */
  static computeCode(secretBytes: Uint8Array, alg: HashAlg, digits: number, state: number): string {
    // 8 字节大端状态
    const msg = new Uint8Array(8);
    const dv = new DataView(msg.buffer);
    const hi = Math.floor(state / 0x100000000);
    const lo = state - hi * 0x100000000;
    dv.setUint32(0, hi, false);
    dv.setUint32(4, lo, false);

    const hash = Hmac.digest(alg, secretBytes, msg);

    // 动态截断：偏移取最后一个字节的低 4 位
    const offset = hash[hash.length - 1] & 0xf;
    const truncatedHash = (((hash[offset] & 0x7f) << 24)
      | ((hash[offset + 1] & 0xff) << 16)
      | ((hash[offset + 2] & 0xff) << 8)
      | (hash[offset + 3] & 0xff)) >>> 0;
    const pinValue = truncatedHash % OtpEngine.DIGITS_POWER[digits];

    // 前导补零
    let result = pinValue.toString();
    for (let i = result.length; i < digits; i++) {
      result = `0${result}`;
    }
    return result;
  }

  /** 当前时间片：floor(unixSeconds / period)，对应 TotpCounter.getValueAtTime */
  static timeSlice(nowMillis: number, period: number): number {
    return Math.floor(Math.floor(nowMillis / 1000) / period);
  }

  /** 校验密钥是否合法（能被 Base32 解码） */
  static isValidSecret(secret: string): boolean {
    try {
      return Base32String.decode(secret).length > 0;
    } catch (e) {
      return false;
    }
  }

  /** 计算 TOTP 当前验证码；密钥非法时返回空串 */
  static totp(account: AccountInfo, nowMillis: number): string {
    try {
      const secretBytes = Base32String.decode(account.secret);
      const state = OtpEngine.timeSlice(nowMillis, account.period);
      return OtpEngine.computeCode(secretBytes, hashAlgOf(account), account.digits, state);
    } catch (e) {
      return '';
    }
  }

  /** 计算 HOTP 当前计数器对应的验证码 */
  static hotp(account: AccountInfo): string {
    try {
      const secretBytes = Base32String.decode(account.secret);
      return OtpEngine.computeCode(secretBytes, hashAlgOf(account), account.digits, account.counter);
    } catch (e) {
      return '';
    }
  }

  /** TOTP 周期内剩余毫秒数 */
  static remainingMillis(nowMillis: number, period: number): number {
    const msInSlice = nowMillis % (period * 1000);
    return period * 1000 - msInSlice;
  }
}
