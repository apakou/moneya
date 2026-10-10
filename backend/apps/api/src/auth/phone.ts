import { parsePhoneNumberFromString } from 'libphonenumber-js';

export interface ParsedPhone {
  e164: string;
  country: string;
  masked: string;
}

/** Returns null unless `raw` is a valid E.164 number with a known country. */
export function parsePhone(raw: unknown): ParsedPhone | null {
  if (typeof raw !== 'string' || !/^\+[1-9][0-9]{6,14}$/.test(raw)) return null;
  const p = parsePhoneNumberFromString(raw);
  if (!p || !p.isValid() || !p.country) return null;
  const national = p.nationalNumber;
  const maskedNational =
    national.slice(0, 2) +
    ' ' +
    '** '.repeat(Math.max(0, Math.ceil((national.length - 4) / 2))) +
    national.slice(-2);
  return {
    e164: p.number,
    country: p.country,
    masked: `+${p.countryCallingCode} ${maskedNational}`.trim(),
  };
}
