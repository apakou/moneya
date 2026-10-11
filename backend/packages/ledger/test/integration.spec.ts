import { Pool } from 'pg';
import { randomInt, randomUUID } from 'node:crypto';
import {
  InsufficientFundsError,
  JournalAlreadyPostedError,
  LedgerService,
  templates,
  validateJournal,
} from '../src';

/**
 * Runs against a real PostgreSQL with migrations 0001..0005 applied.
 *   LEDGER_TEST_DATABASE_URL=postgres://postgres:postgres@localhost/moneya_ci pnpm test
 * Skipped (not faked) when the variable is absent.
 */
const url = process.env.LEDGER_TEST_DATABASE_URL;
const describeDb = url ? describe : describe.skip;

describeDb('LedgerService on PostgreSQL', () => {
  let pool: Pool;
  let ledger: LedgerService;
  const CUR = 'GHS';

  beforeAll(() => {
    pool = new Pool({ connectionString: url, max: 10 });
    ledger = new LedgerService(pool);
  });
  afterAll(() => pool.end());

  async function newUser(): Promise<string> {
    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO app.users (phone, country) VALUES ($1, 'GH') RETURNING id`,
      [`+2332${String(randomInt(0, 100_000_000)).padStart(8, '0')}`],
    );
    return rows[0]!.id;
  }
  async function fund(userId: string, amount: string): Promise<void> {
    await ledger.postJournal(
      templates.reconciliationAdjustment({
        incidentId: randomUUID(),
        userId,
        currency: CUR,
        delta: amount,
        memo: 'test funding',
      }),
    );
  }
  const feeBalance = async () =>
    (
      await pool.query<{ b: string }>(
        `SELECT COALESCE(SUM(e.amount_usdc),0)::text b FROM app.ledger_entries e
         JOIN app.ledger_accounts a ON a.id=e.account_id WHERE a.kind='FEE_REVENUE' AND a.currency=$1`,
        [CUR],
      )
    ).rows[0]!.b;

  it('posts a P2P transfer: balances, fee revenue, history', async () => {
    const [a, b] = [await newUser(), await newUser()];
    await fund(a, '100');
    const feeBefore = Number(await feeBalance());
    const transferId = randomUUID();
    await ledger.postJournal(
      templates.p2pTransfer({
        transferId,
        senderId: a,
        recipientId: b,
        currency: CUR,
        amount: '60',
        fee: '0.5',
      }),
    );
    expect(await ledger.getUserBalance(a, CUR)).toBe('39.5');
    expect(await ledger.getUserBalance(b, CUR)).toBe('60');
    expect(Number(await feeBalance()) - feeBefore).toBeCloseTo(0.5, 6);

    const acct = (await pool.query(`SELECT id FROM app.ledger_accounts WHERE user_id=$1`, [a]))
      .rows[0].id;
    const page1 = await ledger.getAccountHistory(acct, { limit: 1 });
    expect(page1.items).toHaveLength(1);
    expect(page1.items[0]!.amount).toBe('-60.5');
    expect(page1.nextCursor).not.toBeNull();
    const page2 = await ledger.getAccountHistory(acct, { limit: 1, cursor: page1.nextCursor! });
    expect(page2.items[0]!.amount).toBe('100');
    expect(page2.nextCursor).toBeNull();
  });

  it('replaying a journal id throws and changes nothing', async () => {
    const [a, b] = [await newUser(), await newUser()];
    await fund(a, '100');
    const j = templates.p2pTransfer({
      transferId: randomUUID(),
      senderId: a,
      recipientId: b,
      currency: CUR,
      amount: '10',
      fee: '0',
    });
    await ledger.postJournal(j);
    await expect(ledger.postJournal(j)).rejects.toBeInstanceOf(JournalAlreadyPostedError);
    expect(await ledger.getUserBalance(a, CUR)).toBe('90');
    expect(await ledger.getUserBalance(b, CUR)).toBe('10');
  });

  it('refuses to overdraw and leaves no trace (rolled back)', async () => {
    const [a, b] = [await newUser(), await newUser()];
    await fund(a, '5');
    const j = templates.p2pTransfer({
      transferId: randomUUID(),
      senderId: a,
      recipientId: b,
      currency: CUR,
      amount: '10',
      fee: '0',
    });
    await expect(ledger.postJournal(j)).rejects.toBeInstanceOf(InsufficientFundsError);
    expect(await ledger.getUserBalance(a, CUR)).toBe('5');
    const reg = await pool.query('SELECT 1 FROM app.posted_journals WHERE journal_id=$1', [
      j.journalId,
    ]);
    expect(reg.rowCount).toBe(0);
    // and the same journal can be posted once funds exist
    await fund(a, '10');
    await ledger.postJournal(j);
    expect(await ledger.getUserBalance(a, CUR)).toBe('5');
  });

  it('serializes concurrent spends: 10 x 30 from a balance of 100 → exactly 3 succeed', async () => {
    const a = await newUser();
    const b = await newUser();
    await fund(a, '100');
    const results = await Promise.allSettled(
      Array.from({ length: 10 }, () =>
        ledger.postJournal(
          templates.p2pTransfer({
            transferId: randomUUID(),
            senderId: a,
            recipientId: b,
            currency: CUR,
            amount: '30',
            fee: '0',
          }),
        ),
      ),
    );
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(3);
    expect(
      results
        .filter((r) => r.status === 'rejected')
        .every((r) => (r as PromiseRejectedResult).reason instanceof InsufficientFundsError),
    ).toBe(true);
    expect(await ledger.getUserBalance(a, CUR)).toBe('10');
    expect(await ledger.getUserBalance(b, CUR)).toBe('90');
  });

  it('escrow: hold → release (fee earned) and hold → refund (fee returned)', async () => {
    const [a, b] = [await newUser(), await newUser()];
    await fund(a, '100');
    const p = { currency: CUR, amount: '40', fee: '1' };
    const t1 = randomUUID();
    await ledger.postJournal(templates.escrowHold({ ...p, transferId: t1, senderId: a }));
    expect(await ledger.getUserBalance(a, CUR)).toBe('59');
    await ledger.postJournal(templates.escrowRelease({ ...p, transferId: t1, recipientId: b }));
    expect(await ledger.getUserBalance(b, CUR)).toBe('40');

    const t2 = randomUUID();
    await ledger.postJournal(templates.escrowHold({ ...p, transferId: t2, senderId: a }));
    expect(await ledger.getUserBalance(a, CUR)).toBe('18');
    await ledger.postJournal(
      templates.escrowRefund({ ...p, transferId: t2, senderId: a, reason: 'EXPIRED' }),
    );
    expect(await ledger.getUserBalance(a, CUR)).toBe('59');
  });

  it('available balance subtracts active holds', async () => {
    const [a] = [await newUser()];
    await fund(a, '100');
    const { rows } = await pool.query<{ id: string }>(
      `INSERT INTO app.transfers (sender_id, recipient_phone, kind, amount_usdc)
       VALUES ($1, '+233200000001', 'SENT', 30) RETURNING id`,
      [a],
    );
    await pool.query(
      `INSERT INTO app.escrow_holds (transfer_id, user_id, amount_usdc, currency) VALUES ($1,$2,30,$3)`,
      [rows[0]!.id, a, CUR],
    );
    expect(await ledger.getAvailableBalance(a, CUR)).toBe('70');
    expect(await ledger.getUserBalance(a, CUR)).toBe('100');
  });

  it('a caller can update its own rows in the same transaction (atomic with the post)', async () => {
    const [a, b] = [await newUser(), await newUser()];
    await fund(a, '20');
    const tr = (
      await pool.query<{ id: string }>(
        `INSERT INTO app.transfers (sender_id, recipient_id, recipient_phone, kind, amount_usdc)
       VALUES ($1,$2,'+233200000002','SENT',10) RETURNING id`,
        [a, b],
      )
    ).rows[0]!.id;
    await expect(
      ledger.withTransaction(async (tx) => {
        await tx.postJournal(
          templates.p2pTransfer({
            transferId: tr,
            senderId: a,
            recipientId: b,
            currency: CUR,
            amount: '10',
            fee: '0',
          }),
        );
        await tx.client.query(`UPDATE app.transfers SET status='PROCESSING' WHERE id=$1`, [tr]);
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');
    expect(await ledger.getUserBalance(a, CUR)).toBe('20');
    expect(
      (await pool.query('SELECT status FROM app.transfers WHERE id=$1', [tr])).rows[0].status,
    ).toBe('DRAFT');
  });

  it('the imbalance view stays empty and templates validate', async () => {
    expect((await pool.query('SELECT 1 FROM app.v_ledger_imbalance')).rowCount).toBe(0);
    validateJournal(
      templates.escrowHold({
        transferId: randomUUID(),
        senderId: randomUUID(),
        currency: CUR,
        amount: '1',
        fee: '0',
      }),
    );
  });
});
