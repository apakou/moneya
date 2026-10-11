import { FakeSmsProvider, type SmsProvider } from './sms.provider';
import { FailoverSmsProvider, HttpSmsProvider, type HttpSmsConfig } from './sms.http';

/**
 * SMS_PROVIDER=fake (default outside production) | http
 * SMS_HTTP_CONFIGS = JSON array of {@link HttpSmsConfig}, tried in order (failover).
 */
export function createSmsProvider(
  env: NodeJS.ProcessEnv = process.env,
  fake: FakeSmsProvider = new FakeSmsProvider(),
): SmsProvider {
  const kind = env.SMS_PROVIDER ?? (env.NODE_ENV === 'production' ? '' : 'fake');
  if (kind === 'fake') {
    if (env.NODE_ENV === 'production')
      throw new Error('SMS_PROVIDER=fake is not allowed in production');
    return fake;
  }
  if (kind === 'http') {
    let configs: HttpSmsConfig[];
    try {
      configs = JSON.parse(env.SMS_HTTP_CONFIGS ?? '') as HttpSmsConfig[];
    } catch {
      throw new Error('SMS_HTTP_CONFIGS must be a JSON array of provider configs');
    }
    if (
      !Array.isArray(configs) ||
      configs.length === 0 ||
      configs.some((c) => !/^https:\/\//.test(c?.url ?? ''))
    ) {
      throw new Error('SMS_HTTP_CONFIGS needs at least one entry, each with an https url');
    }
    return new FailoverSmsProvider(
      configs.map((c, i) => new HttpSmsProvider({ name: `sms${i + 1}`, ...c })),
    );
  }
  throw new Error('SMS_PROVIDER must be set to "fake" or "http"');
}
