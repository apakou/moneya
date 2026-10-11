import { randomInt, randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { LedgerService, templates } from '@moneya/ledger';
import { SimulatedRampProvider, type RampEvent } from '@moneya/ramp';
import { SimulatedSettlement } from '../src/ramp/ramp.module';
import { priceOfframp, priceOnramp } from '../src/ramp/pricing';
import { RampOrdersService } from '../src/ramp/ramp-orders.service';

const pricing = {
  rates: { GHS: '15.5', XOF: '600', XAF: '600', NGN: '1500', KES: '129' },
  feeBps: 150,
} as const;

describe('quote math', () => {
  it('top-up: fee rounds UP to the fiat precision, user gets the rest, settlement rounds DOWN', () => {
    const q = priceOnramp(pricing, 'GHS', '100');
    expect(q).toMatchObject({
      fromAmount: '100',
      toAmount: '98.5',
      fee: '1.5',
      rate: '1',
      fromCurrency: 'GHS',
      toCurrency: 'GHS',
    });
    expect(q.settlementAmount).toBe('6.451612'); // 100 / 15.5 = 6.4516129…
    const xof = priceOnramp(pricing, 'XOF', '5000');
    expect(xof.fee).toBe('75'); // 0 dp currency: whole francs only
    expect(priceOnramp(pricing, 'GHS', '0.5').fee).toBe('0.01'); // 0.0075 → rounded up to a cent
  });
  it('cash-out same currency: payee gets exactly amount − fee; cross-currency goes through the settlement unit', () => {
    const same = priceOfframp(pricing, 'GHS', 'GHS', '100');
    expect(same).toMatchObject({ toAmount: '98.5', rate: '1' });
    const cross = priceOfframp(pricing, 'GHS', 'XOF', '100');
    expect(cross.toCurrency).toBe('XOF');
    expect(cross.toAmount).toBe('3812'); // 98.5/15.5 USD-unit × 600 = 3812.9… → floor, 0 dp
    expect(Number(cross.rate)).toBeCloseTo(38.12, 2);
  });
  it('rejects dust and unknown currencies', () => {
    expect(() => priceOnramp(pricing, 'GHS', '0.01')).toThrow(RangeError);
    expect(() => priceOnramp({ rates: {}, feeBps: 150 }, 'GHS', '100')).toThrow();
  });
});

const url = process.env.TEST_DATABASE_URL ?? process.env.LEDGER_TEST_DATABASE_URL;
const testSsl = process.env.DATABASE_CA_CERT
  ? { ca: process.env.DATABASE_CA_CERT, rejectUnauthorized: true }
  : undefined;
const describeDb = url ? describe : describe.skip;

describeDb('ramp orders on PostgreSQL (simulated provider)', () => {
  let pool: Pool;
  let ledger: LedgerService;
  let provider: SimulatedRampProvider;
  let svc: RampOrdersService;

  beforeAll(() => {
    pool = new Pool({ connectionString: url, max: 10, ssl: testSsl });
    ledger = new LedgerService(pool);
  });
  afterAll(() => pool.end());
  beforeEach(() => {
    provider = new SimulatedRampProvider({ webhookSecret: 'x'.repeat(32), autoSettle: false });
    svc = new RampOrdersService(pool, ledger, provider, pricing, new SimulatedSettlement());
  });

  const user = async () =>
    (
      await pool.query<{ id: string }>(
        `INSERT INTO app.users (phone, country) VALUES ($1,'GH') RETURNING id`,
        [`+2332${String(randomInt(0, 1e8)).padStart(8, '0')}`],
      )
    ).rows[0]!.id;
  const fund = (userId: string, amount: string) =>
    ledger.postJournal(
      templates.reconciliationAdjustment({
        incidentId: randomUUID(),
        userId,
        currency: 'GHS',
        delta: amount,
        memo: 'test funding',
      }),
    );
  const bal = (userId: string) => ledger.getUserBalance(userId, 'GHS');
  const OK_PHONE = '+233201234567';
  const event = (
    providerRef: string,
    status: 'SUCCEEDED' | 'FAILED',
    kind: 'COLLECTION' | 'PAYOUT',
    orderId: string,
    reason?: 'TIMEOUT',
  ): RampEvent => {
    const wh = provider.resolve(providerRef, status, reason);
    return { ...provider.parseWebhook(wh.headers, wh.body), kind, orderId }; // goes through signature verification
  };
  const imbalance = async () => (await pool.query('SELECT 1 FROM app.v_ledger_imbalance')).rowCount;

  describe('top-up', () => {
    async function start(u: string, amount = '100') {
      const q = await svc.quoteOnramp(u, 'GHS', amount);
      const o = await svc.createOnramp(u, {
        quote_id: q.id,
        payment_method: 'MTN_MOMO',
        payer_msisdn: OK_PHONE,
      });
      return { q, o };
    }

    it('collected → settled → user credited net of fee, exactly once', async () => {
      const u = await user();
      const { o } = await start(u);
      expect(o.status).toBe('AWAITING_PAYMENT');
      expect(o.ussd_instructions).toBeTruthy();
      expect(o.quote).toMatchObject({
        from_amount: '100',
        to_amount: '98.5',
        fee: '1.5',
        rate: '1',
      });
      expect(await bal(u)).toBe('0'); // nothing posted before settlement

      const ev = event(o.provider_reference!, 'SUCCEEDED', 'COLLECTION', o.id);
      await svc.handleCollectionEvent(ev);
      expect(await bal(u)).toBe('98.5');
      expect((await svc.getOnramp(u, o.id)).status).toBe('COMPLETED');

      await svc.handleCollectionEvent(ev); // replayed webhook
      await svc.completeOnramp(o.id, '6.451612'); // replayed settlement
      expect(await bal(u)).toBe('98.5');
      expect(await imbalance()).toBe(0);
    });

    it('declined payment → FAILED with a generic reason and no ledger movement', async () => {
      const u = await user();
      const { o } = await start(u);
      await svc.handleCollectionEvent(
        event(o.provider_reference!, 'FAILED', 'COLLECTION', o.id, 'TIMEOUT'),
      );
      const after = await svc.getOnramp(u, o.id);
      expect(after).toMatchObject({ status: 'FAILED', failure_reason: 'PROVIDER_TIMEOUT' });
      expect(await bal(u)).toBe('0');
    });

    it('a quote is single-use and bound to its owner; expired quotes are refused', async () => {
      const [a, b] = [await user(), await user()];
      const q = await svc.quoteOnramp(a, 'GHS', '50');
      await expect(
        svc.createOnramp(b, { quote_id: q.id, payment_method: 'MTN_MOMO', payer_msisdn: OK_PHONE }),
      ).rejects.toMatchObject({ code: 'NOT_FOUND' });
      await svc.createOnramp(a, {
        quote_id: q.id,
        payment_method: 'MTN_MOMO',
        payer_msisdn: OK_PHONE,
      });
      await expect(
        svc.createOnramp(a, { quote_id: q.id, payment_method: 'MTN_MOMO', payer_msisdn: OK_PHONE }),
      ).rejects.toMatchObject({ code: 'QUOTE_EXPIRED' });
      const q2 = await svc.quoteOnramp(a, 'GHS', '50');
      await pool.query(
        `UPDATE app.quotes SET expires_at = now() - interval '1 second' WHERE id = $1`,
        [q2.id],
      );
      await expect(
        svc.createOnramp(a, {
          quote_id: q2.id,
          payment_method: 'MTN_MOMO',
          payer_msisdn: OK_PHONE,
        }),
      ).rejects.toMatchObject({ code: 'QUOTE_EXPIRED' });
    });

    it('only the owner can read an order', async () => {
      const [a, b] = [await user(), await user()];
      const { o } = await start(a);
      await expect(svc.getOnramp(b, o.id)).rejects.toMatchObject({ code: 'NOT_FOUND' });
    });
  });

  describe('cash-out', () => {
    async function start(u: string, amount = '100', payee = OK_PHONE) {
      const q = await svc.quoteOfframp(u, amount, 'GHS', 'GHS');
      const o = await svc.createOfframp(u, {
        quote_id: q.id,
        payout_method: 'MTN_MOMO',
        payee_msisdn: payee,
        payee_name: 'Ama',
      });
      return { q, o };
    }
    const feeRev = async () =>
      Number(
        (
          await pool.query(
            `SELECT COALESCE(SUM(e.amount_usdc),0)::text s FROM app.ledger_entries e JOIN app.ledger_accounts a ON a.id=e.account_id WHERE a.kind='FEE_REVENUE' AND a.currency='GHS'`,
          )
        ).rows[0].s,
      );
    const suspenseFor = async (orderId: string) =>
      Number(
        (
          await pool.query(
            `SELECT COALESCE(SUM(e.amount_usdc),0)::text s FROM app.ledger_entries e JOIN app.ledger_accounts a ON a.id=e.account_id WHERE a.kind='SUSPENSE' AND e.ref_id=$1`,
            [orderId],
          )
        ).rows[0].s,
      );

    it('debits on request, settles on payout success, earns the fee once', async () => {
      const u = await user();
      await fund(u, '300');
      const fee0 = await feeRev();
      const { o } = await start(u);
      expect(o.status).toBe('PROCESSING');
      expect(o.quote).toMatchObject({ from_amount: '100', to_amount: '98.5', fee: '1.5' });
      expect(await bal(u)).toBe('200');

      const ev = event(o.provider_reference!, 'SUCCEEDED', 'PAYOUT', o.id);
      await svc.handlePayoutEvent(ev);
      await svc.handlePayoutEvent(ev); // replay
      expect((await svc.getOfframp(u, o.id)).status).toBe('SETTLED');
      expect(await bal(u)).toBe('200');
      expect(await suspenseFor(o.id)).toBe(0);
      expect(+((await feeRev()) - fee0).toFixed(6)).toBe(1.5);
      expect(await imbalance()).toBe(0);
    });

    it('failed payout → full refund once; a late success afterwards is ignored', async () => {
      const u = await user();
      await fund(u, '300');
      const { o } = await start(u);
      expect(await bal(u)).toBe('200');
      const fail = event(o.provider_reference!, 'FAILED', 'PAYOUT', o.id);
      await svc.handlePayoutEvent(fail);
      await svc.handlePayoutEvent(fail);
      expect(await bal(u)).toBe('300');
      expect(await svc.getOfframp(u, o.id)).toMatchObject({
        status: 'REFUNDED',
        failure_reason: 'PROVIDER_REJECTED',
      });
      await svc.handlePayoutEvent({
        ...fail,
        eventId: 'late',
        status: 'SUCCEEDED',
        failureReason: undefined,
      });
      expect(await bal(u)).toBe('300');
      expect(await suspenseFor(o.id)).toBe(0);
    });

    it('insufficient balance → 402, nothing debited, the quote is NOT burnt', async () => {
      const u = await user();
      await fund(u, '50');
      const q = await svc.quoteOfframp(u, '100', 'GHS', 'GHS');
      await expect(
        svc.createOfframp(u, { quote_id: q.id, payout_method: 'MTN_MOMO', payee_msisdn: OK_PHONE }),
      ).rejects.toMatchObject({ status: 402, code: 'INSUFFICIENT_FUNDS' });
      expect(await bal(u)).toBe('50');
      expect(
        (await pool.query('SELECT consumed_at FROM app.quotes WHERE id=$1', [q.id])).rows[0]
          .consumed_at,
      ).toBeNull();
      await fund(u, '60');
      await svc.createOfframp(u, {
        quote_id: q.id,
        payout_method: 'MTN_MOMO',
        payee_msisdn: OK_PHONE,
      }); // same quote now works
      expect(await bal(u)).toBe('10');
    });

    it('concurrent cash-outs cannot overdraw: 5 × 100 against 250 → exactly 2 succeed', async () => {
      const u = await user();
      await fund(u, '250');
      const quotes = await Promise.all(
        Array.from({ length: 5 }, () => svc.quoteOfframp(u, '100', 'GHS', 'GHS')),
      );
      const res = await Promise.allSettled(
        quotes.map((q) =>
          svc.createOfframp(u, {
            quote_id: q.id,
            payout_method: 'MTN_MOMO',
            payee_msisdn: OK_PHONE,
          }),
        ),
      );
      expect(res.filter((r) => r.status === 'fulfilled')).toHaveLength(2);
      expect(await bal(u)).toBe('50');
    });

    it('invalid payee phone is rejected before any money moves', async () => {
      const u = await user();
      await fund(u, '100');
      const q = await svc.quoteOfframp(u, '100', 'GHS', 'GHS');
      await expect(
        svc.createOfframp(u, {
          quote_id: q.id,
          payout_method: 'MTN_MOMO',
          payee_msisdn: '0201234567',
        }),
      ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
      expect(await bal(u)).toBe('100');
    });
  });

  it('syncPending polls the provider when webhooks are lost', async () => {
    const auto = new SimulatedRampProvider({ webhookSecret: 'y'.repeat(32), autoSettle: true });
    const s = new RampOrdersService(pool, ledger, auto, pricing, new SimulatedSettlement());
    const u = await user();
    const q = await s.quoteOnramp(u, 'GHS', '100');
    const o = await s.createOnramp(u, {
      quote_id: q.id,
      payment_method: 'MTN_MOMO',
      payer_msisdn: OK_PHONE,
    });
    await pool.query(
      `UPDATE app.onramp_orders SET next_action_at = now() - interval '1 second' WHERE id=$1`,
      [o.id],
    );
    // an order this provider has never heard of (foreign ref) must not stop the batch
    const ghostUser = await user();
    const gq = await s.quoteOnramp(ghostUser, 'GHS', '100');
    const ghost = await s.createOnramp(ghostUser, {
      quote_id: gq.id,
      payment_method: 'MTN_MOMO',
      payer_msisdn: OK_PHONE,
    });
    await pool.query(
      `UPDATE app.onramp_orders SET yc_order_id = $2, next_action_at = now() - interval '1 hour' WHERE id = $1`,
      [ghost.id, `ghost-${randomUUID()}`],
    );
    expect(await s.syncPending()).toBeGreaterThanOrEqual(1);
    expect((await s.getOnramp(u, o.id)).status).toBe('COMPLETED');
    expect(await ledger.getUserBalance(u, 'GHS')).toBe('98.5');
    expect((await s.getOnramp(ghostUser, ghost.id)).status).toBe('AWAITING_PAYMENT'); // skipped, not failed
  });
});
