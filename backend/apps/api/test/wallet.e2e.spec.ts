import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { LedgerService, templates } from '@moneya/ledger';
import type { SimulatedRampProvider } from '@moneya/ramp';
import { AppModule } from '../src/app.module';
import { AUTH_CONFIG, loadAuthConfig } from '../src/auth/auth.config';
import { FakeSmsProvider } from '../src/auth/sms.provider';
import { RAMP_PROVIDER } from '../src/ramp/ramp-orders.service';

const url = process.env.TEST_DATABASE_URL ?? process.env.LEDGER_TEST_DATABASE_URL;
const describeDb = url ? describe : describe.skip;

describeDb('wallet, profile and history (real PostgreSQL, response guard on)', () => {
  let app: INestApplication;
  let sms: FakeSmsProvider;
  let ledger: LedgerService;
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
    ledger = app.get(LedgerService);
    provider = app.get(RAMP_PROVIDER);
  });
  afterAll(async () => {
    await app.close();
    delete process.env.DATABASE_URL;
  });

  async function session(prefix = '+23324') {
    const phone = `${prefix}${String(randomInt(0, 10_000_000)).padStart(7, '0')}`;
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
    return { userId: t.user.id as string, phone, auth, stepUp };
  }
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
  const hook = async (
    ref: string,
    status: 'SUCCEEDED' | 'FAILED',
    kind: 'COLLECTION' | 'PAYOUT',
    orderId: string,
  ) => {
    const w = provider.resolve(ref, status);
    const raw = JSON.stringify({ ...JSON.parse(w.body), kind, orderId });
    await http()
      .post('/webhooks/ramp')
      .set(w.headers)
      .set('content-type', 'application/json')
      .send(raw)
      .expect(200);
  };
  async function topUp(s: Awaited<ReturnType<typeof session>>, amount: string, succeed = true) {
    const q = (
      await http()
        .post('/v1/onramp/quote')
        .set(s.auth)
        .send({ fiat_currency: 'GHS', fiat_amount: amount })
        .expect(200)
    ).body;
    const o = (
      await http()
        .post('/v1/onramp/orders')
        .set(s.auth)
        .set('Idempotency-Key', randomUUID())
        .set('X-Txn-Token', await s.stepUp())
        .send({ quote_id: q.id, payment_method: 'MTN_MOMO', payer_msisdn: '+233201234567' })
        .expect(202)
    ).body;
    if (succeed !== undefined)
      await hook(o.provider_reference, succeed ? 'SUCCEEDED' : 'FAILED', 'COLLECTION', o.id);
    return o.id as string;
  }

  it('GET /v1/users/me returns the profile; unauthenticated is 401', async () => {
    const s = await session();
    const me = (await http().get('/v1/users/me').set(s.auth).expect(200)).body;
    expect(me).toMatchObject({ id: s.userId, phone: s.phone, country: 'GH', kyc_tier: 'TIER_0' });
    await http().get('/v1/users/me').expect(401);
    await http().get('/v1/wallet').expect(401);
    await http().get('/v1/transfers').expect(401);
  });

  it('wallet: starts at 0 in the home currency, follows top-ups and cash-outs, nothing chain-related', async () => {
    const s = await session();
    const w0 = (await http().get('/v1/wallet').set(s.auth).expect(200)).body;
    expect(w0).toMatchObject({ provisioned: true, balance: '0', currency: 'GHS' });

    await topUp(s, '200'); // credited 197 (1.5% fee, rounded up)
    expect((await http().get('/v1/wallet').set(s.auth)).body.balance).toBe('197');

    const q = (
      await http()
        .post('/v1/offramp/quote')
        .set(s.auth)
        .send({ amount: '100', currency: 'GHS', payout_currency: 'GHS' })
        .expect(200)
    ).body;
    await http()
      .post('/v1/offramp/orders')
      .set(s.auth)
      .set('Idempotency-Key', randomUUID())
      .set('X-Txn-Token', await s.stepUp())
      .send({ quote_id: q.id, payout_method: 'MTN_MOMO', payee_msisdn: '+233201234567' })
      .expect(202);
    expect((await http().get('/v1/wallet').set(s.auth)).body.balance).toBe('97'); // 100 held immediately
  });

  it('a user in a country without a home currency yet is not provisioned', async () => {
    const s = await session('+1415'); // US number → no home currency yet
    const w = (await http().get('/v1/wallet').set(s.auth).expect(200)).body;
    expect(w).toMatchObject({ provisioned: false, balance: '0' });
  });

  it('history: newest first, mapped statuses/failure reasons, both directions, fiat-only, only your own', async () => {
    const [a, b] = [await session(), await session()];
    await fund(a.userId, '500');
    const ok = await topUp(a, '100');
    const declined = await topUp(a, '50', false);
    const q = (
      await http()
        .post('/v1/offramp/quote')
        .set(a.auth)
        .send({ amount: '100', currency: 'GHS', payout_currency: 'GHS' })
        .expect(200)
    ).body;
    const out = (
      await http()
        .post('/v1/offramp/orders')
        .set(a.auth)
        .set('Idempotency-Key', randomUUID())
        .set('X-Txn-Token', await a.stepUp())
        .send({ quote_id: q.id, payout_method: 'MTN_MOMO', payee_msisdn: '+233241112222' })
        .expect(202)
    ).body;
    await topUp(b, '70');

    const page = (await http().get('/v1/transfers').set(a.auth).expect(200)).body;
    expect(page.items.map((t: { id: string }) => t.id)).toEqual([out.id, declined, ok]);
    expect(page.has_more).toBe(false);
    const [offramp, failed, completed] = page.items;
    expect(offramp).toMatchObject({
      kind: 'OFFRAMP',
      status: 'PROCESSING',
      amount: '98.5',
      fee: '1.5',
      currency: 'GHS',
    });
    expect(offramp.recipient.phone).toBe('+233241112222');
    expect(offramp.sender.user_id).toBe(a.userId);
    expect(failed).toMatchObject({
      kind: 'ONRAMP',
      status: 'FAILED',
      failure_reason: 'PROVIDER_REJECTED',
    });
    expect(completed).toMatchObject({
      kind: 'ONRAMP',
      status: 'COMPLETED',
      amount: '98.5',
      failure_reason: null,
    });
    expect(completed.recipient.user_id).toBe(a.userId);
    expect(completed.completed_at).toBeTruthy();
    expect(JSON.stringify(page)).not.toMatch(/usdc|stablecoin|stellar|settlement/i);
    // never someone else's order
    expect(
      page.items.every(
        (t: { sender: { user_id: string | null }; recipient: { user_id: string | null } }) =>
          t.sender.user_id === a.userId || t.recipient.user_id === a.userId,
      ),
    ).toBe(true);
  });

  it('pagination by cursor and kind filter', async () => {
    const s = await session();
    for (let i = 0; i < 5; i++) await topUp(s, String(10 + i));
    const p1 = (await http().get('/v1/transfers?limit=2').set(s.auth).expect(200)).body;
    expect(p1.items).toHaveLength(2);
    expect(p1.has_more).toBe(true);
    const p2 = (
      await http()
        .get(`/v1/transfers?limit=2&cursor=${encodeURIComponent(p1.next_cursor)}`)
        .set(s.auth)
        .expect(200)
    ).body;
    const p3 = (
      await http()
        .get(`/v1/transfers?limit=2&cursor=${encodeURIComponent(p2.next_cursor)}`)
        .set(s.auth)
        .expect(200)
    ).body;
    const ids = [...p1.items, ...p2.items, ...p3.items].map((t: { id: string }) => t.id);
    expect(new Set(ids).size).toBe(5);
    expect(p3.has_more).toBe(false);
    expect(p3.next_cursor).toBeNull();
    expect(
      (await http().get('/v1/transfers?kind=OFFRAMP').set(s.auth).expect(200)).body.items,
    ).toHaveLength(0);
    expect(
      (await http().get('/v1/transfers?kind=ONRAMP').set(s.auth).expect(200)).body.items,
    ).toHaveLength(5);
  });

  it('validates query parameters', async () => {
    const s = await session();
    await http().get('/v1/transfers?limit=0').set(s.auth).expect(400);
    await http().get('/v1/transfers?limit=500').set(s.auth).expect(400);
    await http().get('/v1/transfers?kind=NOPE').set(s.auth).expect(400);
    await http().get('/v1/transfers?cursor=garbage').set(s.auth).expect(400);
  });
});
