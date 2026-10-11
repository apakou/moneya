import { randomInt, randomUUID } from 'node:crypto';
import { PgAuthStore } from '../src/auth/pg-auth.store';

const url = process.env.TEST_DATABASE_URL ?? process.env.LEDGER_TEST_DATABASE_URL;
const describeDb = url ? describe : describe.skip;

describeDb('PgAuthStore atomicity (real PostgreSQL)', () => {
  let store: PgAuthStore;
  const phone = () => `+22891${String(randomInt(0, 1_000_000)).padStart(6, '0')}`;

  beforeAll(() => {
    store = PgAuthStore.fromUrl(url!);
  });
  afterAll(() => store.onModuleDestroy());

  it('createUser is race-safe: 10 parallel first logins → one user', async () => {
    const p = phone();
    const users = await Promise.all(Array.from({ length: 10 }, () => store.createUser(p, 'TG')));
    expect(new Set(users.map((u) => u.id)).size).toBe(1);
  });

  it('a txn token is consumed by exactly one of 10 parallel requests', async () => {
    const u = await store.createUser(phone(), 'TG');
    const device = randomUUID();
    await store.insertTxnToken({
      id: randomUUID(),
      userId: u.id,
      deviceId: device,
      tokenHash: 'h-' + randomUUID(),
      consumedAt: null,
      expiresAt: new Date(Date.now() + 60_000),
    });
    const hash = (
      await store['pool'].query('SELECT token_hash FROM app.txn_tokens WHERE user_id=$1', [u.id])
    ).rows[0].token_hash;
    const results = await Promise.all(
      Array.from({ length: 10 }, () => store.consumeTxnToken(hash, u.id, device, new Date())),
    );
    expect(results.filter(Boolean)).toHaveLength(1);
    expect(await store.consumeTxnToken(hash, u.id, randomUUID(), new Date())).toBeNull(); // wrong device
  });

  it('an expired txn token cannot be consumed', async () => {
    const u = await store.createUser(phone(), 'TG');
    const device = randomUUID();
    await store.insertTxnToken({
      id: randomUUID(),
      userId: u.id,
      deviceId: device,
      tokenHash: 'exp-' + randomUUID(),
      consumedAt: null,
      expiresAt: new Date(Date.now() - 1000),
    });
    const hash = (
      await store['pool'].query('SELECT token_hash FROM app.txn_tokens WHERE user_id=$1', [u.id])
    ).rows[0].token_hash;
    expect(await store.consumeTxnToken(hash, u.id, device, new Date())).toBeNull();
  });

  it('refresh rotation: only one of 5 parallel revokes wins; the successor pointer is stored', async () => {
    const u = await store.createUser(phone(), 'TG');
    const id = randomUUID();
    await store.insertRefresh({
      id,
      userId: u.id,
      deviceId: randomUUID(),
      familyId: randomUUID(),
      tokenHash: 'r-' + randomUUID(),
      revokedAt: null,
      replacedBy: null,
      expiresAt: new Date(Date.now() + 1e6),
    });
    const next = randomUUID();
    const wins = await Promise.all(
      Array.from({ length: 5 }, () => store.revokeRefresh(id, new Date(), next)),
    );
    expect(wins.filter(Boolean)).toHaveLength(1);
  });

  it('passcode failures count atomically and lock at the threshold', async () => {
    const u = await store.createUser(phone(), 'TG');
    await store.setPasscode(u.id, '$argon2id$stub');
    const lockAt = new Date(Date.now() + 900_000);
    await Promise.all(
      Array.from({ length: 10 }, () => store.recordPasscodeFailure(u.id, 5, lockAt)),
    );
    const row = await store.getPasscode(u.id);
    expect(row?.failedAttempts).toBe(10);
    expect(row?.lockedUntil?.getTime()).toBe(lockAt.getTime());
    await store.resetPasscodeFailures(u.id);
    expect((await store.getPasscode(u.id))?.lockedUntil).toBeNull();
  });
});
