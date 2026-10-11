import {
  journalIdFor,
  uuidv5,
  NS_LEDGER,
  toMicro,
  fromMicro,
  validateJournal,
  templates,
  JournalInvalidError,
} from '../src';

const U1 = '11111111-1111-4111-8111-111111111111';
const U2 = '22222222-2222-4222-8222-222222222222';
const T = '33333333-3333-4333-8333-333333333333';

describe('money', () => {
  it('round-trips exact decimals without floating point', () => {
    expect(fromMicro(toMicro('0.1') + toMicro('0.2'))).toBe('0.3');
    expect(fromMicro(toMicro('1234567.123456'))).toBe('1234567.123456');
    expect(fromMicro(toMicro('-5'))).toBe('-5');
  });
  it('rejects > 6 decimals, junk and numbers', () => {
    expect(() => toMicro('0.1234567')).toThrow();
    expect(() => toMicro('1e3')).toThrow();
    expect(() => toMicro('')).toThrow();
    expect(() => toMicro(5 as unknown as string)).toThrow();
  });
});

describe('ids', () => {
  it('uuidv5 matches the RFC 4122 reference vector', () => {
    expect(uuidv5('www.example.com', '6ba7b810-9dad-11d1-80b4-00c04fd430c8')).toBe(
      '2ed6657d-e927-568b-95e1-2665a8aea6a2',
    );
  });
  it('journal ids are deterministic and event-specific', () => {
    expect(journalIdFor('TRANSFER:a:SETTLE')).toBe(journalIdFor('TRANSFER:a:SETTLE'));
    expect(journalIdFor('TRANSFER:a:SETTLE')).not.toBe(journalIdFor('TRANSFER:a:REFUND'));
    expect(NS_LEDGER).toMatch(/^[0-9a-f-]{36}$/);
  });
});

describe('templates (single currency, per-currency balanced)', () => {
  const sum = (j: { entries: { amount: string }[] }) =>
    fromMicro(j.entries.reduce((s, e) => s + toMicro(e.amount), 0n));

  it('p2p: sender -(amount+fee), recipient +amount, fee revenue +fee', () => {
    const j = templates.p2pTransfer({
      transferId: T,
      senderId: U1,
      recipientId: U2,
      currency: 'GHS',
      amount: '100',
      fee: '0.5',
    });
    expect(j.entries.map((e) => e.amount)).toEqual(['-100.5', '100', '0.5']);
    expect(sum(j)).toBe('0');
    validateJournal(j);
  });
  it('p2p with zero fee omits the fee leg', () => {
    const j = templates.p2pTransfer({
      transferId: T,
      senderId: U1,
      recipientId: U2,
      currency: 'GHS',
      amount: '10',
      fee: '0',
    });
    expect(j.entries).toHaveLength(2);
  });
  it('escrow hold / release / refund balance and use distinct ids', () => {
    const base = { transferId: T, currency: 'GHS', amount: '50', fee: '1' };
    const hold = templates.escrowHold({ ...base, senderId: U1 });
    const rel = templates.escrowRelease({ ...base, recipientId: U2 });
    const ref = templates.escrowRefund({ ...base, senderId: U1, reason: 'EXPIRED' });
    for (const j of [hold, rel, ref]) {
      expect(sum(j)).toBe('0');
      validateJournal(j);
    }
    expect(new Set([hold.journalId, rel.journalId, ref.journalId]).size).toBe(3);
    expect(ref.entries[1]!.amount).toBe('51'); // fee returned too
    expect(ref.ref.refType).toBe('CLAIM_REFUND');
  });
  it('rejects self-sends, non-positive amounts and blank recon memos', () => {
    expect(() =>
      templates.p2pTransfer({
        transferId: T,
        senderId: U1,
        recipientId: U1,
        currency: 'GHS',
        amount: '1',
        fee: '0',
      }),
    ).toThrow(JournalInvalidError);
    expect(() =>
      templates.escrowHold({ transferId: T, senderId: U1, currency: 'GHS', amount: '0', fee: '0' }),
    ).toThrow(JournalInvalidError);
    expect(() =>
      templates.reconciliationAdjustment({
        incidentId: T,
        userId: U1,
        currency: 'GHS',
        delta: '5',
        memo: ' ',
      }),
    ).toThrow(JournalInvalidError);
  });
});

describe('validateJournal', () => {
  const ok = templates.p2pTransfer({
    transferId: T,
    senderId: U1,
    recipientId: U2,
    currency: 'GHS',
    amount: '10',
    fee: '0',
  });
  it('rejects unbalanced, single-entry, zero and mixed-currency-unbalanced journals', () => {
    expect(() => validateJournal({ ...ok, entries: [ok.entries[0]!] })).toThrow(/at least 2/);
    expect(() =>
      validateJournal({ ...ok, entries: [ok.entries[0]!, { ...ok.entries[1]!, amount: '9' }] }),
    ).toThrow(/balance/);
    expect(() =>
      validateJournal({ ...ok, entries: [ok.entries[0]!, { ...ok.entries[1]!, amount: '0' }] }),
    ).toThrow(/Zero/);
    // zero overall but not per currency
    expect(() =>
      validateJournal({
        ...ok,
        entries: [
          ok.entries[0]!,
          { ...ok.entries[1]!, account: { ...ok.entries[1]!.account, currency: 'XOF' } },
        ],
      }),
    ).toThrow(/balance in/);
  });
});
