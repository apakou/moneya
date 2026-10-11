import { Inject, Injectable } from '@nestjs/common';
import { InsufficientFundsError, LedgerService, templates } from '@moneya/ledger';
import {
  RampError,
  type RampEvent,
  type RampFailureReason,
  type RampProvider,
  type RampCurrency,
} from '@moneya/ramp';
import { randomBytes, randomUUID } from 'node:crypto';
import type { Pool, PoolClient } from 'pg';
import { ApiProblem } from '../common/problem';
import {
  priceOfframp,
  priceOnramp,
  UnsupportedCurrencyError,
  type PricedQuote,
  type PricingConfig,
} from './pricing';

export const RAMP_POOL = Symbol('RAMP_POOL');
export const RAMP_PRICING = Symbol('RAMP_PRICING');
export const RAMP_PROVIDER = Symbol('RAMP_PROVIDER');
export const RAMP_SETTLEMENT = Symbol('RAMP_SETTLEMENT');

/**
 * Confirms that the treasury actually received the settlement for a collected top-up.
 * Real impl = the inbound-payment matcher (STL-05) calling `completeOnramp`; the simulated
 * one confirms instantly so staging works end to end. Returning null = not settled yet.
 */
export interface SettlementPort {
  confirm(order: { id: string; expectedAmount: string }): Promise<string | null>;
}

export const PAYMENT_METHODS = [
  'WAVE',
  'MTN_MOMO',
  'ORANGE_MONEY',
  'MOOV_MONEY',
  'AIRTEL_MONEY',
  'MPESA',
  'BANK_TRANSFER',
] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

const NETWORK: Record<PaymentMethod, string | undefined> = {
  WAVE: 'WAVE',
  MTN_MOMO: 'MTN',
  ORANGE_MONEY: 'ORANGE',
  MOOV_MONEY: 'MOOV',
  AIRTEL_MONEY: 'AIRTEL',
  MPESA: 'MPESA',
  BANK_TRANSFER: undefined,
};
const railOf = (m: PaymentMethod) =>
  m === 'BANK_TRANSFER' ? ('BANK' as const) : ('MOBILE_MONEY' as const);

const ONRAMP_FAILURE: Record<RampFailureReason, string> = {
  PROVIDER_REJECTED: 'PAYER_DECLINED',
  INSUFFICIENT_FUNDS: 'PAYER_DECLINED',
  INVALID_ACCOUNT: 'PAYER_DECLINED',
  LIMIT_EXCEEDED: 'PAYER_DECLINED',
  TIMEOUT: 'PROVIDER_TIMEOUT',
};
const OFFRAMP_FAILURE: Record<RampFailureReason, string> = {
  PROVIDER_REJECTED: 'PROVIDER_REJECTED',
  INSUFFICIENT_FUNDS: 'INSUFFICIENT_LIQUIDITY',
  INVALID_ACCOUNT: 'PAYEE_INVALID',
  LIMIT_EXCEEDED: 'PROVIDER_REJECTED',
  TIMEOUT: 'PROVIDER_TIMEOUT',
};

const QUOTE_TTL_MS = 60_000;
const iso = (d: Date | null): string | null => (d ? d.toISOString() : null);

export interface QuoteDto {
  id: string;
  kind: 'ONRAMP' | 'OFFRAMP';
  from_currency: string;
  from_amount: string;
  to_currency: string;
  to_amount: string;
  rate: string;
  fee: string;
  expires_at: string;
}

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

/**
 * Top-up and cash-out orders (M6/M7). The API surface is fiat-only; the settlement leg
 * lives only in `quotes.usdc_amount` and the ledger.
 *
 * Idempotency: a quote is consumed atomically with the order insert, so a replayed
 * request cannot create a second order; every ledger journal id is derived from the order
 * id, so replayed events cannot double-post; status transitions are guarded `WHERE status = …`.
 */
@Injectable()
export class RampOrdersService {
  constructor(
    @Inject(RAMP_POOL) private readonly pool: Pool,
    private readonly ledger: LedgerService,
    @Inject(RAMP_PROVIDER) private readonly provider: RampProvider,
    @Inject(RAMP_PRICING) private readonly pricing: PricingConfig,
    @Inject(RAMP_SETTLEMENT) private readonly settlement: SettlementPort | null,
  ) {}

  // ----- quotes ----------------------------------------------------------------------------

