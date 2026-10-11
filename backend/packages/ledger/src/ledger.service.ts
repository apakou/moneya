import type { Pool, PoolClient } from 'pg';
import { fromMicro, toMicro } from './money';
import { validateJournal } from './validate';
import {
  InsufficientFundsError,
  JournalAlreadyPostedError,
  type AccountRef,
  type Journal,
} from './types';

export interface LedgerTx {
  /** The transaction's connection, so callers can update `transfers` etc. atomically (ledger.md §5.2). */
  readonly client: PoolClient;
  postJournal(journal: Journal): Promise<void>;
}

export interface HistoryEntry {
  id: string;
  journalId: string;
  amount: string;
  currency: string;
  refType: string;
  refId: string;
  memo: string | null;
  postedAt: string;
}

const accountName = (a: AccountRef): string => `${a.kind}:${a.userId ?? 'GLOBAL'}:${a.currency}`;
const refKey = (a: AccountRef): string => `${a.kind}|${a.userId ?? ''}|${a.currency}`;
const normalize = (n: string): string => fromMicro(toMicro(n));

/**
 * Posts journals to `app.ledger_entries` (LDG-02) and answers balance queries (LDG-03).
 *
 * Guarantees, on top of the DB triggers from 0002:
 *  - all entries + the dedupe row go in ONE transaction (all or nothing);
 *  - replaying a journal id throws {@link JournalAlreadyPostedError} and changes nothing;
 *  - a user wallet can never go negative (L8): concurrent spends from the same
 *    wallet are serialized with a per-account advisory lock.
 */
export class LedgerService {
  constructor(private readonly pool: Pool) {}

  async withTransaction<T>(fn: (tx: LedgerTx) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await fn({ client, postJournal: (j) => this.post(client, j) });
      await client.query('COMMIT'); // deferred balance/registration triggers fire here
      return result;
    } catch (err) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw err;
    } finally {
      client.release();
    }
  }

  postJournal(journal: Journal): Promise<void> {
    return this.withTransaction((tx) => tx.postJournal(journal));
  }

  private async post(client: PoolClient, journal: Journal): Promise<void> {
    validateJournal(journal);

    const refs = new Map<string, AccountRef>();
    for (const e of journal.entries) refs.set(refKey(e.account), e.account);
    const ids = new Map<string, string>();
    for (const [key, ref] of refs) ids.set(key, await this.accountId(client, ref));

    // Serialize spends: lock every debited user wallet, in a stable order (no deadlocks).
    const debited = [
      ...new Set(
        journal.entries
          .filter((e) => e.account.kind === 'USER_WALLET' && toMicro(e.amount) < 0n)
          .map((e) => ids.get(refKey(e.account))!),
      ),
    ].sort();
    for (const id of debited) {
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [id]);
    }

    const reg = await client.query(
      `INSERT INTO app.posted_journals (journal_id, ref_type, ref_id)
       VALUES ($1, $2, $3) ON CONFLICT (journal_id) DO NOTHING RETURNING journal_id`,
      [journal.journalId, journal.ref.refType, journal.ref.refId],
    );
    if (reg.rowCount === 0) throw new JournalAlreadyPostedError(journal.journalId);

    for (const e of journal.entries) {
      await client.query(
        `INSERT INTO app.ledger_entries (journal_id, account_id, amount_usdc, currency, ref_type, ref_id, memo)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          journal.journalId,
          ids.get(refKey(e.account)),
          e.amount,
          e.account.currency,
          journal.ref.refType,
          journal.ref.refId,
          e.memo ?? null,
        ],
      );
    }

    for (const e of journal.entries) {
      if (e.account.kind !== 'USER_WALLET' || toMicro(e.amount) >= 0n) continue;
      const { rows } = await client.query<{ balance: string }>(
        'SELECT COALESCE(SUM(amount_usdc), 0)::text AS balance FROM app.ledger_entries WHERE account_id = $1',
        [ids.get(refKey(e.account))],
      );
      if (toMicro(rows[0]!.balance) < 0n) throw new InsufficientFundsError(e.account.userId!);
    }
  }

  private async accountId(client: PoolClient, ref: AccountRef): Promise<string> {
    const find = () =>
      client.query<{ id: string }>(
        `SELECT id FROM app.ledger_accounts
          WHERE kind = $1 AND currency = $2 AND user_id IS NOT DISTINCT FROM $3::uuid`,
        [ref.kind, ref.currency, ref.userId ?? null],
      );
    let r = await find();
    if (r.rowCount === 0) {
      // Unique on (kind,user,currency) / (kind,currency) for globals: a racing insert is a no-op.
      await client.query(
        `INSERT INTO app.ledger_accounts (kind, user_id, currency, name)
         VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING`,
        [ref.kind, ref.userId ?? null, ref.currency, accountName(ref)],
      );
      r = await find();
    }
    return r.rows[0]!.id;
  }

  // ----- LDG-03: queries -------------------------------------------------------

  async getUserBalance(userId: string, currency: string): Promise<string> {
    const { rows } = await this.pool.query<{ balance: string }>(
      'SELECT balance::text FROM app.v_user_balances WHERE user_id = $1 AND currency = $2',
      [userId, currency],
    );
    return normalize(rows[0]?.balance ?? '0');
  }

  /** Ledger balance minus active escrow holds (ledger.md §6.2). */
  async getAvailableBalance(userId: string, currency: string): Promise<string> {
    const { rows } = await this.pool.query<{ b: string }>(
      'SELECT app.user_available_balance($1, $2)::text AS b',
      [userId, currency],
    );
    return normalize(rows[0]!.b);
  }

  async getAccountHistory(
    accountId: string,
    opts: { limit?: number; cursor?: string } = {},
  ): Promise<{ items: HistoryEntry[]; nextCursor: string | null }> {
    const limit = Math.min(Math.max(opts.limit ?? 20, 1), 100);
    const [at, id] = opts.cursor ? opts.cursor.split('|') : [null, null];
    const { rows } = await this.pool.query(
      `SELECT id, journal_id, amount_usdc::text AS amount, currency, ref_type, ref_id, memo,
              posted_at::text AS posted_at
         FROM app.ledger_entries
        WHERE account_id = $1
          AND ($2::timestamptz IS NULL OR (posted_at, id) < ($2::timestamptz, $3::uuid))
        ORDER BY posted_at DESC, id DESC
        LIMIT $4`,
      [accountId, at, id, limit + 1],
    );
    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    return {
      items: page.map((r) => ({
        id: r.id,
        journalId: r.journal_id,
        amount: normalize(r.amount),
        currency: r.currency,
        refType: r.ref_type,
        refId: r.ref_id,
        memo: r.memo,
        postedAt: r.posted_at,
      })),
      nextCursor: rows.length > limit && last ? `${last.posted_at}|${last.id}` : null,
    };
  }
}
