import { toMicro, InvalidMoneyError } from './money';
import { JournalInvalidError, type Journal } from './types';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Application-side checks mirroring the DB invariants (L1, L6, D7) so a bad
 * journal fails fast with a clear message instead of a constraint error at COMMIT.
 */
export function validateJournal(j: Journal): void {
  if (!UUID_RE.test(j.journalId)) throw new JournalInvalidError('journalId must be a UUID');
  if (!UUID_RE.test(j.ref.refId)) throw new JournalInvalidError('refId must be a UUID');
  if (j.entries.length < 2) throw new JournalInvalidError('A journal needs at least 2 entries');

  const perCurrency = new Map<string, bigint>();
  for (const e of j.entries) {
    let micro: bigint;
    try {
      micro = toMicro(e.amount);
    } catch (err) {
      throw new JournalInvalidError(
        err instanceof InvalidMoneyError ? err.message : 'Invalid amount',
      );
    }
    if (micro === 0n) throw new JournalInvalidError('Zero-amount entries are not allowed');
    if (e.account.kind === 'USER_WALLET' && !e.account.userId) {
      throw new JournalInvalidError('USER_WALLET needs a userId');
    }
    if (e.account.kind !== 'USER_WALLET' && e.account.userId) {
      throw new JournalInvalidError(`${e.account.kind} is a global account`);
    }
    perCurrency.set(e.account.currency, (perCurrency.get(e.account.currency) ?? 0n) + micro);
  }
  for (const [currency, sum] of perCurrency) {
    if (sum !== 0n) throw new JournalInvalidError(`Journal does not balance in ${currency}`);
  }
}
