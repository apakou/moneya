import {
  Account,
  Asset,
  FeeBumpTransaction,
  Horizon,
  Memo,
  Operation,
  StrKey,
  Transaction,
  TransactionBuilder,
} from '@stellar/stellar-sdk';
import { ledgerToChainAmount } from '../amount';
import type {
  BuildPaymentParams,
  ChainAdapter,
  ChainTxResult,
  InboundPayment,
  SignedTx,
  Signer,
  UnsignedTx,
} from '../types';
import type { StellarConfig } from './config';

const DEFAULT_TIMEOUT_SECONDS = 90;

/** Operation ids are TOIDs: the low 12 bits hold the 1-based operation index. */
export function opIndexFromOperationId(operationId: string): number {
  return Number(BigInt(operationId) & 0xfffn) - 1;
}

function buildMemo(memo: BuildPaymentParams['memo']): Memo | undefined {
  if (!memo) return undefined;
  switch (memo.type) {
    case 'id':
      return Memo.id(memo.value);
    case 'text':
      return Memo.text(memo.value);
    case 'hash':
      return Memo.hash(memo.value);
  }
}

function toBase64(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64');
}

function toHex(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('hex');
}

/**
 * Stellar implementation of {@link ChainAdapter}.
 *
 * Offline part (build, sign, hash, fee-bump, address checks) is unit-tested.
 * Network part (submit, getTx, getSequence, streamPayments) is implemented but
 * NOT verified against a live network yet: it needs the testnet spike (STL-00).
 */
export class StellarAdapter implements ChainAdapter {
  private readonly usdc: Asset;
  private readonly servers: Horizon.Server[];

  constructor(private readonly config: StellarConfig) {
    this.usdc = new Asset(config.usdcCode, config.usdcIssuer);
    this.servers = config.horizonUrls.map((url) => new Horizon.Server(url));
  }

  isValidAddress(address: string): boolean {
    return StrKey.isValidEd25519PublicKey(address) || StrKey.isValidMed25519PublicKey(address);
  }

  // ----- offline ----------------------------------------------------------

  buildPayment(params: BuildPaymentParams): UnsignedTx {
    if (!this.isValidAddress(params.destination)) {
      throw new Error('Invalid destination address');
    }
    const now = params.now ?? new Date();
    const timeout = params.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS;
    const maxTime = new Date(now.getTime() + timeout * 1000);

    const builder = new TransactionBuilder(
      new Account(params.sourceAccount, params.sourceSequence),
      {
        fee: String(this.config.baseFeeStroops),
        networkPassphrase: this.config.networkPassphrase,
      },
    )
      .setTimebounds(0, Math.floor(maxTime.getTime() / 1000))
      .addOperation(
        Operation.payment({
          source: params.paymentSource,
          destination: params.destination,
          asset: this.usdc,
          amount: ledgerToChainAmount(params.amount),
        }),
      );
    const memo = buildMemo(params.memo);
    if (memo) builder.addMemo(memo);

    const tx = builder.build();
    const requiredSigners = [...new Set([params.sourceAccount, params.paymentSource])];
    return {
      hash: toHex(tx.hash()),
      xdr: tx.toXDR(),
      signaturePayload: new Uint8Array(tx.hash()),
      maxTime,
      sourceAccount: params.sourceAccount,
      requiredSigners,
    };
  }

  async signPayment(
    unsigned: UnsignedTx,
    signers: readonly Signer[],
    feeSource?: Signer,
  ): Promise<SignedTx> {
    const tx = TransactionBuilder.fromXDR(unsigned.xdr, this.config.networkPassphrase);
    if (!(tx instanceof Transaction)) throw new Error('Expected a plain transaction');

    const byKey = new Map(signers.map((s) => [s.publicKey, s]));
    for (const required of unsigned.requiredSigners) {
      const signer = byKey.get(required);
      if (!signer) throw new Error(`Missing signer for ${required}`);
      tx.addSignature(required, toBase64(await signer.sign(unsigned.signaturePayload)));
    }

    if (!feeSource) {
      return { hash: unsigned.hash, xdr: tx.toXDR(), maxTime: unsigned.maxTime };
    }

    // Fee-bump: the INNER hash stays the idempotency key; the outer hash differs.
    const bump = TransactionBuilder.buildFeeBumpTransaction(
      feeSource.publicKey,
      String(this.config.baseFeeStroops * 2),
      tx,
      this.config.networkPassphrase,
    );
    bump.addSignature(
      feeSource.publicKey,
      toBase64(await feeSource.sign(new Uint8Array(bump.hash()))),
    );
    return {
      hash: unsigned.hash,
      outerHash: toHex(bump.hash()),
      xdr: bump.toXDR(),
      maxTime: unsigned.maxTime,
    };
  }

