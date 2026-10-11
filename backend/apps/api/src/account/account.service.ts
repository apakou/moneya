import { Inject, Injectable } from '@nestjs/common';
import { fromMicro, LedgerService, toMicro } from '@moneya/ledger';
import type { Pool } from 'pg';
import { ApiProblem } from '../common/problem';
import { AUTH_STORE, type AuthStore } from '../auth/auth.store';
import { RAMP_POOL, RAMP_PRICING } from '../ramp/ramp-orders.service';
import { convertAmount, UnsupportedCurrencyError, type PricingConfig } from '../ramp/pricing';

/** Fiat currencies the ledger holds user balances in (one wallet account per currency). */
export const WALLET_CURRENCIES = ['XOF', 'XAF', 'NGN', 'GHS', 'KES'] as const;
export type WalletCurrency = (typeof WALLET_CURRENCIES)[number];

/** A user's home currency, from the country their phone number belongs to. */
const HOME_CURRENCY: Record<string, WalletCurrency> = {
  TG: 'XOF',
  SN: 'XOF',
  CI: 'XOF',
  ML: 'XOF',
  BF: 'XOF',
  BJ: 'XOF',
  NE: 'XOF',
  GW: 'XOF',
  CM: 'XAF',
  GA: 'XAF',
  CG: 'XAF',
  TD: 'XAF',
  CF: 'XAF',
  GQ: 'XAF',
  NG: 'NGN',
  GH: 'GHS',
  KE: 'KES',
};

export type TransactionKind = 'TOP_UP' | 'CASH_OUT';
export type TransactionStatus = 'PENDING' | 'COMPLETED' | 'FAILED';

export interface TransactionDto {
  id: string;
  kind: TransactionKind;
  status: TransactionStatus;
  /** Top-up: what was credited to the balance. Cash-out: what was debited from it. */
  amount: string;
  currency: string;
  fee: string;
  payment_method: string;
  counterparty_phone: string;
  counterparty_name: string | null;
  created_at: string;
  completed_at: string | null;
}

const TOP_UP_STATUS: Record<string, TransactionStatus> = {
  COMPLETED: 'COMPLETED',
  FAILED: 'FAILED',
  EXPIRED: 'FAILED',
};
const CASH_OUT_STATUS: Record<string, TransactionStatus> = {
  SETTLED: 'COMPLETED',
  FAILED: 'FAILED',
  REFUNDED: 'FAILED',
};

const iso = (d: unknown): string | null => (d instanceof Date ? d.toISOString() : null);
/** NUMERIC text → plain decimal without trailing zeros ("13000.000000" → "13000"). */
const plain = (v: unknown): string =>
  v == null
    ? '0'
    : String(v)
        .replace(/(\.\d*?)0+$/, '$1')
        .replace(/\.$/, '');

@Injectable()
export class AccountService {
  constructor(
    @Inject(AUTH_STORE) private readonly store: AuthStore,
    @Inject(RAMP_POOL) private readonly pool: Pool,
    @Inject(RAMP_PRICING) private readonly pricing: PricingConfig,
    private readonly ledger: LedgerService,
  ) {}

  async me(userId: string) {
    const u = await this.store.findUserById(userId);
    if (!u) throw new ApiProblem(401, 'UNAUTHORIZED', 'Authentication required');
    return {
      id: u.id,
      phone: u.phone,
      country: u.country,
      full_name: u.full_name,
      photo_url: u.photo_url,
      kyc_tier: u.kyc_tier,
      created_at: u.created_at.toISOString(),
    };
  }

  /**
   * Balance in one currency, read from the ledger. Defaults to the user's home currency;
   * `?currency=` reads another. `balance` / `available_balance` are what is actually held in
   * that currency; `equivalent_balance` is everything the user holds (in any currency) expressed
   * in it at the current rates, rounded down.
   */
  async wallet(userId: string, currency: unknown) {
    const u = await this.store.findUserById(userId);
    if (!u) throw new ApiProblem(401, 'UNAUTHORIZED', 'Authentication required');
    const code = currency === undefined ? this.homeCurrency(u.country) : this.currency(currency);
    const [balance, available] = await Promise.all([
      this.ledger.getUserBalance(userId, code),
      this.ledger.getAvailableBalance(userId, code),
    ]);
    return {
      provisioned: u.kyc_tier !== 'TIER_0',
      currency: code,
      balance,
      available_balance: available,
      equivalent_balance: await this.equivalent(userId, code),
    };
  }

