import { add, isPositive, negate } from './money';
import { journalIdFor } from './ids';
import { JournalInvalidError, type Journal } from './types';

/**
 * Journal templates (ledger.md §4) under ADR 0001 D7: user balances, escrow and
 * fees are all in the user's fiat currency. Cross-user templates are single-currency.
 *
 * Ramp templates (below) replace the Solana/Yellow-Card ones in ledger.md §4.2/4.3.
 * Under D7 (ADR 0001) user balances/fees are fiat; the treasury (MONEYA_HOT_WALLET)
 * is in the settlement unit; FX_POSITION accounts (one per currency) are the
 * counterparty of every conversion, so each currency balances on its own. Net
 * treasury exposure = treasury balance vs the sum of user balances at the current rate.
 */

const wallet = (userId: string, currency: string) => ({
  kind: 'USER_WALLET' as const,
  userId,
  currency,
});
const global = (
  kind: 'FEE_REVENUE' | 'MONEYA_ESCROW' | 'SUSPENSE' | 'FX_POSITION' | 'MONEYA_HOT_WALLET',
  currency: string,
) => ({ kind, currency });

/** Internal settlement unit of the treasury. Never shown to users (plan §1.1). */
export const SETTLEMENT_UNIT = 'USDC';

function requirePositive(amount: string, fee = '0'): void {
  if (!isPositive(amount)) throw new JournalInvalidError('amount must be > 0');
  if (fee.startsWith('-')) throw new JournalInvalidError('fee must be >= 0');
}

/** §4.1 — P2P transfer settled between two MoneyA users (same currency). */
export function p2pTransfer(p: {
  transferId: string;
  senderId: string;
  recipientId: string;
  currency: string;
  amount: string;
  fee: string;
}): Journal {
  requirePositive(p.amount, p.fee);
  if (p.senderId === p.recipientId)
    throw new JournalInvalidError('sender and recipient must differ');
  const entries: Journal['entries'] = [
    {
      account: wallet(p.senderId, p.currency),
      amount: negate(add(p.amount, p.fee)),
      memo: 'P2P send',
    },
    { account: wallet(p.recipientId, p.currency), amount: p.amount, memo: 'P2P receive' },
  ];
  if (isPositive(p.fee)) {
    entries.push({
      account: global('FEE_REVENUE', p.currency),
      amount: p.fee,
      memo: `P2P fee, transfer ${p.transferId}`,
    });
  }
  return {
    journalId: journalIdFor(`TRANSFER:${p.transferId}:SETTLE`),
    ref: { refType: 'TRANSFER', refId: p.transferId },
    entries,
  };
}

/** §4.4.1 — recipient is not a user yet: sender's amount + fee moves to escrow. */
export function escrowHold(p: {
  transferId: string;
  senderId: string;
  currency: string;
  amount: string;
  fee: string;
}): Journal {
  requirePositive(p.amount, p.fee);
  const total = add(p.amount, p.fee);
  return {
    journalId: journalIdFor(`TRANSFER:${p.transferId}:HOLD`),
    ref: { refType: 'TRANSFER', refId: p.transferId },
    entries: [
      { account: wallet(p.senderId, p.currency), amount: negate(total), memo: 'Unclaimed send' },
      {
        account: global('MONEYA_ESCROW', p.currency),
        amount: total,
        memo: `Escrow hold, transfer ${p.transferId}`,
      },
    ],
  };
}

/** §4.4.2 — recipient claimed: escrow releases to them, fee is earned. */
export function escrowRelease(p: {
  transferId: string;
  recipientId: string;
  currency: string;
  amount: string;
  fee: string;
}): Journal {
  requirePositive(p.amount, p.fee);
  const entries: Journal['entries'] = [
    {
      account: global('MONEYA_ESCROW', p.currency),
      amount: negate(add(p.amount, p.fee)),
      memo: `Escrow released, transfer ${p.transferId}`,
    },
    { account: wallet(p.recipientId, p.currency), amount: p.amount, memo: 'P2P receive (claimed)' },
  ];
  if (isPositive(p.fee)) {
    entries.push({
      account: global('FEE_REVENUE', p.currency),
      amount: p.fee,
      memo: 'P2P fee (claim redeemed)',
    });
  }
  return {
    journalId: journalIdFor(`TRANSFER:${p.transferId}:CLAIM`),
    ref: { refType: 'TRANSFER', refId: p.transferId },
    entries,
  };
}

