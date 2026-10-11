import { createServer, type IncomingMessage, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { FailoverSmsProvider, HttpSmsProvider, otpMessage } from '../src/auth/sms.http';
import { createSmsProvider } from '../src/auth/sms.factory';
import { FakeSmsProvider } from '../src/auth/sms.provider';

interface Seen {
  headers: IncomingMessage['headers'];
  body: string;
}

describe('SMS providers', () => {
  let server: Server;
  let base: string;
  let seen: Seen[];
  let status = 200;

  beforeAll(async () => {
    server = createServer((req, res) => {
      const chunks: Buffer[] = [];
      req.on('data', (c: Buffer) => chunks.push(c));
      req.on('end', () => {
        seen.push({ headers: req.headers, body: Buffer.concat(chunks).toString() });
        res.statusCode = req.url === '/down' ? 503 : status;
        res.end('{"detail":"secret provider text +233201234567 123456"}');
      });
    });
    await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  afterAll(() => new Promise<void>((r) => server.close(() => r())));
  beforeEach(() => {
    seen = [];
    status = 200;
  });

  it('sends JSON with auth header, sender and the localized message', async () => {
    const p = new HttpSmsProvider({
      url: `${base}/send`,
      headers: { Authorization: 'Bearer t0k' },
      sender: 'MoneyA',
    });
    await p.sendOtp('+233201234567', '482916', 'en');
    expect(seen).toHaveLength(1);
    expect(seen[0]!.headers.authorization).toBe('Bearer t0k');
    expect(seen[0]!.headers['content-type']).toBe('application/json');
    expect(JSON.parse(seen[0]!.body)).toEqual({
      to: '+233201234567',
      from: 'MoneyA',
      message: 'MoneyA: your code is 482916. Never share it with anyone.',
    });
  });

  it('supports form encoding, custom field names and static extras', async () => {
    const p = new HttpSmsProvider({
      url: `${base}/send`,
      format: 'form',
      fields: { to: 'recipients', message: 'text' },
      extra: { username: 'moneya' },
    });
    await p.sendOtp('+233201234567', '111222', 'fr');
    expect(seen[0]!.headers['content-type']).toBe('application/x-www-form-urlencoded');
    const form = new URLSearchParams(seen[0]!.body);
    expect(form.get('recipients')).toBe('+233201234567');
    expect(form.get('username')).toBe('moneya');
    expect(form.get('text')).toBe(otpMessage('111222', 'fr'));
    expect(otpMessage('111222', 'fr')).toContain('votre code');
  });

  it('non-2xx throws an error that leaks neither phone, code nor response body', async () => {
    status = 500;
    const p = new HttpSmsProvider({ url: `${base}/send` });
    const err = await p.sendOtp('+233201234567', '482916', 'fr').catch((e: Error) => e);
    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).not.toMatch(/233201234567|482916|secret/);
  });

  it('times out instead of hanging', async () => {
    const slow = createServer(() => undefined);
    await new Promise<void>((r) => slow.listen(0, '127.0.0.1', r));
    const url = `http://127.0.0.1:${(slow.address() as AddressInfo).port}/`;
    await expect(
      new HttpSmsProvider({ url, timeoutMs: 100 }).sendOtp('+233201234567', '1', 'fr'),
    ).rejects.toBeDefined();
    slow.closeAllConnections();
    await new Promise<void>((r) => slow.close(() => r()));
  });

  it('failover: falls through to the backup, fails only when all fail', async () => {
    const down = new HttpSmsProvider({ url: `${base}/down`, name: 'a' });
    const up = new HttpSmsProvider({ url: `${base}/ok`, name: 'b' });
    await new FailoverSmsProvider([down, up]).sendOtp('+233201234567', '482916', 'en');
    expect(seen).toHaveLength(2);
    await expect(
      new FailoverSmsProvider([down, down]).sendOtp('+233201234567', '482916', 'en'),
    ).rejects.toBeDefined();
    expect(() => new FailoverSmsProvider([])).toThrow();
  });

  describe('createSmsProvider', () => {
    const fake = new FakeSmsProvider();
    it('defaults to the fake outside production and refuses it in production', () => {
      expect(createSmsProvider({ NODE_ENV: 'development' }, fake)).toBe(fake);
      expect(() =>
        createSmsProvider({ NODE_ENV: 'production', SMS_PROVIDER: 'fake' }, fake),
      ).toThrow(/production/);
      expect(() => createSmsProvider({ NODE_ENV: 'production' }, fake)).toThrow();
    });
    it('builds the http chain from SMS_HTTP_CONFIGS and validates it', () => {
      const ok = JSON.stringify([
        { url: 'https://sms.example.com/send' },
        { url: 'https://backup.example.com/send' },
      ]);
      expect(
        createSmsProvider({ SMS_PROVIDER: 'http', SMS_HTTP_CONFIGS: ok }, fake),
      ).toBeInstanceOf(FailoverSmsProvider);
      for (const bad of [
        '',
        'nope',
        '[]',
        '[{"url":"http://insecure.example.com"}]',
        '[{"name":"x"}]',
      ]) {
        expect(() =>
          createSmsProvider({ SMS_PROVIDER: 'http', SMS_HTTP_CONFIGS: bad }, fake),
        ).toThrow();
      }
      expect(() => createSmsProvider({ SMS_PROVIDER: 'twilio' }, fake)).toThrow();
    });
  });
});

import { createRampProvider } from '../src/ramp/ramp.module';
describe('createRampProvider', () => {
  it('defaults to the simulator outside production and refuses everything in production', () => {
    expect(createRampProvider({ NODE_ENV: 'development' }).name).toBe('simulated');
    expect(() =>
      createRampProvider({ NODE_ENV: 'production', RAMP_PROVIDER: 'simulated' }),
    ).toThrow(/production/);
    expect(() => createRampProvider({ NODE_ENV: 'production' })).toThrow();
    expect(() => createRampProvider({ RAMP_PROVIDER: 'acme' })).toThrow();
  });
});
