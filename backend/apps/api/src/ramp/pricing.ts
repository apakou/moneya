import { FIAT_DECIMALS, type RampCurrency } from '@moneya/ramp';
import { toMicro, fromMicro } from '@moneya/ledger';

/**
 * Quote math. All amounts are BigInt micro-units (6 dp); rates are scaled by 1e8.
 * `rates[C]` = units of C per 1 settlement unit. Settlement amounts are rounded
 * DOWN (we never promise the treasury more than it receives); fees round UP to the
 * currency's fiat precision (the user never pays a fractional minor unit).
 */
const RATE_SCALE = 100_000_000n;

export interface PricingConfig {
  rates: Partial<Record<RampCurrency, string>>;
  feeBps: number;
}

/** Sample rates for dev/test only (clearly not market data). Production must set RAMP_RATES. */
export const SIMULATED_RATES: Record<RampCurrency, string> = {
  GHS: '15.5',
  XOF: '600',
  XAF: '600',
  NGN: '1500',
  KES: '129',
};

export function loadPricing(env: NodeJS.ProcessEnv = process.env): PricingConfig {
  let rates: PricingConfig['rates'];
  if (env.RAMP_RATES) {
    rates = JSON.parse(env.RAMP_RATES) as PricingConfig['rates'];
  } else if (env.NODE_ENV === 'production') {
    throw new Error('RAMP_RATES is required in production (no market-data source is wired yet)');
  } else {
    rates = SIMULATED_RATES;
  }
  return { rates, feeBps: Number(env.RAMP_FEE_BPS ?? 150) };
}

export class UnsupportedCurrencyError extends Error {}

const rateScaled = (cfg: PricingConfig, c: RampCurrency): bigint => {
  const r = cfg.rates[c];
  if (!r || !/^[0-9]+(\.[0-9]{1,8})?$/.test(r))
    throw new UnsupportedCurrencyError(`No rate for ${c}`);
  const [i, f = ''] = r.split('.');
  const v = BigInt(i!) * RATE_SCALE + BigInt(f.padEnd(8, '0'));
  if (v === 0n) throw new UnsupportedCurrencyError(`No rate for ${c}`);
  return v;
};

const unit = (c: RampCurrency): bigint => 10n ** BigInt(6 - FIAT_DECIMALS[c]); // micro per minor unit
const floorTo = (v: bigint, u: bigint): bigint => (v / u) * u;
const ceilTo = (v: bigint, u: bigint): bigint => ((v + u - 1n) / u) * u;

function fee(cfg: PricingConfig, c: RampCurrency, amount: bigint): bigint {
  return ceilTo((amount * BigInt(cfg.feeBps) + 9_999n) / 10_000n, unit(c));
}

/** settlement micro = amount / rate */
const toSettlement = (cfg: PricingConfig, c: RampCurrency, amount: bigint): bigint =>
  (amount * RATE_SCALE) / rateScaled(cfg, c);

export interface PricedQuote {
  fromCurrency: RampCurrency;
  fromAmount: string;
  toCurrency: RampCurrency;
  toAmount: string;
  /** Effective rate to/from, 8 dp (always "1" for a top-up). */
  rate: string;
  fee: string;
  /** INTERNAL: settlement-unit amount. */
  settlementAmount: string;
}

export function priceOnramp(
  cfg: PricingConfig,
  currency: RampCurrency,
  fiatAmount: string,
): PricedQuote {
  const x = toMicro(fiatAmount);
  const f = fee(cfg, currency, x);
  if (x <= f) throw new RangeError('Amount too small to cover the fee');
  const s = toSettlement(cfg, currency, x);
  if (s <= 0n) throw new RangeError('Amount too small');
  return {
    fromCurrency: currency,
    fromAmount: fromMicro(x),
    toCurrency: currency,
    toAmount: fromMicro(x - f),
    rate: '1',
    fee: fromMicro(f),
    settlementAmount: fromMicro(s),
  };
}

export function priceOfframp(
  cfg: PricingConfig,
  currency: RampCurrency,
  payoutCurrency: RampCurrency,
  amount: string,
): PricedQuote {
  const y = toMicro(amount);
  const f = fee(cfg, currency, y);
  if (y <= f) throw new RangeError('Amount too small to cover the fee');
  const s = toSettlement(cfg, currency, y - f);
  // Same currency: no conversion, the payee gets exactly the net. Otherwise convert via the settlement unit.
  const payout =
    currency === payoutCurrency
      ? y - f
      : floorTo((s * rateScaled(cfg, payoutCurrency)) / RATE_SCALE, unit(payoutCurrency));
  if (s <= 0n || payout <= 0n) throw new RangeError('Amount too small');
  const eff = currency === payoutCurrency ? RATE_SCALE : (payout * RATE_SCALE) / y;
  return {
    fromCurrency: currency,
    fromAmount: fromMicro(y),
    toCurrency: payoutCurrency,
    toAmount: fromMicro(payout),
    rate: trimRate(eff),
    fee: fromMicro(f),
    settlementAmount: fromMicro(s),
  };
}

const trimRate = (eff: bigint): string => {
  const i = eff / RATE_SCALE;
  const f = String(eff % RATE_SCALE)
    .padStart(8, '0')
    .replace(/0+$/, '');
  return f ? `${i}.${f}` : `${i}`;
};