  /** Total of every balance the user holds, converted into `target`. */
  private async equivalent(userId: string, target: WalletCurrency): Promise<string> {
    const { rows } = await this.pool.query<{ currency: string; balance: string }>(
      'SELECT currency, balance::text AS balance FROM app.v_user_balances WHERE user_id = $1',
      [userId],
    );
    try {
      let total = 0n;
      for (const r of rows) {
        if (!(WALLET_CURRENCIES as readonly string[]).includes(r.currency)) continue;
        total += toMicro(
          convertAmount(this.pricing, plain(r.balance), r.currency as WalletCurrency, target),
        );
      }
      return fromMicro(total);
    } catch (e) {
      if (e instanceof UnsupportedCurrencyError)
        throw new ApiProblem(503, 'RATES_UNAVAILABLE', 'Exchange rates are temporarily unavailable');
      throw e;
    }
  }

  /** The user's top-ups and cash-outs, newest first, keyset-paginated. */
  async transactions(userId: string, limitRaw: unknown, cursorRaw: unknown) {
    const limit = this.limit(limitRaw);
    const [at, id] = this.cursor(cursorRaw);
    const { rows } = await this.pool.query(
      `SELECT * FROM (
         SELECT 'TOP_UP' AS kind, o.id, o.status::text AS raw_status,
                q.to_currency::text AS currency, q.to_amount::text AS amount, q.fee_amount::text AS fee,
                o.payment_method::text AS method, o.payer_msisdn::text AS phone, NULL::text AS name,
                o.created_at, o.created_at::text AS created_at_text, o.completed_at AS finished_at
           FROM app.onramp_orders o JOIN app.quotes q ON q.id = o.quote_id
          WHERE o.user_id = $1
         UNION ALL
         SELECT 'CASH_OUT', o.id, o.status::text,
                q.fiat_currency::text, q.fiat_amount::text, q.fee_amount::text,
                o.payout_method::text, o.payee_msisdn::text, o.payee_name,
                o.created_at, o.created_at::text, o.settled_at
           FROM app.offramp_orders o JOIN app.quotes q ON q.id = o.quote_id
          WHERE o.user_id = $1
       ) t
        WHERE ($2::timestamptz IS NULL OR (created_at, id) < ($2::timestamptz, $3::uuid))
        ORDER BY created_at DESC, id DESC
        LIMIT $4`,
      [userId, at, id, limit + 1],
    );
    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    const items: TransactionDto[] = page.map((r) => ({
      id: r.id,
      kind: r.kind,
      status: (r.kind === 'TOP_UP' ? TOP_UP_STATUS : CASH_OUT_STATUS)[r.raw_status] ?? 'PENDING',
      amount: plain(r.amount),
      currency: r.currency,
      fee: plain(r.fee),
      payment_method: r.method,
      counterparty_phone: r.phone,
      counterparty_name: r.name,
      created_at: r.created_at.toISOString(),
      completed_at: iso(r.finished_at),
    }));
    return {
      items,
      next_cursor: rows.length > limit && last ? `${last.created_at_text}|${last.id}` : null,
    };
  }

  // ----- input helpers ---------------------------------------------------------------------

  private homeCurrency(country: string): WalletCurrency {
    const c = HOME_CURRENCY[country];
    if (!c) throw new ApiProblem(400, 'UNSUPPORTED_COUNTRY', 'Your country is not supported yet');
    return c;
  }
  private currency(v: unknown): WalletCurrency {
    if (typeof v !== 'string' || !(WALLET_CURRENCIES as readonly string[]).includes(v))
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'Unsupported currency');
    return v as WalletCurrency;
  }
  private limit(v: unknown): number {
    if (v === undefined) return 20;
    const n = typeof v === 'string' && /^[0-9]{1,3}$/.test(v) ? Number(v) : NaN;
    if (!Number.isInteger(n) || n < 1 || n > 100)
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'limit must be between 1 and 100');
    return n;
  }
  private cursor(v: unknown): [string | null, string | null] {
    if (v === undefined) return [null, null];
    const m =
      typeof v === 'string'
        ? /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:[+-]\d{2}(?::?\d{2})?|Z))\|([0-9a-f-]{36})$/i.exec(
            v,
          )
        : null;
    if (!m) throw new ApiProblem(400, 'VALIDATION_ERROR', 'Invalid cursor');
    return [m[1]!, m[2]!];
  }
}
