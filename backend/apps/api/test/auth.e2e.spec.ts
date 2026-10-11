import { Controller, INestApplication, Module, Post, UseGuards } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomInt } from 'node:crypto';
import { AUTH_STORE } from '../src/auth/auth.store';
import { PgAuthStore } from '../src/auth/pg-auth.store';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthModule } from '../src/auth/auth.module';
import { AUTH_CONFIG, loadAuthConfig } from '../src/auth/auth.config';
import { AuthGuard, TxnTokenGuard } from '../src/auth/auth.guard';
import { FakeSmsProvider } from '../src/auth/sms.provider';

@Controller('probe')
class MoneyProbe {
  @Post('pay')
  @UseGuards(AuthGuard, TxnTokenGuard)
  pay() {
    return { status: 'COMPLETED' };
  }
}

@Module({ imports: [AuthModule], controllers: [MoneyProbe] })
class ProbeModule {}

let PHONE = '+22890123456';
const DEVICE = '3f8c1d2e-5a4b-4c6d-8e7f-0a1b2c3d4e5f';
const OTHER_DEVICE = '9b2e7a10-1c3d-4e5f-8a6b-7c8d9e0f1a2b';

const dbUrl = process.env.TEST_DATABASE_URL ?? process.env.LEDGER_TEST_DATABASE_URL;

// The same suite runs on the in-memory store always, and on PostgreSQL when a database is provided.
const stores: [string, string | undefined][] = [['in-memory store', undefined]];
if (dbUrl) stores.push(['PostgreSQL store', dbUrl]);