  async quoteOnramp(userId: string, currency: unknown, amount: unknown): Promise<QuoteDto> {
    const c = this.currency(currency);
    return this.saveQuote(
      userId,
      'ONRAMP',
      this.price(() => priceOnramp(this.pricing, c, this.money(amount))),
    );
  }

  async quoteOfframp(
    userId: string,
    amount: unknown,
    currency: unknown,
    payoutCurrency: unknown,
  ): Promise<QuoteDto> {
    const c = this.currency(currency);
    const p = this.currency(payoutCurrency);
    return this.saveQuote(
      userId,
      'OFFRAMP',
      this.price(() => priceOfframp(this.pricing, c, p, this.money(amount))),
    );
  }

  private price(fn: () => PricedQuote): PricedQuote {
    try {
      return fn();
    } catch (e) {
      if (e instanceof RangeError)
        throw new ApiProblem(400, 'AMOUNT_TOO_SMALL', 'Amount too small');
      if (e instanceof UnsupportedCurrencyError)
        throw new ApiProblem(400, 'UNSUPPORTED_CURRENCY', 'Currency not available');
      throw e;
    }
  }

  private async saveQuote(
    userId: string,
    kind: 'ONRAMP' | 'OFFRAMP',
    q: PricedQuote,
  ): Promise<QuoteDto> {
    const id = randomUUID();
    const expires = new Date(Date.now() + QUOTE_TTL_MS);
    await this.pool.query(
      `INSERT INTO app.quotes (id, user_id, kind, fiat_currency, fiat_amount, usdc_amount, rate, fee_usdc,
                               to_currency, to_amount, fee_amount, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,0,$8,$9,$10,$11)`,
      [
        id,
        userId,
        kind,
        q.fromCurrency,
        q.fromAmount,
        q.settlementAmount,
        q.rate,
        q.toCurrency,
        q.toAmount,
        q.fee,
        expires,
      ],
    );
    return this.quoteDto({
      id,
      kind,
      fiat_currency: q.fromCurrency,
      fiat_amount: q.fromAmount,
      to_currency: q.toCurrency,
      to_amount: q.toAmount,
      rate: q.rate,
      fee_amount: q.fee,
      expires_at: expires,
    });
  }

  private quoteDto(r: Row): QuoteDto {
    const num = (v: unknown) =>
      String(v)
        .replace(/(\.\d*?)0+$/, '$1')
        .replace(/\.$/, '');
    return {
      id: r.id,
      kind: r.kind,
      from_currency: r.fiat_currency,
      from_amount: num(r.fiat_amount),
      to_currency: r.to_currency,
      to_amount: num(r.to_amount),
      rate: num(r.rate),
      fee: num(r.fee_amount),
      expires_at: new Date(r.expires_at).toISOString(),
    };
  }

