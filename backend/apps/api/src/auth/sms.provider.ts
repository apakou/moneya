import { Injectable } from '@nestjs/common';

export const SMS_PROVIDER = Symbol('SMS_PROVIDER');

export interface SmsProvider {
  /** Deliver a one-time code. Must throw on delivery failure. */
  sendOtp(phone: string, code: string, locale: 'fr' | 'en'): Promise<void>;
}

/**
 * Dev/test provider: keeps messages in memory, nothing leaves the process.
 * Real Twilio Verify / Africa's Talking adapters implement the same port and
 * are selected by SMS_PROVIDER env once keys exist.
 */
@Injectable()
export class FakeSmsProvider implements SmsProvider {
  readonly sent: { phone: string; code: string; locale: string }[] = [];

  sendOtp(phone: string, code: string, locale: 'fr' | 'en'): Promise<void> {
    this.sent.push({ phone, code, locale });
    return Promise.resolve();
  }

  lastCode(phone: string): string | undefined {
    return [...this.sent].reverse().find((m) => m.phone === phone)?.code;
  }
}