/** §4.4.3/4.4.4 — expiry or cancellation: sender gets the full amount + fee back. */
export function escrowRefund(p: {
  transferId: string;
  senderId: string;
  currency: string;
  amount: string;
  fee: string;
  reason: 'EXPIRED' | 'CANCELLED';
}): Journal {
  requirePositive(p.amount, p.fee);
  const total = add(p.amount, p.fee);
  return {
    journalId: journalIdFor(`TRANSFER:${p.transferId}:REFUND`),
    ref: { refType: 'CLAIM_REFUND', refId: p.transferId },
    entries: [
      {
        account: global('MONEYA_ESCROW', p.currency),
        amount: negate(total),
        memo: `Escrow ${p.reason.toLowerCase()}, transfer ${p.transferId}`,
      },
      {
        account: wallet(p.senderId, p.currency),
        amount: total,
        memo: 'Unclaimed refund, full incl. fee',
      },
    ],
  };
}

/** §4.5 — operator-approved correction against SUSPENSE. `delta` is signed, applied to the user. */
export function reconciliationAdjustment(p: {
  incidentId: string;
  userId: string;
  currency: string;
  delta: string;
  memo: string;
}): Journal {
  if (!p.memo.trim()) throw new JournalInvalidError('A reconciliation adjustment needs a memo');
  return {
    journalId: journalIdFor(`RECONCILIATION_ADJ:${p.incidentId}:${p.userId}`),
    ref: { refType: 'RECONCILIATION_ADJ', refId: p.incidentId },
    entries: [
      { account: wallet(p.userId, p.currency), amount: p.delta, memo: `Recon adj: ${p.memo}` },
      {
        account: global('SUSPENSE', p.currency),
        amount: negate(p.delta),
        memo: `Recon adj ${p.incidentId}`,
      },
    ],
  };
}

// ----- Ramps (D7) ---------------------------------------------------------------------

function requireSettlement(settlementAmount: string): void {
  if (!isPositive(settlementAmount)) throw new JournalInvalidError('settlementAmount must be > 0');
}

/**
 * Top-up settled (fiat collected AND the treasury's settlement confirmed). Nothing is posted
 * earlier: the ledger records only confirmed settlement. The user is credited fiat net of fee.
 *
 *   fiat:       user +(X-F)   fee +F   FX_POSITION(fiat) -X
 *   settlement: treasury +S   FX_POSITION(settlement) -S
 */
export function onrampSettle(p: {
  orderId: string;
  userId: string;
  currency: string;
  /** Fiat the user paid (X). */
  fiatAmount: string;
  /** All-in fee in the same fiat (F), may be 0 but < X. */
  fee: string;
  /** Settlement-unit amount received by the treasury (S). */
  settlementAmount: string;
}): Journal {
  requirePositive(p.fiatAmount, p.fee);
  requireSettlement(p.settlementAmount);
  const credit = add(p.fiatAmount, negate(p.fee));
  if (!isPositive(credit)) throw new JournalInvalidError('fee must be smaller than the amount');
  const entries: Journal['entries'] = [
    {
      account: wallet(p.userId, p.currency),
      amount: credit,
      memo: `Top-up ${p.fiatAmount} ${p.currency}`,
    },
    {
      account: global('FX_POSITION', p.currency),
      amount: negate(p.fiatAmount),
      memo: `Top-up, order ${p.orderId}`,
    },
    {
      account: global('MONEYA_HOT_WALLET', SETTLEMENT_UNIT),
      amount: p.settlementAmount,
      memo: `Settlement in, order ${p.orderId}`,
    },
    {
      account: global('FX_POSITION', SETTLEMENT_UNIT),
      amount: negate(p.settlementAmount),
      memo: `Top-up, order ${p.orderId}`,
    },
  ];
  if (isPositive(p.fee)) {
    entries.push({
      account: global('FEE_REVENUE', p.currency),
      amount: p.fee,
      memo: `Top-up fee, order ${p.orderId}`,
    });
  }
  return {
    journalId: journalIdFor(`ONRAMP_ORDER:${p.orderId}:SETTLE`),
    ref: { refType: 'ONRAMP_ORDER', refId: p.orderId },
    entries,
  };
}

