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

describeDb('ramp HTTP API (real PostgreSQL, full app, response guard on)', () => {
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
    await app.listen(0, '127.0.0.1'); // own the server: supertest would close a shared one after its first request batch
    sms = app.get(FakeSmsProvider);
    ledger = app.get(LedgerService);
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
    return { userId: t.user.id as string, auth, stepUp };
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
  const webhook = (
    providerRef: string,
    status: 'SUCCEEDED' | 'FAILED',
    kind: 'COLLECTION' | 'PAYOUT',
    orderId: string,
  ) => {
    const w = provider.resolve(providerRef, status);
    const body = JSON.parse(w.body);
    const raw = JSON.stringify({ ...body, kind, orderId });
    return { raw, headers: w.headers };
  };

  it('top-up end to end: quote → order (idempotent) → signed webhook → balance', async () => {
    const s = await session();
    const quote = (
      await http()
        .post('/v1/onramp/quote')
        .set(s.auth)
        .send({ fiat_currency: 'GHS', fiat_amount: '200' })
        .expect(200)
    ).body;
    expect(quote).toMatchObject({
      kind: 'ONRAMP',
      from_currency: 'GHS',
      from_amount: '200',
      to_amount: '197',
      fee: '3',
      rate: '1',
    });
    expect(JSON.stringify(quote)).not.toMatch(/usdc|settlement/i);

    const key = randomUUID();
    const body = { quote_id: quote.id, payment_method: 'MTN_MOMO', payer_msisdn: '+233201234567' };
    await http()
      .post('/v1/onramp/orders')
      .set(s.auth)
      .set('Idempotency-Key', key)
      .send(body)
      .expect(401); // no step-up token
    const create = (token: string) =>
      http()
        .post('/v1/onramp/orders')
        .set(s.auth)
        .set('Idempotency-Key', key)
        .set('X-Txn-Token', token)
        .send(body);
    const first = await create(await s.stepUp()).expect(202);
    expect(first.body.status).toBe('AWAITING_PAYMENT');

    // lost-response retry: same key, no valid token needed, identical result, no second order
    const replay = await create('already-used-or-garbage').expect(202);
    expect(replay.body.id).toBe(first.body.id);
    // same key, different body → 422
    await http()
      .post('/v1/onramp/orders')
      .set(s.auth)
      .set('Idempotency-Key', key)
      .set('X-Txn-Token', await s.stepUp())
      .send({ ...body, payer_msisdn: '+233201234999' })
      .expect(422);

    const wh = webhook(first.body.provider_reference, 'SUCCEEDED', 'COLLECTION', first.body.id);
    await http()
      .post('/webhooks/ramp')
      .set(wh.headers)
      .set('content-type', 'application/json')
      .send(wh.raw)
      .expect(200);
    await http()
      .post('/webhooks/ramp')
      .set(wh.headers)
      .set('content-type', 'application/json')
      .send(wh.raw)
      .expect(200); // duplicate delivery

    const done = (await http().get(`/v1/onramp/orders/${first.body.id}`).set(s.auth).expect(200))
      .body;
    expect(done.status).toBe('COMPLETED');
    expect(await ledger.getUserBalance(s.userId, 'GHS')).toBe('197');
  });

  it('webhooks: a bad signature or tampered body is rejected and changes nothing', async () => {
    const s = await session();
    const quote = (
      await http()
        .post('/v1/onramp/quote')
        .set(s.auth)
        .send({ fiat_currency: 'GHS', fiat_amount: '100' })
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
    const wh = webhook(order.provider_reference, 'SUCCEEDED', 'COLLECTION', order.id);
    await http()
      .post('/webhooks/ramp')
      .set({ ...wh.headers, 'x-ramp-signature': '00'.repeat(32) })
      .set('content-type', 'application/json')
      .send(wh.raw)
      .expect(400);
    await http()
      .post('/webhooks/ramp')
      .set(wh.headers)
      .set('content-type', 'application/json')
      .send(wh.raw.replace('SUCCEEDED', 'FAILED'))
      .expect(400);
    await http().post('/webhooks/ramp').send({}).expect(400);
    expect((await http().get(`/v1/onramp/orders/${order.id}`).set(s.auth)).body.status).toBe(
      'AWAITING_PAYMENT',
    );
  });

  it('cash-out end to end: 402 without funds, debit, signed webhook settles, refund path restores', async () => {
    const s = await session();
    const q0 = (
      await http()
        .post('/v1/offramp/quote')
        .set(s.auth)
        .send({ amount: '100', currency: 'GHS', payout_currency: 'GHS' })
        .expect(200)
    ).body;
    const place = async (quoteId: string, over: object = {}) =>
      http()
        .post('/v1/offramp/orders')
        .set(s.auth)
        .set('Idempotency-Key', randomUUID())
        .set('X-Txn-Token', await s.stepUp())
        .send({
          quote_id: quoteId,
          payout_method: 'MTN_MOMO',
          payee_msisdn: '+233201234567',
          ...over,
        });
    const broke = await place(q0.id);
    expect(broke.status).toBe(402);
    expect(broke.body.code).toBe('INSUFFICIENT_FUNDS');
    expect(broke.headers['content-type']).toMatch(/problem\+json/);

    await fund(s.userId, '500');
    const ok = (await place(q0.id)).body; // the same quote still works: it was not burnt
    expect(ok.status).toBe('PROCESSING');
    expect(await ledger.getUserBalance(s.userId, 'GHS')).toBe('400');
    const settled = webhook(ok.provider_reference, 'SUCCEEDED', 'PAYOUT', ok.id);
    await http()
      .post('/webhooks/ramp')
      .set(settled.headers)
      .set('content-type', 'application/json')
      .send(settled.raw)
      .expect(200);
    expect((await http().get(`/v1/offramp/orders/${ok.id}`).set(s.auth)).body.status).toBe(
      'SETTLED',
    );
    expect(await ledger.getUserBalance(s.userId, 'GHS')).toBe('400');

    const q1 = (
      await http()
        .post('/v1/offramp/quote')
        .set(s.auth)
        .send({ amount: '50', currency: 'GHS', payout_currency: 'GHS' })
        .expect(200)
    ).body;
    const failing = (await place(q1.id)).body;
    expect(await ledger.getUserBalance(s.userId, 'GHS')).toBe('350');
    const failed = webhook(failing.provider_reference, 'FAILED', 'PAYOUT', failing.id);
    await http()
      .post('/webhooks/ramp')
      .set(failed.headers)
      .set('content-type', 'application/json')
      .send(failed.raw)
      .expect(200);
    expect((await http().get(`/v1/offramp/orders/${failing.id}`).set(s.auth)).body).toMatchObject({
      status: 'REFUNDED',
      failure_reason: 'PROVIDER_REJECTED',
    });
    expect(await ledger.getUserBalance(s.userId, 'GHS')).toBe('400');
  });

  it('access control and validation', async () => {
    const [a, b] = [await session(), await session()];
    await http()
      .post('/v1/onramp/quote')
      .send({ fiat_currency: 'GHS', fiat_amount: '10' })
      .expect(401);
    await http()
      .post('/v1/onramp/quote')
      .set(a.auth)
      .send({ fiat_currency: 'EUR', fiat_amount: '10' })
      .expect(400);
    await http()
      .post('/v1/onramp/quote')
      .set(a.auth)
      .send({ fiat_currency: 'GHS', fiat_amount: '-5' })
      .expect(400);
    await http()
      .post('/v1/onramp/quote')
      .set(a.auth)
      .send({ fiat_currency: 'GHS', fiat_amount: '0.01' })
      .expect(400); // dust
    // precision: a currency's own decimals only (GHS 2, XOF 0)
    const quote = (path: string, body: object) => http().post(path).set(a.auth).send(body);
    await quote('/v1/onramp/quote', { fiat_currency: 'GHS', fiat_amount: '10.123' }).expect(400);
    await quote('/v1/onramp/quote', { fiat_currency: 'XOF', fiat_amount: '1000.5' }).expect(400);
    await quote('/v1/offramp/quote', {
      amount: '10.123',
      currency: 'GHS',
      payout_currency: 'GHS',
    }).expect(400);
    await quote('/v1/onramp/quote', { fiat_currency: 'XOF', fiat_amount: '1000' }).expect(200);
    await quote('/v1/onramp/quote', { fiat_currency: 'GHS', fiat_amount: '10.12' }).expect(200);
    const q = (
      await http()
        .post('/v1/onramp/quote')
        .set(a.auth)
        .send({ fiat_currency: 'GHS', fiat_amount: '100' })
        .expect(200)
    ).body;
    const stolen = await http()
      .post('/v1/onramp/orders')
      .set(b.auth)
      .set('Idempotency-Key', randomUUID())
      .set('X-Txn-Token', await b.stepUp())
      .send({ quote_id: q.id, payment_method: 'MTN_MOMO', payer_msisdn: '+233201234567' });
    expect(stolen.status).toBe(404);
    await http()
      .post('/v1/onramp/orders')
      .set(a.auth)
      .set('X-Txn-Token', await a.stepUp())
      .send({})
      .expect(400); // Idempotency-Key required
    await http().get('/v1/onramp/orders/not-a-uuid').set(a.auth).expect(404);
    await http().get(`/v1/onramp/orders/${randomUUID()}`).set(a.auth).expect(404);
  });
});