  /** Locks and consumes a quote inside the caller's transaction; 409 when expired/used/not theirs. */
  private async takeQuote(
    c: PoolClient,
    userId: string,
    quoteId: unknown,
    kind: 'ONRAMP' | 'OFFRAMP',
  ): Promise<Row> {
    if (typeof quoteId !== 'string' || !/^[0-9a-f-]{36}$/i.test(quoteId))
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'quote_id must be a UUID');
    const { rows } = await c.query(
      `SELECT * FROM app.quotes WHERE id = $1 AND user_id = $2 AND kind = $3 FOR UPDATE`,
      [quoteId, userId, kind],
    );
    const q = rows[0];
    if (!q) throw new ApiProblem(404, 'NOT_FOUND', 'Quote not found');
    if (q.consumed_at || new Date(q.expires_at) <= new Date())
      throw new ApiProblem(409, 'QUOTE_EXPIRED', 'Quote expired, please request a new one');
    await c.query('UPDATE app.quotes SET consumed_at = now() WHERE id = $1', [quoteId]);
    return q;
  }

  // ----- top-up -----------------------------------------------------------------------------

  async createOnramp(userId: string, body: Record<string, unknown>) {
    const method = this.method(body.payment_method);
    const phone = this.phone(body.payer_msisdn);
    const orderId = randomUUID();
    const memo = randomBytes(10).toString('base64url'); // chain-side reference; never exposed

    const quote = await this.ledger.withTransaction(async ({ client }) => {
      const q = await this.takeQuote(client, userId, body.quote_id, 'ONRAMP');
      await client.query(
        `INSERT INTO app.onramp_orders (id, user_id, quote_id, payment_method, payer_msisdn, deposit_memo)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [orderId, userId, q.id, method, phone, memo],
      );
      return q;
    });

    try {
      const op = await this.provider.createCollection({
        orderId,
        currency: quote.fiat_currency,
        amount: this.plain(quote.fiat_amount, quote.fiat_currency),
        phone,
        rail: railOf(method),
        network: NETWORK[method],
      });
      await this.pool.query(
        `UPDATE app.onramp_orders SET yc_order_id = $2, ussd_instructions = $3, checkout_url = $4, next_action_at = now() + interval '30 seconds'
          WHERE id = $1`,
        [
          orderId,
          op.providerRef,
          op.userAction?.type === 'USSD_PROMPT' ? op.userAction.value : null,
          op.userAction?.type === 'REDIRECT' ? op.userAction.value : null,
        ],
      );
    } catch (err) {
      await this.pool.query(
        `UPDATE app.onramp_orders SET status='FAILED', failure_reason='PROVIDER_ERROR' WHERE id=$1 AND status='AWAITING_PAYMENT'`,
        [orderId],
      );
      if (err instanceof RampError && err.code === 'INVALID_REQUEST')
        throw new ApiProblem(400, 'VALIDATION_ERROR', 'Invalid payment details');
      throw new ApiProblem(503, 'PROVIDER_UNAVAILABLE', 'Payments are temporarily unavailable');
    }
    return this.getOnramp(userId, orderId);
  }

  /** Called with a verified provider event. Safe to call any number of times. */
  async handleCollectionEvent(e: RampEvent): Promise<void> {
    if (e.status === 'PENDING') return;
    if (e.status === 'FAILED') {
      await this.pool.query(
        `UPDATE app.onramp_orders SET status='FAILED', failure_reason=$2, next_action_at=NULL WHERE id=$1 AND status='AWAITING_PAYMENT'`,
        [e.orderId, ONRAMP_FAILURE[e.failureReason ?? 'PROVIDER_REJECTED']],
      );
      return;
    }
    await this.pool.query(
      `UPDATE app.onramp_orders SET status='COLLECTED' WHERE id=$1 AND status='AWAITING_PAYMENT'`,
      [e.orderId],
    );
    await this.trySettleOnramp(e.orderId);
  }

  /** Asks the settlement port whether the treasury has been paid, and credits the user if so. */
  async trySettleOnramp(orderId: string): Promise<void> {
    if (!this.settlement) return;
    const { rows } = await this.pool.query(
      `SELECT o.status, q.usdc_amount::text AS expected FROM app.onramp_orders o JOIN app.quotes q ON q.id = o.quote_id WHERE o.id = $1`,
      [orderId],
    );
    if (!rows[0] || rows[0].status !== 'COLLECTED') return;
    const settled = await this.settlement.confirm({
      id: orderId,
      expectedAmount: rows[0].expected,
    });
    if (settled) await this.completeOnramp(orderId, settled);
  }

  /**
   * Credits the user once settlement is CONFIRMED (called by the settlement matcher).
   * `settledAmount` is what the treasury really received. One transaction: order → COMPLETED + journal.
   */
  async completeOnramp(orderId: string, settledAmount: string): Promise<void> {
    await this.ledger.withTransaction(async (tx) => {
      const { rows } = await tx.client.query(
        `UPDATE app.onramp_orders o SET status='COMPLETED', completed_at=now(), next_action_at=NULL
           FROM app.quotes q
          WHERE o.id = $1 AND o.status IN ('COLLECTED','CREDITING_WALLET') AND q.id = o.quote_id
        RETURNING o.user_id, q.fiat_currency, q.fiat_amount::text AS fiat_amount, q.fee_amount::text AS fee`,
        [orderId],
      );
      const o = rows[0];
      if (!o) return; // already completed (replay) or not collected
      await tx.postJournal(
        templates.onrampSettle({
          orderId,
          userId: o.user_id,
          currency: o.fiat_currency,
          fiatAmount: o.fiat_amount,
          fee: o.fee,
          settlementAmount: settledAmount,
        }),
      );
    });
  }

  async getOnramp(userId: string, id: string) {
    const { rows } = await this.pool.query(
      `SELECT o.*, q.kind, q.fiat_currency, q.fiat_amount, q.to_currency, q.to_amount, q.rate, q.fee_amount, q.expires_at
         FROM app.onramp_orders o JOIN app.quotes q ON q.id = o.quote_id
        WHERE o.id = $1 AND o.user_id = $2`,
      [id, userId],
    );
    const r = rows[0];
    if (!r) throw new ApiProblem(404, 'NOT_FOUND', 'Order not found');
    return {
      id: r.id,
      status: r.status,
      quote: this.quoteDto({ ...r, id: r.quote_id }),
      checkout_url: r.checkout_url,
      ussd_instructions: r.ussd_instructions,
      provider_reference: r.yc_order_id,
      failure_reason: r.failure_reason,
      created_at: iso(r.created_at),
      completed_at: iso(r.completed_at),
    };
  }

  // ----- cash-out ----------------------------------------------------------------------------

  async createOfframp(userId: string, body: Record<string, unknown>) {
    const method = this.method(body.payout_method);
    const phone = this.phone(body.payee_msisdn);
    const name = typeof body.payee_name === 'string' ? body.payee_name.slice(0, 80) : null;
    const orderId = randomUUID();

    let quote: Row;
    try {
      quote = await this.ledger.withTransaction(async (tx) => {
        const q = await this.takeQuote(tx.client, userId, body.quote_id, 'OFFRAMP');
        await tx.client.query(
          `INSERT INTO app.offramp_orders (id, user_id, quote_id, payout_method, payee_msisdn, payee_name)
           VALUES ($1,$2,$3,$4,$5,$6)`,
          [orderId, userId, q.id, method, phone, name],
        );
        // Debit first: no funds → 402 and everything (incl. quote consumption) rolls back.
        await tx.postJournal(
          templates.offrampHold({
            orderId,
            userId,
            currency: q.fiat_currency,
            amount: this.plain(q.fiat_amount, q.fiat_currency),
          }),
        );
        return q;
      });
    } catch (err) {
      if (err instanceof InsufficientFundsError)
        throw new ApiProblem(402, 'INSUFFICIENT_FUNDS', 'Insufficient balance');
      throw err;
    }

    try {
      const op = await this.provider.createPayout({
        orderId,
        currency: quote.to_currency,
        amount: this.plain(quote.to_amount, quote.to_currency),
        phone,
        rail: railOf(method),
        network: NETWORK[method],
      });
      await this.pool.query(
        `UPDATE app.offramp_orders SET yc_order_id=$2, next_action_at = now() + interval '30 seconds' WHERE id=$1`,
        [orderId, op.providerRef],
      );
    } catch (err) {
      await this.failOfframp(orderId, 'PROVIDER_REJECTED');
      if (err instanceof RampError && err.code === 'INVALID_REQUEST')
        throw new ApiProblem(400, 'VALIDATION_ERROR', 'Invalid payout details');
      throw new ApiProblem(503, 'PROVIDER_UNAVAILABLE', 'Payments are temporarily unavailable');
    }
    return this.getOfframp(userId, orderId);
  }

  async handlePayoutEvent(e: RampEvent): Promise<void> {
    if (e.status === 'PENDING') return;
    if (e.status === 'FAILED')
      return this.failOfframp(e.orderId, e.failureReason ?? 'PROVIDER_REJECTED');
    await this.ledger.withTransaction(async (tx) => {
      const { rows } = await tx.client.query(
        `UPDATE app.offramp_orders o SET status='SETTLED', settled_at=now(), next_action_at=NULL
           FROM app.quotes q
          WHERE o.id=$1 AND o.status='PROCESSING' AND q.id=o.quote_id
        RETURNING q.fiat_currency, q.fiat_amount::text AS amount, q.fee_amount::text AS fee, q.usdc_amount::text AS settlement`,
        [e.orderId],
      );
      const o = rows[0];
      if (!o) return; // replay, or already refunded (a late success after a failure is an ops alert, not a double post)
      await tx.postJournal(
        templates.offrampSettle({
          orderId: e.orderId,
          currency: o.fiat_currency,
          amount: o.amount,
          fee: o.fee,
          settlementAmount: o.settlement,
        }),
      );
    });
  }

  /** Payout failed: give the user everything back, once. */
  private async failOfframp(orderId: string, reason: RampFailureReason): Promise<void> {
    await this.ledger.withTransaction(async (tx) => {
      const { rows } = await tx.client.query(
        `UPDATE app.offramp_orders o SET status='REFUNDED', failure_reason=$2, next_action_at=NULL
           FROM app.quotes q
          WHERE o.id=$1 AND o.status='PROCESSING' AND q.id=o.quote_id
        RETURNING o.user_id, q.fiat_currency, q.fiat_amount::text AS amount`,
        [orderId, OFFRAMP_FAILURE[reason]],
      );
      const o = rows[0];
      if (!o) return;
      await tx.postJournal(
        templates.offrampRefund({
          orderId,
          userId: o.user_id,
          currency: o.fiat_currency,
          amount: o.amount,
        }),
      );
    });
  }

  async getOfframp(userId: string, id: string) {
    const { rows } = await this.pool.query(
      `SELECT o.*, q.kind, q.fiat_currency, q.fiat_amount, q.to_currency, q.to_amount, q.rate, q.fee_amount, q.expires_at
         FROM app.offramp_orders o JOIN app.quotes q ON q.id = o.quote_id
        WHERE o.id = $1 AND o.user_id = $2`,
      [id, userId],
    );
    const r = rows[0];
    if (!r) throw new ApiProblem(404, 'NOT_FOUND', 'Order not found');
    return {
      id: r.id,
      status: r.status,
      quote: this.quoteDto({ ...r, id: r.quote_id }),
      provider_reference: r.yc_order_id,
      failure_reason: r.failure_reason,
      created_at: iso(r.created_at),
      settled_at: iso(r.settled_at),
    };
  }

  // ----- polling fallback (webhooks can be lost) -----------------------------------------------------

  /** Resumer: asks the provider about orders that are still waiting and applies the answer as an event. */
  async syncPending(limit = 50): Promise<number> {
    let n = 0;
    const on = await this.pool.query(
      `SELECT id, yc_order_id FROM app.onramp_orders WHERE status IN ('AWAITING_PAYMENT','COLLECTED') AND yc_order_id IS NOT NULL AND next_action_at <= now() ORDER BY next_action_at LIMIT $1`,
      [limit],
    );
    for (const r of on.rows) {
      const op = await this.provider.getOperation(r.yc_order_id);
      await this.handleCollectionEvent({
        eventId: `poll-${r.id}`,
        kind: 'COLLECTION',
        providerRef: op.providerRef,
        orderId: r.id,
        status: op.status,
        failureReason: op.failureReason,
      });
      n++;
    }
    const off = await this.pool.query(
      `SELECT id, yc_order_id FROM app.offramp_orders WHERE status='PROCESSING' AND yc_order_id IS NOT NULL AND next_action_at <= now() ORDER BY next_action_at LIMIT $1`,
      [limit],
    );
    for (const r of off.rows) {
      const op = await this.provider.getOperation(r.yc_order_id);
      await this.handlePayoutEvent({
        eventId: `poll-${r.id}`,
        kind: 'PAYOUT',
        providerRef: op.providerRef,
        orderId: r.id,
        status: op.status,
        failureReason: op.failureReason,
      });
      n++;
    }
    return n;
  }

  // ----- input helpers -------------------------------------------------------------------------------------

  private currency(v: unknown): RampCurrency {
    if (typeof v !== 'string' || !['XOF', 'XAF', 'NGN', 'GHS', 'KES'].includes(v))
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'Unsupported currency');
    return v as RampCurrency;
  }
  private money(v: unknown): string {
    if (typeof v !== 'string' || !/^[0-9]+(\.[0-9]{1,6})?$/.test(v))
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'Invalid amount');
    return v;
  }
  private method(v: unknown): PaymentMethod {
    if (typeof v !== 'string' || !(PAYMENT_METHODS as readonly string[]).includes(v))
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'Unsupported payment method');
    return v as PaymentMethod;
  }
  private phone(v: unknown): string {
    if (typeof v !== 'string' || !/^\+[1-9][0-9]{6,14}$/.test(v))
      throw new ApiProblem(400, 'VALIDATION_ERROR', 'Invalid phone number');
    return v;
  }
  /** NUMERIC text → plain decimal string without trailing zeros, within the currency's fiat decimals. */
  private plain(v: unknown, _currency: string): string {
    return String(v)
      .replace(/(\.\d*?)0+$/, '$1')
      .replace(/\.$/, '');
  }
}