/** Cash-out requested: the full debit (Y, fee included) leaves the user's balance and waits in SUSPENSE. */
export function offrampHold(p: {
  orderId: string;
  userId: string;
  currency: string;
  amount: string;
}): Journal {
  requirePositive(p.amount);
  return {
    journalId: journalIdFor(`OFFRAMP_ORDER:${p.orderId}:HOLD`),
    ref: { refType: 'OFFRAMP_ORDER', refId: p.orderId },
    entries: [
      {
        account: wallet(p.userId, p.currency),
        amount: negate(p.amount),
        memo: `Cash-out, order ${p.orderId}`,
      },
      {
        account: global('SUSPENSE', p.currency),
        amount: p.amount,
        memo: `Cash-out hold, order ${p.orderId}`,
      },
    ],
  };
}

/**
 * Cash-out paid out by the provider: the hold is released, the fee is earned and the
 * treasury pays the settlement unit.
 *
 *   fiat:       SUSPENSE -Y   FX_POSITION(fiat) +(Y-F)   fee +F
 *   settlement: treasury -S   FX_POSITION(settlement) +S
 */
export function offrampSettle(p: {
  orderId: string;
  currency: string;
  /** Total debited from the user (Y). */
  amount: string;
  fee: string;
  settlementAmount: string;
}): Journal {
  requirePositive(p.amount, p.fee);
  requireSettlement(p.settlementAmount);
  const net = add(p.amount, negate(p.fee));
  if (!isPositive(net)) throw new JournalInvalidError('fee must be smaller than the amount');
  const entries: Journal['entries'] = [
    {
      account: global('SUSPENSE', p.currency),
      amount: negate(p.amount),
      memo: `Cash-out settled, order ${p.orderId}`,
    },
    {
      account: global('FX_POSITION', p.currency),
      amount: net,
      memo: `Cash-out, order ${p.orderId}`,
    },
    {
      account: global('MONEYA_HOT_WALLET', SETTLEMENT_UNIT),
      amount: negate(p.settlementAmount),
      memo: `Settlement out, order ${p.orderId}`,
    },
    {
      account: global('FX_POSITION', SETTLEMENT_UNIT),
      amount: p.settlementAmount,
      memo: `Cash-out, order ${p.orderId}`,
    },
  ];
  if (isPositive(p.fee)) {
    entries.push({
      account: global('FEE_REVENUE', p.currency),
      amount: p.fee,
      memo: `Cash-out fee, order ${p.orderId}`,
    });
  }
  return {
    journalId: journalIdFor(`OFFRAMP_ORDER:${p.orderId}:SETTLE`),
    ref: { refType: 'OFFRAMP_ORDER', refId: p.orderId },
    entries,
  };
}

/** Cash-out failed at the provider: the user gets the full amount back, fee included. */
export function offrampRefund(p: {
  orderId: string;
  userId: string;
  currency: string;
  amount: string;
}): Journal {
  requirePositive(p.amount);
  return {
    journalId: journalIdFor(`OFFRAMP_ORDER:${p.orderId}:REFUND`),
    ref: { refType: 'OFFRAMP_ORDER', refId: p.orderId },
    entries: [
      {
        account: global('SUSPENSE', p.currency),
        amount: negate(p.amount),
        memo: `Cash-out reversed, order ${p.orderId}`,
      },
      { account: wallet(p.userId, p.currency), amount: p.amount, memo: 'Cash-out refunded' },
    ],
  };
}
