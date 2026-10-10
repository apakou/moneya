/**
 * Amount conversion at the chain boundary (plan §4.2).
 *
 * The ledger and API use 6 decimal places. Stellar USDC has 7. We never accept
 * more than 6 dp from the ledger side, so a conversion can never silently
 * round money.
 */

const LEDGER_RE = /^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$/;
const CHAIN_RE = /^(0|[1-9][0-9]*)(\.[0-9]{1,7})?$/;

export class InvalidAmountError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidAmountError';
  }
}

function assertPositive(value: string, normalised: string): void {
  if (/^0(\.0+)?$/.test(normalised)) {
    throw new InvalidAmountError(`Amount must be greater than zero: ${value}`);
  }
}

function pad(value: string, dp: number): string {
  const [int = '0', frac = ''] = value.split('.');
  return `${int}.${frac.padEnd(dp, '0')}`;
}

/** Ledger (≤ 6 dp) → Stellar (exactly 7 dp). Rejects sub-micro precision and non-positive. */
export function ledgerToChainAmount(amount: string): string {
  if (!LEDGER_RE.test(amount)) {
    throw new InvalidAmountError(`Invalid ledger amount (max 6 decimal places): ${amount}`);
  }
  const out = pad(amount, 7);
  assertPositive(amount, out);
  return out;
}

/** Stellar (≤ 7 dp) → ledger (exactly 6 dp). Throws if the 7th decimal is non-zero. */
export function chainToLedgerAmount(amount: string): string {
  if (!CHAIN_RE.test(amount)) {
    throw new InvalidAmountError(`Invalid chain amount: ${amount}`);
  }
  const padded = pad(amount, 7);
  const [int = '0', frac = ''] = padded.split('.');
  if (frac[6] !== '0') {
    throw new InvalidAmountError(
      `Amount has sub-micro precision and cannot enter the ledger: ${amount}`,
    );
  }
  return `${int}.${frac.slice(0, 6)}`;
}
