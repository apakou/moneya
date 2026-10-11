/**
 * Money is never a JS number. Amounts are decimal strings with at most 6
 * decimals (ledger precision, NUMERIC(20,6)) and are handled as BigInt
 * micro-units internally.
 */
const SCALE = 6;
const RE = /^-?(0|[1-9][0-9]*)(\.[0-9]{1,6})?$/;

export class InvalidMoneyError extends Error {}

export function toMicro(amount: string): bigint {
  if (typeof amount !== 'string' || !RE.test(amount)) {
    throw new InvalidMoneyError(`Invalid amount "${String(amount)}" (max ${SCALE} decimals)`);
  }
  const neg = amount.startsWith('-');
  const [int, frac = ''] = amount.replace('-', '').split('.');
  const micro = BigInt(int ?? '0') * 10n ** BigInt(SCALE) + BigInt(frac.padEnd(SCALE, '0'));
  return neg ? -micro : micro;
}

export function fromMicro(micro: bigint): string {
  const neg = micro < 0n;
  const abs = neg ? -micro : micro;
  const int = abs / 10n ** BigInt(SCALE);
  const frac = String(abs % 10n ** BigInt(SCALE))
    .padStart(SCALE, '0')
    .replace(/0+$/, '');
  return `${neg ? '-' : ''}${int}${frac ? `.${frac}` : ''}`;
}

export const add = (a: string, b: string): string => fromMicro(toMicro(a) + toMicro(b));
export const negate = (a: string): string => fromMicro(-toMicro(a));
export const isPositive = (a: string): boolean => toMicro(a) > 0n;
