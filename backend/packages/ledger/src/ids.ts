import { createHash } from 'node:crypto';

/** Fixed namespace for deterministic journal ids (never change it). */
export const NS_LEDGER = '6f1d4a8e-3c52-5b97-9d0a-2e7c41b8f5a3';

/** RFC 4122 UUIDv5 (SHA-1). */
export function uuidv5(name: string, namespace: string): string {
  const ns = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const h = createHash('sha1').update(ns).update(name, 'utf8').digest();
  h[6] = (h[6]! & 0x0f) | 0x50;
  h[8] = (h[8]! & 0x3f) | 0x80;
  const x = h.subarray(0, 16).toString('hex');
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20)}`;
}

/**
 * Journal id derived from the business event, e.g. `TRANSFER:<id>:SETTLE`.
 * A worker replaying the same step produces the same id, so the dedupe table
 * rejects the second post instead of double-spending.
 */
export const journalIdFor = (key: string): string => uuidv5(key, NS_LEDGER);
