/** Home currency by ISO country (launch + planned corridors). `null` = not served yet. */
const BY_COUNTRY: Record<string, string> = {
  GH: 'GHS',
  NG: 'NGN',
  KE: 'KES',
  // UEMOA (XOF)
  SN: 'XOF',
  CI: 'XOF',
  ML: 'XOF',
  BF: 'XOF',
  BJ: 'XOF',
  TG: 'XOF',
  NE: 'XOF',
  GW: 'XOF',
  // CEMAC (XAF)
  CM: 'XAF',
  GA: 'XAF',
  CG: 'XAF',
  TD: 'XAF',
  CF: 'XAF',
  GQ: 'XAF',
};

export const homeCurrency = (country: string): string | null => BY_COUNTRY[country] ?? null;
