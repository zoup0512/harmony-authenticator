import { OtpType, AccountInfo } from '../model/Account';
import { Base32String } from './Base32';

/** otpauth:// URI 解析；显式提供的非法参数不得回退为默认值。 */
export class OtpUri {
  static parse(uri: string): ParseResult {
    const result: ParseResult = { ok: false, error: '', name: '', issuer: '', secret: '',
      type: OtpType.TOTP, counter: 0, digits: 6, algorithm: 'SHA1', period: 30 };
    const fail = (error: string): ParseResult => {
      result.error = error;
      return result;
    };
    const prefix = 'otpauth://';
    let s = uri.trim();
    if (s.toLowerCase().indexOf(prefix) !== 0) {
      return fail('链接必须以 otpauth:// 开头');
    }
    s = s.substring(prefix.length);
    const slashIdx = s.indexOf('/');
    if (slashIdx < 0) return fail('链接缺少类型（totp/hotp）');
    const host = s.substring(0, slashIdx).toLowerCase();
    if (host === 'totp') {
      result.type = OtpType.TOTP;
    } else if (host === 'hotp') {
      result.type = OtpType.HOTP;
    } else {
      return fail(`不支持的类型: ${host}`);
    }
    s = s.substring(slashIdx + 1);
    const qIdx = s.indexOf('?');
    const label = qIdx < 0 ? s : s.substring(0, qIdx);
    const query = qIdx < 0 ? '' : s.substring(qIdx + 1);
    let decodedLabel = '';
    try {
      decodedLabel = decodeURIComponent(label);
    } catch (e) {
      return fail('标签编码无效');
    }
    const colonIdx = decodedLabel.indexOf(':');
    const hasLabelIssuer = colonIdx >= 0;
    if (hasLabelIssuer) {
      result.issuer = decodedLabel.substring(0, colonIdx).trim();
      result.name = decodedLabel.substring(colonIdx + 1).trim();
    } else {
      result.name = decodedLabel.trim();
    }
    const labelIssuer = result.issuer;
    const recognized: string[] = ['secret', 'issuer', 'algorithm', 'digits', 'period', 'counter'];
    const seen: string[] = [];
    if (query.length > 0) {
      for (const pair of query.split('&')) {
        if (pair.length === 0) continue;
        const eqIdx = pair.indexOf('=');
        let key = '';
        let value = '';
        try {
          key = decodeURIComponent(eqIdx < 0 ? pair : pair.substring(0, eqIdx)).toLowerCase();
          value = decodeURIComponent(eqIdx < 0 ? '' : pair.substring(eqIdx + 1));
        } catch (e) {
          return fail('参数编码无效');
        }
        if (recognized.indexOf(key) < 0) continue;
        if (seen.indexOf(key) >= 0) return fail(`重复参数: ${key}`);
        seen.push(key);
        if (key === 'secret') {
          result.secret = value.replace(/[\s-]/g, '').toUpperCase();
        } else if (key === 'issuer') {
          result.issuer = value.trim();
          if (hasLabelIssuer && result.issuer !== labelIssuer) return fail('issuer 与标签前缀不一致');
        } else if (key === 'algorithm') {
          const alg = value.toUpperCase();
          if (alg !== 'SHA1' && alg !== 'SHA256') return fail(`不支持的算法: ${value}`);
          result.algorithm = alg;
        } else {
          if (!/^[0-9]+$/.test(value)) return fail(`${key} 必须为十进制整数`);
          const number = Number(value);
          if (!Number.isSafeInteger(number)) return fail(`${key} 超出安全整数范围`);
          if (key === 'digits') {
            if (number < 1 || number > 9) return fail('digits 必须在 1 到 9 之间');
            result.digits = number;
          } else if (key === 'period') {
            if (number < 1 || number > 3600) return fail('period 必须在 1 到 3600 之间');
            result.period = number;
          } else {
            result.counter = number;
          }
        }
      }
    }
    try {
      if (seen.indexOf('secret') < 0 || Base32String.decode(result.secret).length === 0) {
        return fail('链接缺少有效密钥（secret 参数）');
      }
    } catch (e) {
      return fail('密钥不是有效的 Base32');
    }
    if (result.type === OtpType.HOTP && seen.indexOf('counter') < 0) return fail('HOTP 缺少 counter');
    if (result.name.length === 0) {
      result.name = result.issuer.length > 0 ? result.issuer : '未命名账户';
    }
    result.ok = true;
    return result;
  }

  /** 生成 otpauth:// URI（用于将来导出/展示） */
  static build(a: AccountInfo): string {
    const type = a.type === OtpType.HOTP ? 'hotp' : 'totp';
    const label = a.issuer.length > 0
      ? `${encodeURIComponent(a.issuer)}:${encodeURIComponent(a.name)}`
      : encodeURIComponent(a.name);
    let uri = `otpauth://${type}/${label}?secret=${encodeURIComponent(a.secret)}`;
    if (a.issuer.length > 0) uri += `&issuer=${encodeURIComponent(a.issuer)}`;
    uri += `&algorithm=${a.algorithm}&digits=${a.digits}`;
    if (a.type === OtpType.TOTP) {
      uri += `&period=${a.period}`;
    } else {
      uri += `&counter=${a.counter}`;
    }
    return uri;
  }
}

export interface ParseResult {
  ok: boolean;
  error: string;
  name: string;
  issuer: string;
  secret: string;
  type: OtpType;
  counter: number;
  digits: number;
  algorithm: string;
  period: number;
}
