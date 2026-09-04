import { OtpType, AccountInfo } from '../model/Account';

/**
 * otpauth:// URI 解析。
 * 格式参考 Google Authenticator：
 *   otpauth://totp/Issuer:account?secret=XXX&issuer=Issuer&algorithm=SHA1&digits=6&period=30
 *   otpauth://hotp/Issuer:account?secret=XXX&counter=0
 */
export class OtpUri {
  /** 解析结果：成功时 account 字段可用（id/createdAt 等由存储层填充），失败时 error 有值 */
  static parse(uri: string): ParseResult {
    const result: ParseResult = { ok: false, error: '', name: '', issuer: '', secret: '',
      type: OtpType.TOTP, counter: 0, digits: 6, algorithm: 'SHA1', period: 30 };

    let s = uri.trim();
    const prefix = 'otpauth://';
    if (s.toLowerCase().indexOf(prefix) !== 0) {
      result.error = '链接必须以 otpauth:// 开头';
      return result;
    }
    s = s.substring(prefix.length);

    // 主机部分：totp / hotp
    const slashIdx = s.indexOf('/');
    if (slashIdx < 0) {
      result.error = '链接缺少类型（totp/hotp）';
      return result;
    }
    const host = s.substring(0, slashIdx).toLowerCase();
    if (host === 'totp') {
      result.type = OtpType.TOTP;
    } else if (host === 'hotp') {
      result.type = OtpType.HOTP;
    } else {
      result.error = `不支持的类型: ${host}`;
      return result;
    }
    s = s.substring(slashIdx + 1);

    // 拆出查询串
    let label = s;
    let query = '';
    const qIdx = s.indexOf('?');
    if (qIdx >= 0) {
      label = s.substring(0, qIdx);
      query = s.substring(qIdx + 1);
    }

    // 标签：Issuer:account 或直接 account
    let decodedLabel = '';
    try {
      decodedLabel = decodeURIComponent(label);
    } catch (e) {
      decodedLabel = label;
    }
    const colonIdx = decodedLabel.indexOf(':');
    if (colonIdx > 0) {
      result.issuer = decodedLabel.substring(0, colonIdx).trim();
      result.name = decodedLabel.substring(colonIdx + 1).trim();
    } else {
      result.name = decodedLabel.trim();
    }

    // 解析查询参数
    let hasSecret = false;
    if (query.length > 0) {
      const pairs = query.split('&');
      for (const pair of pairs) {
        const eqIdx = pair.indexOf('=');
        if (eqIdx <= 0) {
          continue;
        }
        const key = pair.substring(0, eqIdx).toLowerCase();
        let value = pair.substring(eqIdx + 1);
        try {
          value = decodeURIComponent(value);
        } catch (e) {
          // 保留原值
        }
        if (key === 'secret') {
          result.secret = value.replace(/[\s-]/g, '').toUpperCase();
          hasSecret = true;
        } else if (key === 'issuer') {
          // 参数里的 issuer 优先级低于标签前缀
          if (result.issuer.length === 0) {
            result.issuer = value.trim();
          }
        } else if (key === 'algorithm') {
          const alg = value.toUpperCase();
          if (alg === 'SHA1' || alg === 'SHA256') {
            result.algorithm = alg;
          } else if (alg === 'SHA512') {
            result.error = '暂不支持 SHA512 算法';
            return result;
          }
        } else if (key === 'digits') {
          const digits = Number(value);
          if (digits >= 1 && digits <= 9) {
            result.digits = digits;
          }
        } else if (key === 'period') {
          const period = Number(value);
          if (period >= 1 && period <= 3600) {
            result.period = period;
          }
        } else if (key === 'counter') {
          const counter = Number(value);
          if (!isNaN(counter) && counter >= 0) {
            result.counter = Math.floor(counter);
          }
        }
      }
    }

    if (!hasSecret || result.secret.length === 0) {
      result.error = '链接缺少密钥（secret 参数）';
      return result;
    }
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
    let uri = `otpauth://${type}/${label}?secret=${a.secret}`;
    if (a.issuer.length > 0) {
      uri += `&issuer=${encodeURIComponent(a.issuer)}`;
    }
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
