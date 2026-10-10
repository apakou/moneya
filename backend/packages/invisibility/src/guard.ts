/**
 * Stablecoin-invisibility guard (plan §1.1, ticket INV-03).
 *
 * MoneyA users must never learn that stablecoins or a blockchain are used. This
 * module scans any JSON-like value (keys AND string values) for chain-revealing
 * vocabulary and identifiers. It is used by e2e tests, and by a response
 * interceptor outside production.
 */

export interface Leak {
  /** JSON path, e.g. `$.items[0].fee`. */
  path: string;
  kind: 'term' | 'identifier' | 'key';
  match: string;
}

export interface LeakOptions {
  /** Exact JSON paths that are allowed to match (reviewed exceptions). */
  allowPaths?: readonly string[];
}

export const FORBIDDEN_TERM =
  /\b(usdc|usd\s*coin|stablecoins?|solana|stellar|xlm|lumens?|blockchain|crypto(?:currency)?|on-?chain|wallets?|gas\s+fees?)\b/i;

/** Stellar public key (G…), muxed address (M…), 64-hex transaction hash. */
const IDENTIFIERS: ReadonlyArray<readonly [string, RegExp]> = [
  ['stellar-address', /\bG[A-Z2-7]{55}\b/],
  ['stellar-muxed-address', /\bM[A-Z2-7]{68}\b/],
  ['tx-hash', /\b[0-9a-fA-F]{64}\b/],
];

export const FORBIDDEN_KEY =
  /(usdc|stablecoin|solana|stellar|xlm|blockchain|crypto|chain|tx_?hash|signature|address)/i;

export function findLeaks(value: unknown, options: LeakOptions = {}): Leak[] {
  const allow = new Set(options.allowPaths ?? []);
  const leaks: Leak[] = [];

  const visit = (node: unknown, path: string): void => {
    if (allow.has(path)) return;
    if (typeof node === 'string') {
      const term = FORBIDDEN_TERM.exec(node);
      if (term) leaks.push({ path, kind: 'term', match: term[0] });
      for (const [, re] of IDENTIFIERS) {
        const id = re.exec(node);
        if (id) leaks.push({ path, kind: 'identifier', match: id[0] });
      }
      return;
    }
    if (Array.isArray(node)) {
      node.forEach((item, i) => visit(item, `${path}[${i}]`));
      return;
    }
    if (node !== null && typeof node === 'object') {
      for (const [key, child] of Object.entries(node as Record<string, unknown>)) {
        const childPath = `${path}.${key}`;
        if (!allow.has(childPath) && FORBIDDEN_KEY.test(key)) {
          leaks.push({ path: childPath, kind: 'key', match: key });
        }
        visit(child, childPath);
      }
    }
  };

  visit(value, '$');
  return leaks;
}

export class StablecoinLeakError extends Error {
  constructor(public readonly leaks: readonly Leak[]) {
    super(
      `Response leaks chain/stablecoin details: ${leaks
        .map((l) => `${l.kind}:${l.match}@${l.path}`)
        .join(', ')}`,
    );
    this.name = 'StablecoinLeakError';
  }
}

export function assertNoLeaks(value: unknown, options?: LeakOptions): void {
  const leaks = findLeaks(value, options);
  if (leaks.length > 0) throw new StablecoinLeakError(leaks);
}