describe.each(stores)('auth (M1) — %s', (_label, url) => {
  let app: INestApplication;
  let sms: FakeSmsProvider;
  const http = () => request(app.getHttpServer());

  beforeEach(async () => {
    PHONE = `+22890${String(randomInt(0, 1_000_000)).padStart(6, '0')}`; // fresh user per test
    let builder = Test.createTestingModule({ imports: [AppModule, ProbeModule] });
    if (url) builder = builder.overrideProvider(AUTH_STORE).useValue(PgAuthStore.fromUrl(url));
    const mod = await builder
      .overrideProvider(AUTH_CONFIG)
      .useValue({ ...loadAuthConfig(), argon2: { memoryCost: 1024, timeCost: 2, parallelism: 1 } })
      .compile();
    app = mod.createNestApplication({ logger: false });
    await app.init();
    sms = app.get(FakeSmsProvider);
  });
  afterEach(() => app.close());

  async function login(phone = PHONE, device = DEVICE) {
    await http().post('/v1/auth/otp').send({ phone }).expect(202);
    const res = await http()
      .post('/v1/auth/otp/verify')
      .send({ phone, code: sms.lastCode(phone), device_id: device })
      .expect(200);
    return res.body as {
      access_token: string;
      refresh_token: string;
      expires_in: number;
      user: { id: string; phone: string; kyc_tier: string };
    };
  }
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

  describe('OTP', () => {
    it('sends a code and returns a masked destination, never the code', async () => {
      const res = await http().post('/v1/auth/otp').send({ phone: PHONE }).expect(202);
      expect(res.body.retry_after_seconds).toBeGreaterThan(0);
      expect(res.body.masked_destination).toMatch(/\*\*/);
      expect(JSON.stringify(res.body)).not.toContain(sms.lastCode(PHONE));
      expect(sms.sent).toHaveLength(1);
    });

    it('rejects invalid phones with a problem+json 400', async () => {
      const res = await http().post('/v1/auth/otp').send({ phone: '0612345678' }).expect(400);
      expect(res.headers['content-type']).toMatch(/problem\+json/);
      expect(res.body.code).toBe('VALIDATION_ERROR');
    });

    it('rate-limits to 3 requests per phone per window', async () => {
      for (let i = 0; i < 3; i++)
        await http().post('/v1/auth/otp').send({ phone: PHONE }).expect(202);
      const res = await http().post('/v1/auth/otp').send({ phone: PHONE }).expect(429);
      expect(res.body.code).toBe('RATE_LIMITED');
      expect(res.headers['retry-after']).toBeDefined();
      expect(sms.sent).toHaveLength(3);
    });

    it('answers identically for new and existing numbers (no enumeration)', async () => {
      const a = await http().post('/v1/auth/otp').send({ phone: PHONE }).expect(202);
      await login(PHONE);
      const b = await http().post('/v1/auth/otp').send({ phone: PHONE }).expect(202);
      expect(Object.keys(b.body).sort()).toEqual(Object.keys(a.body).sort());
    });
  });

  describe('verify', () => {
    it('creates a TIER_0 user and returns tokens', async () => {
      const t = await login();
      expect(t.user).toMatchObject({ phone: PHONE, kyc_tier: 'TIER_0', country: 'TG' });
      expect(t.expires_in).toBe(900);
      expect(t.access_token.split('.')).toHaveLength(3);
    });

    it('passcode_set is false on first login and true once a passcode exists (also on refresh)', async () => {
      const first = await login();
      expect((first as { passcode_set?: boolean }).passcode_set).toBe(false);
      await http()
        .post('/v1/auth/passcode')
        .set(bearer(first.access_token))
        .send({ passcode: '482916' })
        .expect(204);
      const again = await login();
      expect((again as { passcode_set?: boolean }).passcode_set).toBe(true);
      const refreshed = await http()
        .post('/v1/auth/refresh')
        .send({ refresh_token: again.refresh_token })
        .expect(200);
      expect(refreshed.body.passcode_set).toBe(true);
    });

    it('a second login on the same phone returns the same user', async () => {
      const a = await login();
      const b = await login();
      expect(b.user.id).toBe(a.user.id);
    });

    it('a code is single-use', async () => {
      await http().post('/v1/auth/otp').send({ phone: PHONE }).expect(202);
      const code = sms.lastCode(PHONE);
      const body = { phone: PHONE, code, device_id: DEVICE };
      await http().post('/v1/auth/otp/verify').send(body).expect(200);
      await http().post('/v1/auth/otp/verify').send(body).expect(401);
    });

    it('wrong code → 401 OTP_INVALID; 5 failures lock the phone out even for the right code', async () => {
      await http().post('/v1/auth/otp').send({ phone: PHONE }).expect(202);
      const good = sms.lastCode(PHONE)!;
      const wrong = good === '000000' ? '111111' : '000000';
      for (let i = 0; i < 5; i++) {
        const r = await http()
          .post('/v1/auth/otp/verify')
          .send({ phone: PHONE, code: wrong, device_id: DEVICE });
        expect(r.status).toBe(401);
        expect(r.body.code).toBe('OTP_INVALID');
      }
      const locked = await http()
        .post('/v1/auth/otp/verify')
        .send({ phone: PHONE, code: good, device_id: DEVICE });
      expect(locked.status).toBe(429);
      expect(locked.body.code).toBe('OTP_LOCKED');
    });

    it('requires a device id', async () => {
      await http().post('/v1/auth/otp').send({ phone: PHONE }).expect(202);
      await http()
        .post('/v1/auth/otp/verify')
        .send({ phone: PHONE, code: sms.lastCode(PHONE) })
        .expect(400);
    });
  });

  describe('refresh rotation', () => {
    it('issues a new pair and revokes the old refresh token', async () => {
      const t = await login();
      const r1 = await http()
        .post('/v1/auth/refresh')
        .send({ refresh_token: t.refresh_token })
        .expect(200);
      expect(r1.body.refresh_token).not.toBe(t.refresh_token);
      expect(r1.body.user.id).toBe(t.user.id);
      await http()
        .post('/v1/auth/refresh')
        .send({ refresh_token: r1.body.refresh_token })
        .expect(200);
    });

    it('reuse of a rotated token revokes the whole family', async () => {
      const t = await login();
      const r1 = await http()
        .post('/v1/auth/refresh')
        .send({ refresh_token: t.refresh_token })
        .expect(200);
      await http().post('/v1/auth/refresh').send({ refresh_token: t.refresh_token }).expect(401); // replay
      // the legitimate newest token is now dead too → forced re-OTP
      await http()
        .post('/v1/auth/refresh')
        .send({ refresh_token: r1.body.refresh_token })
        .expect(401);
    });

    it('rejects garbage and does not touch other devices’ families', async () => {
      const a = await login(PHONE, DEVICE);
      const b = await login(PHONE, OTHER_DEVICE);
      await http()
        .post('/v1/auth/refresh')
        .send({ refresh_token: 'x'.repeat(43) })
        .expect(401);
      const r = await http()
        .post('/v1/auth/refresh')
        .send({ refresh_token: a.refresh_token })
        .expect(200);
      await http().post('/v1/auth/refresh').send({ refresh_token: a.refresh_token }).expect(401);
      await http().post('/v1/auth/refresh').send({ refresh_token: b.refresh_token }).expect(200);
      expect(r.body.access_token).toBeDefined();
    });
  });

  describe('passcode & step-up', () => {
    it('requires a bearer token', async () => {
      await http().post('/v1/auth/passcode').send({ passcode: '482916' }).expect(401);
      await http().post('/v1/auth/step-up').send({ passcode: '482916' }).expect(401);
    });

    it('sets a passcode, rejects weak/malformed ones', async () => {
      const t = await login();
      await http()
        .post('/v1/auth/passcode')
        .set(bearer(t.access_token))
        .send({ passcode: '12345' })
        .expect(400);
      for (const weak of ['000000', '123456', '654321']) {
        const r = await http()
          .post('/v1/auth/passcode')
          .set(bearer(t.access_token))
          .send({ passcode: weak });
        expect(r.status).toBe(400);
        expect(r.body.code).toBe('PASSCODE_TOO_WEAK');
      }
      await http()
        .post('/v1/auth/passcode')
        .set(bearer(t.access_token))
        .send({ passcode: '482916' })
        .expect(204);
    });

    it('changing needs the current passcode', async () => {
      const t = await login();
      const h = bearer(t.access_token);
      await http().post('/v1/auth/passcode').set(h).send({ passcode: '482916' }).expect(204);
      await http().post('/v1/auth/passcode').set(h).send({ passcode: '739104' }).expect(400);
      await http()
        .post('/v1/auth/passcode')
        .set(h)
        .send({ passcode: '739104', current_passcode: '111222' })
        .expect(401);
      await http()
        .post('/v1/auth/passcode')
        .set(h)
        .send({ passcode: '739104', current_passcode: '482916' })
        .expect(204);
      await http().post('/v1/auth/step-up').set(h).send({ passcode: '739104' }).expect(200);
    });

    it('step-up before a passcode exists → 403', async () => {
      const t = await login();
      const r = await http()
        .post('/v1/auth/step-up')
        .set(bearer(t.access_token))
        .send({ passcode: '482916' });
      expect(r.status).toBe(403);
      expect(r.body.code).toBe('PASSCODE_NOT_SET');
    });

    it('mints a 60s txn token; wrong passcode → 401; 5 failures lock', async () => {
      const t = await login();
      const h = bearer(t.access_token);
      await http().post('/v1/auth/passcode').set(h).send({ passcode: '482916' }).expect(204);
      const ok = await http()
        .post('/v1/auth/step-up')
        .set(h)
        .send({ passcode: '482916' })
        .expect(200);
      const ttl = new Date(ok.body.expires_at).getTime() - Date.now();
      expect(ttl).toBeGreaterThan(50_000);
      expect(ttl).toBeLessThanOrEqual(60_000);

      for (let i = 0; i < 5; i++)
        await http().post('/v1/auth/step-up').set(h).send({ passcode: '111222' }).expect(401);
      const locked = await http().post('/v1/auth/step-up').set(h).send({ passcode: '482916' });
      expect(locked.status).toBe(429);
      expect(locked.body.code).toBe('PASSCODE_LOCKED');
    });

    it('txn token is single-use and bound to the device', async () => {
      const t = await login(PHONE, DEVICE);
      const h = bearer(t.access_token);
      await http().post('/v1/auth/passcode').set(h).send({ passcode: '482916' }).expect(204);
      const { body } = await http()
        .post('/v1/auth/step-up')
        .set(h)
        .send({ passcode: '482916' })
        .expect(200);

      await http().post('/probe/pay').set(h).expect(401); // no token → step-up required
      await http().post('/probe/pay').set(h).set('X-Txn-Token', body.txn_token).expect(201);
      const replay = await http().post('/probe/pay').set(h).set('X-Txn-Token', body.txn_token);
      expect(replay.status).toBe(409);
      expect(replay.body.code).toBe('TXN_TOKEN_CONSUMED');

      // token minted on one device is useless from another session of the same user
      const other = await login(PHONE, OTHER_DEVICE);
      const fresh = await http()
        .post('/v1/auth/step-up')
        .set(h)
        .send({ passcode: '482916' })
        .expect(200);
      await http()
        .post('/probe/pay')
        .set(bearer(other.access_token))
        .set('X-Txn-Token', fresh.body.txn_token)
        .expect(409);
    });
  });
});
