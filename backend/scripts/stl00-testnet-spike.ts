/**
 * STL-00 — Stellar TESTNET spike. Throwaway verification of the network half of
 * StellarAdapter (submit, getTx by inner hash, getSequence, streamPayments,
 * fee-bump, channel accounts, tx_bad_seq retry, idempotent resubmit).
 *
 *   pnpm stl00            (needs outbound HTTPS to horizon-testnet.stellar.org
 *                          and friendbot.stellar.org)
 *
 * It issues its OWN test asset "USDC" from a throwaway issuer, so no Circle
 * issuer is needed. Testnet only; refuses to run against anything else.
 */
import {
  Asset,
  Horizon,
  Keypair,
  Networks,
  Operation,
  TransactionBuilder,
} from '@stellar/stellar-sdk';
import { KeypairSigner, StellarAdapter, type InboundPayment } from '@moneya/chain';

const HORIZON =
  process.env.STELLAR_HORIZON_URLS?.split(',')[0]?.trim() ?? 'https://horizon-testnet.stellar.org';
if (!HORIZON.includes('testnet')) throw new Error('STL-00 runs on testnet only');
const server = new Horizon.Server(HORIZON);
const CHANNELS = 10;

const results: { name: string; ok: boolean; note?: string }[] = [];
const check = (name: string, ok: boolean, note?: string) => {
  results.push({ name, ok, note });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${note ? ` — ${note}` : ''}`);
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function fund(pub: string): Promise<void> {
  const res = await fetch(`https://friendbot.stellar.org/?addr=${pub}`);
  if (!res.ok) throw new Error(`friendbot ${res.status}`);
}

async function classic(
  source: Keypair,
  ops: ReturnType<typeof Operation.payment>[],
): Promise<void> {
  const acct = await server.loadAccount(source.publicKey());
  const b = new TransactionBuilder(acct, {
    fee: '100',
    networkPassphrase: Networks.TESTNET,
  }).setTimeout(60);
  ops.forEach((o) => b.addOperation(o));
  const tx = b.build();
  tx.sign(source);
  await server.submitTransaction(tx);
}

async function main(): Promise<void> {
  const issuer = Keypair.random();
  const hot = Keypair.random();
  const deposit = Keypair.random();
  const channels = Array.from({ length: CHANNELS }, () => Keypair.random());

  console.log('funding accounts via friendbot…');
  for (const k of [issuer, hot, deposit, ...channels]) await fund(k.publicKey());

  const usdc = new Asset('USDC', issuer.publicKey());
  for (const k of [hot, deposit]) {
    const acct = await server.loadAccount(k.publicKey());
    const tx = new TransactionBuilder(acct, { fee: '100', networkPassphrase: Networks.TESTNET })
      .addOperation(Operation.changeTrust({ asset: usdc }))
      .setTimeout(60)
      .build();
    tx.sign(k);
    await server.submitTransaction(tx);
  }
  await classic(issuer, [
    Operation.payment({ destination: hot.publicKey(), asset: usdc, amount: '1000' }),
  ]);

  const adapter = new StellarAdapter({
    network: 'TESTNET',
    networkPassphrase: Networks.TESTNET,
    horizonUrls: [HORIZON],
    usdcCode: 'USDC',
    usdcIssuer: issuer.publicKey(),
    baseFeeStroops: 100,
  });
  const hotSigner = new KeypairSigner(hot);
  const sendFrom = async (ch: Keypair, amount: string, memoId: string) => {
    const unsigned = adapter.buildPayment({
      sourceAccount: ch.publicKey(),
      sourceSequence: await adapter.getSequence(ch.publicKey()),
      paymentSource: hot.publicKey(),
      destination: deposit.publicKey(),
      amount,
      memo: { type: 'id', value: memoId },
    });
    return adapter.signPayment(unsigned, [new KeypairSigner(ch), hotSigner], hotSigner);
  };

  // 1. stream before sending
  const seen: InboundPayment[] = [];
  const stop = adapter.streamPayments(
    deposit.publicKey(),
    'now',
    (p) => void seen.push(p),
    (e) => console.error('stream error', e),
  );
  await sleep(2000);

  // 2. single payment: submit, confirm by INNER hash, idempotent resubmit
  const signed = await sendFrom(channels[0]!, '12.345678', '4242');
  const r1 = await adapter.submit(signed.xdr);
  check('submit confirms', r1.status === 'CONFIRMED', JSON.stringify(r1));
  const g = await adapter.getTx(signed.hash);
  check('getTx by inner hash', g.status === 'CONFIRMED' && g.ledgerSequence !== undefined);
  const r2 = await adapter.submit(signed.xdr);
  check('resubmit same XDR is idempotent', r2.status === 'CONFIRMED', JSON.stringify(r2));
  const missing = await adapter.getTx('0'.repeat(64));
  check('getTx unknown hash → NOT_FOUND', missing.status === 'NOT_FOUND');

  // 3. tx_bad_seq: stale sequence fails, fresh one succeeds
  const stale = adapter.buildPayment({
    sourceAccount: channels[0]!.publicKey(),
    sourceSequence: '1',
    paymentSource: hot.publicKey(),
    destination: deposit.publicKey(),
    amount: '1',
  });
  const staleSigned = await adapter.signPayment(
    stale,
    [new KeypairSigner(channels[0]!), hotSigner],
    hotSigner,
  );
  const rBad = await adapter.submit(staleSigned.xdr);
  check('stale sequence → FAILED (tx_bad_seq)', rBad.status === 'FAILED', rBad.errorCode);
  const retry = await sendFrom(channels[0]!, '1', '4243');
  check(
    'retry with fresh sequence succeeds',
    (await adapter.submit(retry.xdr)).status === 'CONFIRMED',
  );

  // 4. parallel via channel accounts
  const par = await Promise.all(
    channels.map(async (ch, i) =>
      adapter.submit((await sendFrom(ch, '0.5', String(5000 + i))).xdr),
    ),
  );
  check(
    `${CHANNELS} concurrent payments via channel accounts`,
    par.every((r) => r.status === 'CONFIRMED'),
    par.map((r) => r.errorCode ?? 'ok').join(','),
  );

  // 5. stream saw them all, with dedupe keys
  await sleep(5000);
  stop();
  const keys = new Set(seen.map((p) => `${p.txHash}:${p.opIndex}`));
  check(
    'stream delivered every payment exactly once per (tx_hash, op_index)',
    keys.size === seen.length && seen.length >= CHANNELS + 2,
    `${seen.length} events`,
  );
  check(
    'stream carries asset, memo and 7dp amount',
    seen.some((p) => p.assetCode === 'USDC' && p.memo === '4242' && p.amount === '12.3456780'),
  );

  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
