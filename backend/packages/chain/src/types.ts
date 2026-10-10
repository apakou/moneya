/**
 * Chain abstraction (plan §3, ticket STL-01).
 *
 * Only the backend uses this. Nothing here may leak to the API or the client
 * (plan §1.1). The interface exists so a second chain is a drop-in later.
 */

/** Decimal string. Ledger amounts are 6 dp; the adapter converts at its boundary. */
export type LedgerAmount = string;

export type MemoSpec =
  | { type: 'id'; value: string }
  | { type: 'text'; value: string }
  | { type: 'hash'; value: string /* 64 hex chars */ };

export interface BuildPaymentParams {
  /** Transaction source: a channel account holding its own sequence number. */
  sourceAccount: string;
  /** Current sequence number of `sourceAccount` (the tx will use +1). */
  sourceSequence: string;
  /** Account that actually sends the funds (operation source), e.g. the hot account. */
  paymentSource: string;
  destination: string;
  amount: LedgerAmount;
  memo?: MemoSpec;
  /** Seconds until the transaction expires (timebounds). Default 90. */
  timeoutSeconds?: number;
  /** Injectable clock for deterministic tests. */
  now?: Date;
}

/** A transaction that is fully built and hashed but NOT yet signed. */
export interface UnsignedTx {
  hash: string;
  /** Unsigned envelope, base64 XDR. */
  xdr: string;
  /** Transaction hash payload to sign (32 bytes). */
  signaturePayload: Uint8Array;
  maxTime: Date;
  sourceAccount: string;
  /** Public keys whose signatures the network requires (tx source + payment source). */
  requiredSigners: readonly string[];
}

/** A signed transaction ready to persist, then submit (resubmitting it is idempotent). */
export interface SignedTx {
  /**
   * Hash of the INNER transaction. It is known before submit and never changes,
   * so it is the idempotency key we persist (`chain_txs.tx_hash`).
   */
  hash: string;
  /** Hash of the fee-bump envelope when one was applied (differs from `hash`). */
  outerHash?: string;
  xdr: string;
  maxTime: Date;
}

/**
 * Signing abstraction. The MVP signer will sit on a KMS/HSM or custody API
 * (decision D4); tests use a local keypair.
 */
export interface Signer {
  readonly publicKey: string;
  sign(payload: Uint8Array): Promise<Uint8Array>;
}

export type ChainTxStatus = 'NOT_FOUND' | 'CONFIRMED' | 'FAILED';

export interface ChainTxResult {
  hash: string;
  status: ChainTxStatus;
  ledgerSequence?: number;
  /** Internal diagnostics only; never returned to clients. */
  errorCode?: string;
}

export interface InboundPayment {
  txHash: string;
  /** Network operation id: globally unique, the primary dedupe key. */
  operationId: string;
  /** Zero-based operation index within the transaction (derived from the operation id). */
  opIndex: number;
  from: string;
  to: string;
  assetCode: string;
  assetIssuer: string | undefined;
  /** 7-dp decimal string as received from the network. */
  amount: string;
  memo: string | undefined;
  pagingToken: string;
}

export interface ChainAdapter {
  isValidAddress(address: string): boolean;
  buildPayment(params: BuildPaymentParams): UnsignedTx;
  /**
   * Sign with every required signer and, when `feeSource` is given, wrap in a
   * fee-bump. Throws if a required signer is missing.
   */
  signPayment(tx: UnsignedTx, signers: readonly Signer[], feeSource?: Signer): Promise<SignedTx>;
  /** Idempotent: submitting the same XDR twice never moves funds twice. */
  submit(xdr: string): Promise<ChainTxResult>;
  getTx(hash: string): Promise<ChainTxResult>;
  getSequence(account: string): Promise<string>;
  streamPayments(
    account: string,
    cursor: string | undefined,
    onPayment: (p: InboundPayment) => Promise<void> | void,
    onError: (err: unknown) => void,
  ): () => void;
}
