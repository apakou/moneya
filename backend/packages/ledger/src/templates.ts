import { add, isPositive, negate } from './money';
import { journalIdFor } from './ids';
import { JournalInvalidError, type Journal } from './types';

/**
 * Journal templates (ledger.md §4) under ADR 0001 D7: user balances, escrow and
 * fees are all in the user's fiat currency. A single-currency journal here;
 * cross-currency conversion journals (ramps) arrive with M6/M7.
 *
 * Ramp templates (§4.2 onramp, §4.3 offramp) are intentionally NOT here: they
 * depend on the provider integration (RMP-00) and the D7 conversion design.
 */

const wallet = (userId: string, currency: string) => ({
  kind: 'USER_WALLET' as const,
  userId,
  currency,
});
const global = (kind: 'FEE_REVENUE' | 'MONEYA_ESCROW' | 'SUSPENSE', currency: string) => ({
  kind,
  currency,
});

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
