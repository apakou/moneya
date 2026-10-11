import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import type { SimulatedRampProvider } from '@moneya/ramp';
import { AppModule } from '../src/app.module';
import { AUTH_CONFIG, loadAuthConfig } from '../src/auth/auth.config';
import { FakeSmsProvider } from '../src/auth/sms.provider';
import { RAMP_PROVIDER } from '../src/ramp/ramp-orders.service';

const url = process.env.TEST_DATABASE_URL ?? process.env.LEDGER_TEST_DATABASE_URL;
const describeDb = url ? describe : describe.skip;

describeDb('account HTTP API: profile, balance, transactions (real PostgreSQL)', () => {
  let app: INestApplication;
  let sms: FakeSmsProvider;
  let provider: SimulatedRampProvider;
  const http = () => request(app.getHttpServer());
  const DEVICE = '3f8c1d2e-5a4b-4c6d-8e7f-0a1b2c3d4e5f';

  beforeAll(async () => {
    process.env.DATABASE_URL = url;
    const mod = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(AUTH_CONFIG)
      .useValue({ ...loadAuthConfig(), argon2: { memoryCost: 1024, timeCost: 2, parallelism: 1 } })
      .compile();
    app = mod.createNestApplication({ logger: false, rawBody: true });
    await app.listen(0, '127.0.0.1');
    sms = app.get(FakeSmsProvider);
    provider = app.get(RAMP_PROVIDER);
  });
  afterAll(async () => {
    await app.close();
    delete process.env.DATABASE_URL;
  });

  async function session() {
    const phone = `+23324${String(randomInt(0, 10_000_000)).padStart(7, '0')}`;
    await http().post('/v1/auth/otp').send({ phone }).expect(202);
    const t = (
      await http()
        .post('/v1/auth/otp/verify')
        .send({ phone, code: sms.lastCode(phone), device_id: DEVICE })
        .expect(200)
    ).body;
    const auth = { Authorization: `Bearer ${t.access_token}` };
    await http().post('/v1/auth/passcode').set(auth).send({ passcode: '482916' }).expect(204);
    const stepUp = async () =>
      (await http().post('/v1/auth/step-up').set(auth).send({ passcode: '482916' }).expect(200))
        .body.txn_token as string;
    return { phone, userId: t.user.id as string, auth, stepUp };
  }

  async function topUp(s: Awaited<ReturnType<typeof session>>, amount: string, settle: boolean) {
    const quote = (
      await http()
        .post('/v1/onramp/quote')
        .set(s.auth)
        .send({ fiat_currency: 'GHS', fiat_amount: amount })
        .expect(200)
    ).body;
    const order = (
      await http()
        .post('/v1/onramp/orders')
        .set(s.auth)
        .set('Idempotency-Key', randomUUID())
        .set('X-Txn-Token', await s.stepUp())
        .send({ quote_id: quote.id, payment_method: 'MTN_MOMO', payer_msisdn: '+233201234567' })
        .expect(202)
    ).body;
    if (settle) {
      const w = provider.resolve(order.provider_reference, 'SUCCEEDED');
      const raw = JSON.stringify({ ...JSON.parse(w.body), kind: 'COLLECTION', orderId: order.id });
      await http()
        .post('/webhooks/ramp')
        .set(w.headers)
        .set('content-type', 'application/json')
        .send(raw)
        .expect(200);
    }
    return order.id as string;
  }

  it('requires authentication on every account endpoint', async () => {
    for (const path of ['/v1/users/me', '/v1/wallet', '/v1/transactions']) {
      await http().get(path).expect(401);
    }
  });

  it('users/me returns the signed-in user', async () => {
    const s = await session();
    const me = (await http().get('/v1/users/me').set(s.auth).expect(200)).body;
    expect(me).toMatchObject({
      id: s.userId,
      phone: s.phone,
      country: 'GH',
      full_name: null,
      photo_url: null,
      kyc_tier: 'TIER_0',
    });
    expect(typeof me.created_at).toBe('string');
  });

  it('wallet: zero for a new user, the credited amount after a top-up, per currency', async () => {
    const s = await session();
    const empty = (await http().get('/v1/wallet').set(s.auth).expect(200)).body;
    expect(empty).toMatchObject({
      currency: 'GHS',
      balance: '0',
      available_balance: '0',
      equivalent_balance: '0',
    });

    await topUp(s, '200', true);
    const funded = (await http().get('/v1/wallet').set(s.auth).expect(200)).body;
    expect(funded).toMatchObject({
      currency: 'GHS',
      balance: '197',
      available_balance: '197',
      equivalent_balance: '197',
    });
    expect(JSON.stringify(funded)).not.toMatch(/usdc|stellar|chain/i);

    const other = (await http().get('/v1/wallet?currency=XOF').set(s.auth).expect(200)).body;
    // nothing is held in XOF, but the GHS holding is worth 197 × 600 / 15.5 = 7625.8… XOF (rounded down)
    expect(other).toMatchObject({
      currency: 'XOF',
      balance: '0',
      available_balance: '0',
      equivalent_balance: '7625',
    });
    await http().get('/v1/wallet?currency=USD').set(s.auth).expect(400);
  });

  it('transactions: newest first, statuses mapped, keyset pagination, user-scoped', async () => {
    const s = await session();
    const settled = await topUp(s, '200', true);
    const pending = await topUp(s, '100', false);

    const all = (await http().get('/v1/transactions').set(s.auth).expect(200)).body;
    expect(all.next_cursor).toBeNull();
    expect(all.items.map((t: { id: string }) => t.id)).toEqual([pending, settled]);
    expect(all.items[0]).toMatchObject({
      kind: 'TOP_UP',
      status: 'PENDING',
      amount: '98.5',
      currency: 'GHS',
      payment_method: 'MTN_MOMO',
      counterparty_phone: '+233201234567',
      completed_at: null,
    });
    expect(all.items[1]).toMatchObject({
      kind: 'TOP_UP',
      status: 'COMPLETED',
      amount: '197',
      fee: '3',
    });
    expect(all.items[1].completed_at).not.toBeNull();
    expect(JSON.stringify(all)).not.toMatch(/usdc|stellar|chain/i);

    const p1 = (await http().get('/v1/transactions?limit=1').set(s.auth).expect(200)).body;
    expect(p1.items).toHaveLength(1);
    expect(p1.next_cursor).toEqual(expect.any(String));
    const p2 = (
      await http()
        .get('/v1/transactions')
        .query({ limit: 1, cursor: p1.next_cursor })
        .set(s.auth)
        .expect(200)
    ).body;
    expect(p2.items.map((t: { id: string }) => t.id)).toEqual([settled]);
    expect(p2.next_cursor).toBeNull();

    const stranger = await session();
    const theirs = (await http().get('/v1/transactions').set(stranger.auth).expect(200)).body;
    expect(theirs).toEqual({ items: [], next_cursor: null });

    await http().get('/v1/transactions?limit=0').set(s.auth).expect(400);
    await http().get('/v1/transactions?cursor=garbage').set(s.auth).expect(400);
  });
});
