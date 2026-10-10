import { Keypair } from '@stellar/stellar-sdk';
import { assertNoLeaks, findLeaks, StablecoinLeakError } from '@moneya/invisibility';

describe('invisibility guard', () => {
  it('accepts a clean fiat-only response', () => {
    const body = {
      id: '0b9e8f0e-1c4e-4a58-9a6b-1f0c5d8f2a11',
      status: 'COMPLETED',
      amount: '5000',
      fee: '50',
      currency: 'XOF',
      note: 'Rent for October',
    };
    expect(findLeaks(body)).toEqual([]);
    expect(() => assertNoLeaks(body)).not.toThrow();
  });

  it.each([
    ['USDC', 'You received 8 USDC'],
    ['USD Coin', 'USD Coin balance'],
    ['stablecoin', 'Powered by stablecoins'],
    ['Stellar', 'Settled on Stellar'],
    ['blockchain', 'on the blockchain'],
    ['wallet', 'Your wallet was not debited'],
    ['crypto', 'crypto transfer'],
  ])('flags the term %s in string values', (_name, text) => {
    expect(findLeaks({ message: text }).map((l) => l.kind)).toContain('term');
  });

  it('flags chain-revealing keys', () => {
    const kinds = findLeaks({ solana_signature: 'x', amount_usdc: '1', chain: 'STELLAR' });
    expect(
      kinds
        .filter((l) => l.kind === 'key')
        .map((l) => l.match)
        .sort(),
    ).toEqual(['amount_usdc', 'chain', 'solana_signature']);
  });

  it('flags Stellar addresses and 64-hex transaction hashes by shape', () => {
    const address = Keypair.random().publicKey();
    const hash = 'a'.repeat(64);
    const leaks = findLeaks({ ref: address, other: [hash] });
    expect(leaks.map((l) => l.match).sort()).toEqual([address, hash].sort());
    expect(leaks.every((l) => l.kind === 'identifier')).toBe(true);
  });

  it('reports precise JSON paths for nested values', () => {
    const [leak] = findLeaks({ items: [{ ok: 1 }, { detail: 'paid in USDC' }] });
    expect(leak?.path).toBe('$.items[1].detail');
  });

  it('honours reviewed exceptions by exact path', () => {
    const body = { legal: { note: 'See the Stellar terms' } };
    expect(findLeaks(body)).not.toEqual([]);
    expect(findLeaks(body, { allowPaths: ['$.legal.note'] })).toEqual([]);
  });

  it('does not false-positive on words that merely contain a term', () => {
    expect(findLeaks({ m: 'stellarated cryptic gasoline' })).toEqual([]);
  });

  it('assertNoLeaks throws a descriptive error', () => {
    expect(() => assertNoLeaks({ x: 'USDC' })).toThrow(StablecoinLeakError);
  });
});
