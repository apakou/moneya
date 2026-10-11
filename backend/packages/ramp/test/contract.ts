import { randomUUID } from 'node:crypto';
import { RampError, type RampProvider, type RampRequest } from '../src';

/**
 * Behaviour every RampProvider adapter (simulated or real) must have. A real
 * adapter runs this against its sandbox with `phones` that trigger each outcome.
 */
export function rampProviderContract(
  make: () => RampProvider,
  phones: { success: string; failure: string },
): void {
  const req = (over: Partial<RampRequest> = {}): RampRequest => ({
    orderId: randomUUID(),
    currency: 'GHS',
    amount: '50.25',
    phone: phones.success,
    rail: 'MOBILE_MONEY',
    network: 'MTN',
    ...over,
  });

  it('creates a pending collection and settles it', async () => {
    const p = make();
    const op = await p.createCollection(req());
    expect(op.status).toBe('PENDING');
    expect(op.providerRef).toBeTruthy();
    const done = await p.getOperation(op.providerRef);
    expect(done.status).toBe('SUCCEEDED');
  });

  it('reports a generic failure reason, never provider text', async () => {
    const p = make();
    const op = await p.createPayout(req({ phone: phones.failure }));
    const done = await p.getOperation(op.providerRef);
    expect(done.status).toBe('FAILED');
    expect([
      'PROVIDER_REJECTED',
      'INSUFFICIENT_FUNDS',
      'TIMEOUT',
      'INVALID_ACCOUNT',
      'LIMIT_EXCEEDED',
    ]).toContain(done.failureReason);
  });

  it('is idempotent on orderId and rejects a reused id with different parameters', async () => {
    const p = make();
    const r = req();
    const a = await p.createPayout(r);
    const b = await p.createPayout(r);
    expect(b.providerRef).toBe(a.providerRef);
    await expect(p.createPayout({ ...r, amount: '51' })).rejects.toBeInstanceOf(RampError);
  });

  it('keeps collections and payouts for the same order separate', async () => {
    const p = make();
    const r = req();
    expect((await p.createCollection(r)).providerRef).not.toBe(
      (await p.createPayout(r)).providerRef,
    );
  });

  it('validates currency precision, phone and order id', async () => {
    const p = make();
    for (const bad of [
      req({ currency: 'XOF', amount: '100.5' }),
      req({ currency: 'GHS', amount: '1.234' }),
      req({ amount: '0' }),
      req({ amount: '-5' }),
      req({ amount: '1e3' }),
      req({ phone: '0201234567' }),
      req({ orderId: 'nope' }),
    ]) {
      await expect(p.createCollection(bad)).rejects.toMatchObject({ code: 'INVALID_REQUEST' });
    }
    await expect(
      p.createCollection(req({ currency: 'XOF', amount: '5000' })),
    ).resolves.toBeDefined();
  });

  it('unknown operation → NOT_FOUND', async () => {
    await expect(make().getOperation('nope')).rejects.toMatchObject({ code: 'NOT_FOUND' });
  });

  it('exposes no settlement-asset vocabulary in any returned object', async () => {
    const p = make();
    const op = await p.createCollection(req());
    expect(JSON.stringify([op, await p.getOperation(op.providerRef)])).not.toMatch(
      /usdc|stablecoin|stellar|solana|crypto|blockchain|wallet address/i,
    );
  });
}
