import type { SmsProvider } from './sms.provider';

export interface HttpSmsConfig {
  /** Human label for logs/metrics (never the URL: it may embed secrets). */
  name?: string;
  url: string;
  /** Request encoding. Africa's-Talking-style gateways use `form`; most others `json`. */
  format?: 'json' | 'form';
  /** Static headers, e.g. {"apiKey": "..."} or {"Authorization": "Bearer ..."}. */
  headers?: Record<string, string>;
  /** Body field names; defaults to to/message/from. */
  fields?: { to?: string; message?: string; from?: string };
  sender?: string;
  /** Static extra body fields, e.g. {"username": "moneya"}. */
  extra?: Record<string, string>;
  timeoutMs?: number;
}

export function otpMessage(code: string, locale: 'fr' | 'en'): string {
  return locale === 'en'
    ? `MoneyA: your code is ${code}. Never share it with anyone.`
    : `MoneyA : votre code est ${code}. Ne le partagez avec personne.`;
}

/**
 * Provider-agnostic SMS adapter: one HTTP POST per message to any aggregator
 * that accepts it (config-only; no vendor SDK). Success = 2xx. Errors never
 * include the phone number, the code or the response body.
 */
export class HttpSmsProvider implements SmsProvider {
  constructor(
    private readonly cfg: HttpSmsConfig,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  get name(): string {
    return this.cfg.name ?? 'http';
  }

  async sendOtp(phone: string, code: string, locale: 'fr' | 'en'): Promise<void> {
    const f = { to: 'to', message: 'message', from: 'from', ...this.cfg.fields };
    const fields: Record<string, string> = {
      ...this.cfg.extra,
      [f.to]: phone,
      [f.message]: otpMessage(code, locale),
    };
    if (this.cfg.sender) fields[f.from] = this.cfg.sender;

    const form = this.cfg.format === 'form';
    const res = await this.fetchImpl(this.cfg.url, {
      method: 'POST',
      headers: {
        'content-type': form ? 'application/x-www-form-urlencoded' : 'application/json',
        accept: 'application/json',
        ...this.cfg.headers,
      },
      body: form ? new URLSearchParams(fields).toString() : JSON.stringify(fields),
      signal: AbortSignal.timeout(this.cfg.timeoutMs ?? 8000),
    });
    if (!res.ok) throw new Error(`SMS provider ${this.name} responded ${res.status}`);
  }
}

/** Tries providers in order; fails only if all of them fail. */
export class FailoverSmsProvider implements SmsProvider {
  constructor(private readonly providers: readonly SmsProvider[]) {
    if (providers.length === 0) throw new Error('FailoverSmsProvider needs at least one provider');
  }

  async sendOtp(phone: string, code: string, locale: 'fr' | 'en'): Promise<void> {
    let last: unknown;
    for (const p of this.providers) {
      try {
        await p.sendOtp(phone, code, locale);
        return;
      } catch (err) {
        last = err;
      }
    }
    throw last instanceof Error ? last : new Error('All SMS providers failed');
  }
}
