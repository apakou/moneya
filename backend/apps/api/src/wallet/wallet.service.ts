import { Inject, Injectable } from '@nestjs/common';
import { LedgerService, fromMicro, toMicro } from '@moneya/ledger';
import type { Pool } from 'pg';
import { AuthService } from '../auth/auth.service';
import { homeCurrency } from '../common/currency';
import { ApiProblem } from '../common/problem';
import { RAMP_POOL } from '../ramp/ramp-orders.service';

const money = (v: unknown): string => fromMicro(toMicro(String(v)));

/** Order status → `Transfer.status` (openapi.yaml). */
const STATUS: Record<string, string> = {
  AWAITING_PAYMENT: 'PROCESSING',
  COLLECTED: 'PROCESSING',
  CREDITING_WALLET: 'PROCESSING',
  PROCESSING: 'PROCESSING',
  COMPLETED: 'COMPLETED',
  SETTLED: 'COMPLETED',
  FAILED: 'FAILED',
  EXPIRED: 'FAILED',
  REFUNDED: 'FAILED',
};

/** Order failure reason → `Transfer.failure_reason`. */
const FAILURE: Record<string, string> = {
  PAYER_DECLINED: 'PROVIDER_REJECTED',
  PROVIDER_REJECTED: 'PROVIDER_REJECTED',
  PAYEE_INVALID: 'PROVIDER_REJECTED',
  PROVIDER_TIMEOUT: 'SERVICE_UNAVAILABLE',
  PROVIDER_ERROR: 'SERVICE_UNAVAILABLE',
  INSUFFICIENT_LIQUIDITY: 'SERVICE_UNAVAILABLE',
  COMPLIANCE_BLOCK: 'COMPLIANCE_BLOCK',
};

interface TransferRow {
  id: string;
  kind: 'ONRAMP' | 'OFFRAMP';
  raw_status: string;
  amount: string;
  fee: string;
  currency: string;
  phone: string;
  failure_reason: string | null;
  created_at: Date;
  finished_at: Date | null;
}

@Injectable()
export class WalletService {
  constructor(
    @Inject(RAMP_POOL) private readonly pool: Pool,
    private readonly ledger: LedgerService,
    private readonly auth: AuthService,
  ) {}

  /** `GET /v1/wallet`: the spendable balance (ledger minus active holds) in the user's home currency. */
  async getWallet(userId: string) {
    const user = await this.auth.getUser(userId);
    const currency = homeCurrency(user.country);
    if (!currency) return { provisioned: false, balance: '0', currency: 'GHS' };
    return {
      provisioned: true,
      balance: await this.ledger.getAvailableBalance(userId, currency),
      currency,
      balance_cached_at: new Date().toISOString(),
    };
  }

  /**
   * `GET /v1/transfers`: the user's money movements, newest first. Today that is their top-ups and
   * cash-outs (peer-to-peer sends join this list when they exist). Cursor = `created_at|id`.
   */
  async listTransfers(userId: string, q: { limit?: unknown; cursor?: unknown; kind?: unknown }) {
    const limit = this.limit(q.limit);
    const kind = q.kind === undefined ? null : this.kind(q.kind);
    let at: string | null = null;
    let id: string | null = null;
    if (q.cursor !== undefined) {
      const m = /^(.+)\|([0-9a-f-]{36})$/i.exec(String(q.cursor));
      if (!m) throw new ApiProblem(400, 'VALIDATION_ERROR', 'Invalid cursor');
      [, at, id] = m as unknown as [string, string, string];
    }
    const { rows } = await this.pool.query<TransferRow>(
      `SELECT * FROM (
         SELECT o.id, 'ONRAMP' AS kind, o.status::text AS raw_status, q.to_amount AS amount,
                q.fee_amount AS fee, q.fiat_currency::text AS currency, o.payer_msisdn AS phone,
                o.failure_reason, o.created_at, o.completed_at AS finished_at
           FROM app.onramp_orders o JOIN app.quotes q ON q.id = o.quote_id WHERE o.user_id = $1
         UNION ALL
         SELECT o.id, 'OFFRAMP', o.status::text, (q.fiat_amount - q.fee_amount),
                q.fee_amount, q.fiat_currency::text, o.payee_msisdn,
                o.failure_reason, o.created_at, o.settled_at
           FROM app.offramp_orders o JOIN app.quotes q ON q.id = o.quote_id WHERE o.user_id = $1
       ) t
       WHERE ($2::text IS NULL OR t.kind = $2)
         AND ($3::timestamptz IS NULL OR (t.created_at, t.id) < ($3::timestamptz, $4::uuid))
       ORDER BY t.created_at DESC, t.id DESC
       LIMIT $5`,
      [userId, kind, at, id, limit + 1],
    );
    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    const items = await Promise.all(page.map((r) => this.toTransfer(userId, r)));
    return {
      items,
      has_more: rows.length > limit,
      next_cursor:
        rows.length > limit && last
          ? `${await this.cursorTs(last.id, last.kind)}|${last.id}`
          : null,
    };
  }

  /** Cursor timestamps must round-trip exactly (microseconds), which a JS Date cannot. */
  private async cursorTs(id: string, kind: string): Promise<string> {
    const table = kind === 'ONRAMP' ? 'onramp_orders' : 'offramp_orders';
    const { rows } = await this.pool.query<{ ts: string }>(
      `SELECT created_at::text AS ts FROM app.${table} WHERE id = $1`,
      [id],
    );
    return rows[0]!.ts;
  }

  private async toTransfer(userId: string, r: TransferRow) {
    const user = await this.auth.getUser(userId);
    const you = { user_id: userId, phone: user.phone, display_name: user.full_name };
    const other = { user_id: null, phone: r.phone, display_name: null };
    const status = STATUS[r.raw_status] ?? 'PROCESSING';
    return {
      id: r.id,
      kind: r.kind,
      status,
      sender: r.kind === 'ONRAMP' ? other : you,
      recipient: r.kind === 'ONRAMP' ? you : other,
      amount: money(r.amount),
      fee: money(r.fee),
      currency: r.currency,
      note: null,
      failure_reason:
        status === 'FAILED' ? (FAILURE[r.failure_reason ?? ''] ?? 'SERVICE_UNAVAILABLE') : null,
      created_at: new Date(r.created_at).toISOString(),
      completed_at: r.finished_at ? new Date(r.finished_at).toISOString() : null,
    };
  }

  private limit(v: unknown): number {
    if (v === undefined) return 20;
    const n = Number(v);
    if (!Number.isInteger(n) || n < 1 || n > 50)
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'limit must be 1-50');
    return n;
  }

  private kind(v: unknown): string {
    if (typeof v !== 'string' || !['SENT', 'RECEIVED', 'ONRAMP', 'OFFRAMP'].includes(v)) {
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'Invalid kind');
    }
    return v;
  }
}
