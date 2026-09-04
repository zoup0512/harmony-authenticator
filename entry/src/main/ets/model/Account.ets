import { HashAlg } from '../otp/Digest';

/** OTP 类型：时间型 / 计数器型，取值与 Android 版 AccountDb.OtpType 一致 */
export enum OtpType {
  TOTP = 0,
  HOTP = 1
}

/** 账户模型，对应 Android 版 AccountDb 的一行记录 */
export interface AccountInfo {
  /** 唯一 id（自增） */
  id: number;
  /** 账户名，如 alice@example.com */
  name: string;
  /** 服务提供方（如 Google），可为空 */
  issuer: string;
  /** Base32 编码的密钥 */
  secret: string;
  /** TOTP 或 HOTP */
  type: OtpType;
  /** HOTP 计数器 */
  counter: number;
  /** 验证码位数（6/8） */
  digits: number;
  /** 哈希算法 */
  algorithm: string;
  /** TOTP 周期（秒） */
  period: number;
  /** 创建时间戳（毫秒） */
  createdAt: number;
  /** 排序序号 */
  sortOrder: number;
}

/** 用于 JSON 序列化/反序列化的辅助（ArkTS 下手动拷贝字段以保证类型正确） */
export function cloneAccount(a: AccountInfo): AccountInfo {
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
    sortOrder: a.sortOrder
  };
  return copy;
}

export function hashAlgOf(a: AccountInfo): HashAlg {
  return a.algorithm === 'SHA256' ? HashAlg.SHA256 : HashAlg.SHA1;
}
