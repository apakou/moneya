export type FiatCurrency = 'XOF' | 'XAF' | 'NGN' | 'GHS' | 'KES';

export type AccountKind =
  | 'USER_WALLET'
  | 'MONEYA_HOT_WALLET'
  | 'MONEYA_ESCROW'
  | 'YC_RECEIVABLE'
  | 'YC_PAYABLE'
  | 'FEE_REVENUE'
  | 'SUSPENSE'
  | 'FX_POSITION';

/** Identity of a ledger account: (kind, owner, currency). Global accounts have no userId. */
export interface AccountRef {
  kind: AccountKind;
  userId?: string;
  currency: string;
}

export interface EntrySpec {
  account: AccountRef;
  /** Signed decimal string, max 6 dp. + credit, - debit (ledger.md §3.1). Never zero. */
  amount: string;
  memo?: string;
}

export type RefType =
  'TRANSFER' | 'ONRAMP_ORDER' | 'OFFRAMP_ORDER' | 'CLAIM_REFUND' | 'RECONCILIATION_ADJ';

export interface JournalRef {
  refType: RefType;
  refId: string;
}

export interface Journal {
  /** Deterministic id from {@link journalIdFor}. */
  journalId: string;
  ref: JournalRef;
  entries: EntrySpec[];
}

export class JournalInvalidError extends Error {}
export class JournalAlreadyPostedError extends Error {
  constructor(readonly journalId: string) {
    super(`Journal ${journalId} was already posted`);
  }
}
export class InsufficientFundsError extends Error {
  constructor(readonly userId: string) {
    super('Insufficient funds');
  }
}
