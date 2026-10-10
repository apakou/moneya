import {
  Keypair,
  Networks,
  Operation,
  Transaction,
  TransactionBuilder,
  FeeBumpTransaction,
} from '@stellar/stellar-sdk';
import {
  KeypairSigner,
  loadStellarConfig,
  opIndexFromOperationId,
  StellarAdapter,
} from '@moneya/chain';
import type { StellarConfig } from '@moneya/chain';

const issuer = Keypair.random().publicKey();
const config: StellarConfig = {
  network: 'TESTNET',
  networkPassphrase: Networks.TESTNET,
  horizonUrls: ['https://horizon.invalid'],
  usdcCode: 'USDC',
  usdcIssuer: issuer,
  baseFeeStroops: 100,
};
const adapter = new StellarAdapter(config);
const NOW = new Date('2026-10-10T12:00:00Z');

function setup() {
  const channel = KeypairSigner.random();
  const hot = KeypairSigner.random();
  const dest = Keypair.random().publicKey();
  return { channel, hot, dest };
}

describe('StellarAdapter (offline)', () => {
  it('validates addresses', () => {
    expect(adapter.isValidAddress(Keypair.random().publicKey())).toBe(true);
    expect(adapter.isValidAddress(Keypair.random().secret())).toBe(false);
    expect(adapter.isValidAddress('not-an-address')).toBe(false);
    expect(adapter.isValidAddress('')).toBe(false);
  });

  it('builds a USDC payment whose hash is known before signing and is deterministic', () => {
    const { channel, hot, dest } = setup();
    const params = {
      sourceAccount: channel.publicKey,
      sourceSequence: '100',
      paymentSource: hot.publicKey,
      destination: dest,
      amount: '12.5',
      now: NOW,
    };
    const a = adapter.buildPayment(params);
    const b = adapter.buildPayment(params);
    expect(a.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(a.hash).toBe(b.hash);
    expect(a.xdr).toBe(b.xdr);

    const tx = TransactionBuilder.fromXDR(a.xdr, Networks.TESTNET) as Transaction;
    expect(Buffer.from(tx.hash()).toString('hex')).toBe(a.hash);
    expect(tx.sequence).toBe('101'); // source sequence + 1
    expect(tx.source).toBe(channel.publicKey);
    const op = tx.operations[0] as Operation.Payment;
    expect(op.type).toBe('payment');
    expect(op.source).toBe(hot.publicKey);
    expect(op.destination).toBe(dest);
    expect(op.amount).toBe('12.5000000');
    expect(op.asset.getCode()).toBe('USDC');
    expect(op.asset.getIssuer()).toBe(issuer);
  });

  it('sets timebounds so a stuck transaction expires deterministically', () => {
    const { channel, hot, dest } = setup();
    const built = adapter.buildPayment({
      sourceAccount: channel.publicKey,
      sourceSequence: '1',
      paymentSource: hot.publicKey,
      destination: dest,
      amount: '1',
      timeoutSeconds: 60,
      now: NOW,
    });
    const tx = TransactionBuilder.fromXDR(built.xdr, Networks.TESTNET) as Transaction;
    expect(tx.timeBounds?.maxTime).toBe(String(Math.floor(NOW.getTime() / 1000) + 60));
    expect(tx.timeBounds?.minTime).toBe('0');
    expect(built.maxTime.toISOString()).toBe('2026-10-10T12:01:00.000Z');
  });

  it('attaches each memo type', () => {
    const { channel, hot, dest } = setup();
    const base = {
      sourceAccount: channel.publicKey,
      sourceSequence: '1',
      paymentSource: hot.publicKey,
      destination: dest,
      amount: '1',
      now: NOW,
    };
    const memoOf = (memo: Parameters<typeof adapter.buildPayment>[0]['memo']) =>
      (
        TransactionBuilder.fromXDR(
          adapter.buildPayment({ ...base, memo }).xdr,
          Networks.TESTNET,
        ) as Transaction
      ).memo;
    expect(memoOf({ type: 'id', value: '12345' }).value).toBe('12345');
    expect(memoOf({ type: 'text', value: 'order-42' }).value?.toString()).toBe('order-42');
    expect(memoOf({ type: 'hash', value: 'ab'.repeat(32) }).type).toBe('hash');
    expect(memoOf(undefined).type).toBe('none');
  });

  it('rejects sub-micro amounts and invalid destinations', () => {
    const { channel, hot, dest } = setup();
    const base = {
      sourceAccount: channel.publicKey,
      sourceSequence: '1',
      paymentSource: hot.publicKey,
      destination: dest,
      amount: '1',
      now: NOW,
    };
    expect(() => adapter.buildPayment({ ...base, amount: '0.0000001' })).toThrow();
    expect(() => adapter.buildPayment({ ...base, amount: '0' })).toThrow();
    expect(() => adapter.buildPayment({ ...base, destination: 'GBAD' })).toThrow(
      'Invalid destination',
    );
  });

  it('signs with every required signer and the signatures verify against the hash', async () => {
    const { channel, hot, dest } = setup();
    const built = adapter.buildPayment({
      sourceAccount: channel.publicKey,
      sourceSequence: '7',
      paymentSource: hot.publicKey,
      destination: dest,
      amount: '3',
      now: NOW,
    });
    expect([...built.requiredSigners].sort()).toEqual([channel.publicKey, hot.publicKey].sort());

    const signed = await adapter.signPayment(built, [channel, hot]);
    expect(signed.hash).toBe(built.hash); // signing never changes the idempotency key
    const tx = TransactionBuilder.fromXDR(signed.xdr, Networks.TESTNET) as Transaction;
    expect(tx.signatures).toHaveLength(2);
    for (const sig of tx.signatures) {
      const ok = [channel.publicKey, hot.publicKey].some((pk) =>
        Keypair.fromPublicKey(pk).verify(Buffer.from(tx.hash()), sig.signature()),
      );
      expect(ok).toBe(true);
    }
  });

  it('requires only one signature when the source and payment source are the same', async () => {
    const { hot, dest } = setup();
    const built = adapter.buildPayment({
      sourceAccount: hot.publicKey,
      sourceSequence: '7',
      paymentSource: hot.publicKey,
      destination: dest,
      amount: '3',
      now: NOW,
    });
    expect(built.requiredSigners).toEqual([hot.publicKey]);
    const signed = await adapter.signPayment(built, [hot]);
    expect(
      (TransactionBuilder.fromXDR(signed.xdr, Networks.TESTNET) as Transaction).signatures,
    ).toHaveLength(1);
  });

  it('refuses to sign when a required signer is missing', async () => {
    const { channel, hot, dest } = setup();
    const built = adapter.buildPayment({
      sourceAccount: channel.publicKey,
      sourceSequence: '7',
      paymentSource: hot.publicKey,
      destination: dest,
      amount: '3',
      now: NOW,
    });
    await expect(adapter.signPayment(built, [channel])).rejects.toThrow(/Missing signer/);
  });

  it('wraps in a fee-bump while keeping the inner hash as the idempotency key', async () => {
    const { channel, hot, dest } = setup();
    const feeSource = KeypairSigner.random();
    const built = adapter.buildPayment({
      sourceAccount: channel.publicKey,
      sourceSequence: '7',
      paymentSource: hot.publicKey,
      destination: dest,
      amount: '3',
      now: NOW,
    });
    const signed = await adapter.signPayment(built, [channel, hot], feeSource);
    expect(signed.hash).toBe(built.hash);
    expect(signed.outerHash).toMatch(/^[0-9a-f]{64}$/);
    expect(signed.outerHash).not.toBe(signed.hash);

    const outer = TransactionBuilder.fromXDR(signed.xdr, Networks.TESTNET);
    expect(outer).toBeInstanceOf(FeeBumpTransaction);
    const bump = outer as FeeBumpTransaction;
    expect(bump.feeSource).toBe(feeSource.publicKey);
    expect(Buffer.from(bump.innerTransaction.hash()).toString('hex')).toBe(built.hash);
    expect(bump.signatures).toHaveLength(1);
  });
});

describe('opIndexFromOperationId', () => {
  it('derives the zero-based index from the low 12 bits of the operation id', () => {
    expect(opIndexFromOperationId(String((123456n << 32n) | (1n << 12n) | 1n))).toBe(0);
    expect(opIndexFromOperationId(String((123456n << 32n) | (1n << 12n) | 3n))).toBe(2);
  });
});

describe('loadStellarConfig', () => {
  const ok = {
    STELLAR_NETWORK: 'TESTNET',
    STELLAR_HORIZON_URLS: ' https://a.example , https://b.example ',
    STELLAR_USDC_ISSUER: issuer,
  } as NodeJS.ProcessEnv;

  it('parses a valid environment', () => {
    const c = loadStellarConfig(ok);
    expect(c.horizonUrls).toEqual(['https://a.example', 'https://b.example']);
    expect(c.networkPassphrase).toBe(Networks.TESTNET);
    expect(c.baseFeeStroops).toBe(100);
  });

  it('selects the public passphrase for PUBLIC', () => {
    expect(loadStellarConfig({ ...ok, STELLAR_NETWORK: 'PUBLIC' }).networkPassphrase).toBe(
      Networks.PUBLIC,
    );
  });

  it.each([
    [{ STELLAR_NETWORK: 'MAINNET' }, /STELLAR_NETWORK/],
    [{ STELLAR_HORIZON_URLS: '' }, /STELLAR_HORIZON_URLS/],
    [{ STELLAR_USDC_ISSUER: '' }, /STELLAR_USDC_ISSUER/],
  ])('fails fast on %p', (override, message) => {
    expect(() => loadStellarConfig({ ...ok, ...override } as NodeJS.ProcessEnv)).toThrow(message);
  });
});
