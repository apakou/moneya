/**
 * Fiat ramp port (plan §3, M6/M7). Collect money from a user's mobile-money/bank
 * account (top-up) or pay it out to one (cash-out).
 *
 * The interface is fiat-only on purpose (plan §1.1): whatever the provider does
 * to settle with us behind the scenes is not part of this contract. A real
 * provider (decision D2, pending RMP-00) is one adapter implementing it and must
 * pass `rampProviderContract` in test/contract.ts.
 */

export type RampCurrency = 'XOF' | 'XAF' | 'NGN' | 'GHS' | 'KES';
export type RampRail = 'MOBILE_MONEY' | 'BANK';

/** Fiat decimals shown/accepted per currency (ledger keeps 6 dp internally). */
export const FIAT_DECIMALS: Record<RampCurrency, number> = {
  XOF: 0,
  XAF: 0,
  NGN: 2,
  GHS: 2,
  KES: 2,
};

export type RampStatus = 'PENDING' | 'SUCCEEDED' | 'FAILED';

/** Provider-agnostic reasons; no raw provider text ever leaves the adapter. */
export type RampFailureReason =
  'PROVIDER_REJECTED' | 'INSUFFICIENT_FUNDS' | 'TIMEOUT' | 'INVALID_ACCOUNT' | 'LIMIT_EXCEEDED';

export interface RampRequest {
  /** Our order id (UUID). The idempotency key: the same id never creates two operations. */
  orderId: string;
  currency: RampCurrency;
  /** Decimal string in the currency's fiat decimals. */
  amount: string;
  /** E.164 phone of the mobile-money wallet (or account holder for BANK). */
  phone: string;
  rail: RampRail;
  /** Operator hint, e.g. MTN / VODAFONE / AIRTELTIGO. */
  network?: string;
}

export interface RampOperation {
  providerRef: string;
  status: RampStatus;
  failureReason?: RampFailureReason;
  /** How the user completes a collection (USSD prompt text, redirect), when applicable. */
  userAction?: { type: 'USSD_PROMPT' | 'REDIRECT'; value: string };
}

export interface RampEvent {
  /** Unique per delivery attempt group; dedupe key (audit.webhook_events). */
  eventId: string;
  kind: 'COLLECTION' | 'PAYOUT';
  providerRef: string;
  orderId: string;
  status: RampStatus;
  failureReason?: RampFailureReason;
}

export class RampError extends Error {
  constructor(
    readonly code:
      'INVALID_REQUEST' | 'UNSUPPORTED' | 'INVALID_SIGNATURE' | 'NOT_FOUND' | 'UNAVAILABLE',
    message: string,
  ) {
    super(message);
  }
}

export interface RampProvider {
  readonly name: string;
  /** Top-up: ask the user's wallet for payment. Idempotent on `orderId`. */
  createCollection(req: RampRequest): Promise<RampOperation>;
  /** Cash-out: pay the user's wallet. Idempotent on `orderId`. */
  createPayout(req: RampRequest): Promise<RampOperation>;
  getOperation(providerRef: string): Promise<RampOperation>;
  /** Verifies the signature and returns the event, or throws RampError('INVALID_SIGNATURE'). */
  parseWebhook(headers: Record<string, string | undefined>, rawBody: string): RampEvent;
}

export function validateRequest(req: RampRequest): void {
  const decimals = FIAT_DECIMALS[req.currency];
  if (decimals === undefined)
    throw new RampError('UNSUPPORTED', `Unsupported currency ${String(req.currency)}`);
  const m = typeof req.amount === 'string' ? /^([0-9]+)(?:\.([0-9]+))?$/.exec(req.amount) : null;
  const frac = m?.[2] ?? '';
  const positive = m ? /[1-9]/.test(m[1]! + frac) : false;
  const canonicalInt = m ? m[1] === '0' || !m[1]!.startsWith('0') : false;
  if (!m || !positive || !canonicalInt || frac.length > decimals) {
    throw new RampError(
      'INVALID_REQUEST',
      `amount must be a positive decimal with at most ${decimals} decimals`,
    );
  }
  if (!/^\+[1-9][0-9]{6,14}$/.test(req.phone))
    throw new RampError('INVALID_REQUEST', 'phone must be E.164');
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(req.orderId)) {
    throw new RampError('INVALID_REQUEST', 'orderId must be a UUID');
  }
}
