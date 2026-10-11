import { randomUUID } from 'node:crypto';
import { RampError, SimulatedRampProvider } from '../src';
import { rampProviderContract } from './contract';

const make = (opts: { autoSettle?: boolean; now?: () => Date } = {}) =>
  new SimulatedRampProvider({ webhookSecret: 'test-secret-0123456789', ...opts });
const base = { currency: 'GHS' as const, amount: '10', rail: 'MOBILE_MONEY' as const };

describe('SimulatedRampProvider', () => {
  describe('provider contract', () => {
    rampProviderContract(() => make(), { success: '+233201234567', failure: '+233201230000' });
  });

  it('stays pending for the 1111 suffix and for autoSettle=false until resolved', async () => {
    const p = make();
    const op = await p.createCollection({ ...base, orderId: randomUUID(), phone: '+233201231111' });
    expect((await p.getOperation(op.providerRef)).status).toBe('PENDING');

    const manual = make({ autoSettle: false });
    const m = await manual.createPayout({ ...base, orderId: randomUUID(), phone: '+233201234567' });
    expect((await manual.getOperation(m.providerRef)).status).toBe('PENDING');
    manual.resolve(m.providerRef, 'SUCCEEDED');
    expect((await manual.getOperation(m.providerRef)).status).toBe('SUCCEEDED');
  });

  it('terminal states never change', async () => {
    const p = make({ autoSettle: false });
    const op = await p.createPayout({ ...base, orderId: randomUUID(), phone: '+233201234567' });
    p.resolve(op.providerRef, 'FAILED', 'TIMEOUT');
    p.resolve(op.providerRef, 'SUCCEEDED');
    expect(await p.getOperation(op.providerRef)).toMatchObject({
      status: 'FAILED',
      failureReason: 'TIMEOUT',
    });
  });

  describe('webhooks', () => {
    it('round-trips a signed event', async () => {
      const p = make({ autoSettle: false });
      const orderId = randomUUID();
      const op = await p.createCollection({ ...base, orderId, phone: '+233201234567' });
      const { headers, body } = p.resolve(op.providerRef, 'SUCCEEDED');
      expect(p.parseWebhook(headers, body)).toMatchObject({
        kind: 'COLLECTION',
        orderId,
        status: 'SUCCEEDED',
        providerRef: op.providerRef,
      });
    });

    it('rejects a tampered body, a wrong secret, missing headers and stale timestamps', async () => {
      const p = make({ autoSettle: false });
      const op = await p.createCollection({
        ...base,
        orderId: randomUUID(),
        phone: '+233201234567',
      });
      const { headers, body } = p.resolve(op.providerRef, 'SUCCEEDED');
      const code = (fn: () => unknown) => {
        try {
          fn();
        } catch (e) {
          return (e as RampError).code;
        }
        return 'no error';
      };
      expect(code(() => p.parseWebhook(headers, body.replace('SUCCEEDED', 'FAILED')))).toBe(
        'INVALID_SIGNATURE',
      );
      expect(
        code(() =>
          new SimulatedRampProvider({ webhookSecret: 'another-secret-0123456789' }).parseWebhook(
            headers,
            body,
          ),
        ),
      ).toBe('INVALID_SIGNATURE');
      expect(code(() => p.parseWebhook({}, body))).toBe('INVALID_SIGNATURE');
      const later = make({ now: () => new Date(Date.now() + 10 * 60_000) });
      expect(code(() => later.parseWebhook(headers, body))).toBe('INVALID_SIGNATURE');
    });
  });
});