  // ----- network (verify with STL-00) -------------------------------------

  /** Try each provider in order; only network-level failures trigger failover. */
  private async withFailover<T>(fn: (server: Horizon.Server) => Promise<T>): Promise<T> {
    let lastError: unknown;
    for (const server of this.servers) {
      try {
        return await fn(server);
      } catch (err) {
        if (isDefinitiveNetworkAnswer(err)) throw err;
        lastError = err;
      }
    }
    throw lastError instanceof Error ? lastError : new Error('All Horizon providers failed');
  }

  async submit(xdr: string): Promise<ChainTxResult> {
    const tx = TransactionBuilder.fromXDR(xdr, this.config.networkPassphrase);
    const innerHash = toHex((tx instanceof FeeBumpTransaction ? tx.innerTransaction : tx).hash());
    try {
      const res = await this.withFailover((s) => s.submitTransaction(tx));
      return { hash: innerHash, status: 'CONFIRMED', ledgerSequence: res.ledger };
    } catch (err) {
      const codes = resultCodes(err);
      if (codes) return { hash: innerHash, status: 'FAILED', errorCode: codes };
      throw err; // unknown outcome: caller resubmits the SAME xdr or looks the hash up
    }
  }

  async getTx(hash: string): Promise<ChainTxResult> {
    try {
      const rec = await this.withFailover((s) => s.transactions().transaction(hash).call());
      return {
        hash,
        status: rec.successful ? 'CONFIRMED' : 'FAILED',
        ledgerSequence: rec.ledger_attr,
      };
    } catch (err) {
      if (httpStatus(err) === 404) return { hash, status: 'NOT_FOUND' };
      throw err;
    }
  }

  async getSequence(account: string): Promise<string> {
    const acc = await this.withFailover((s) => s.loadAccount(account));
    return acc.sequenceNumber();
  }

  streamPayments(
    account: string,
    cursor: string | undefined,
    onPayment: (p: InboundPayment) => Promise<void> | void,
    onError: (err: unknown) => void,
  ): () => void {
    const server = this.servers[0];
    if (!server) throw new Error('No Horizon provider configured');
    const close = server
      .payments()
      .forAccount(account)
      .cursor(cursor ?? 'now')
      .stream({
        onmessage: (record) => {
          const rec = record as unknown as Horizon.ServerApi.PaymentOperationRecord;
          if (rec.type !== 'payment' || rec.to !== account) return;
          void (async () => {
            try {
              const tx = await rec.transaction();
              await onPayment({
                txHash: rec.transaction_hash,
                operationId: rec.id,
                opIndex: opIndexFromOperationId(rec.id),
                from: rec.from,
                to: rec.to,
                assetCode: rec.asset_type === 'native' ? 'XLM' : (rec.asset_code ?? ''),
                assetIssuer: rec.asset_issuer,
                amount: rec.amount,
                memo: tx.memo,
                pagingToken: rec.paging_token,
              });
            } catch (err) {
              onError(err);
            }
          })();
        },
        onerror: onError,
      });
    return close;
  }
}

function httpStatus(err: unknown): number | undefined {
  const e = err as { response?: { status?: number }; status?: number } | undefined;
  return e?.response?.status ?? e?.status;
}

/** A 4xx answer is the network's definitive reply; do not fail over on it. */
function isDefinitiveNetworkAnswer(err: unknown): boolean {
  const status = httpStatus(err);
  return status !== undefined && status >= 400 && status < 500;
}

function resultCodes(err: unknown): string | undefined {
  const extras = (err as { response?: { data?: { extras?: { result_codes?: unknown } } } })
    ?.response?.data?.extras?.result_codes as
    { transaction?: string; operations?: string[] } | undefined;
  if (!extras) return undefined;
  return [extras.transaction, ...(extras.operations ?? [])].filter(Boolean).join(',');
}
