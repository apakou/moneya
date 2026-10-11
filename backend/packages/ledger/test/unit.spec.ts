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

describe('ramp templates (D7: each currency balances on its own)', () => {
  const perCurrency = (j: { entries: { account: { currency: string }; amount: string }[] }) => {
    const m = new Map<string, bigint>();
    for (const e of j.entries)
      m.set(e.account.currency, (m.get(e.account.currency) ?? 0n) + toMicro(e.amount));
    return m;
  };
  const OID = '44444444-4444-4444-8444-444444444444';

  it('onrampSettle: user credited net of fee; GHS and settlement legs each balance', () => {
    const j = templates.onrampSettle({
      orderId: OID,
      userId: U1,
      currency: 'GHS',
      fiatAmount: '100',
      fee: '2',
      settlementAmount: '6.451613',
    });
    expect([...perCurrency(j).values()].every((v) => v === 0n)).toBe(true);
    expect(perCurrency(j).size).toBe(2);
    expect(j.entries.find((e) => e.account.kind === 'USER_WALLET')!.amount).toBe('98');
    validateJournal(j);
  });
  it('offramp hold → settle and hold → refund net to the right places', () => {
    const hold = templates.offrampHold({
      orderId: OID,
      userId: U1,
      currency: 'GHS',
      amount: '100',
    });
    const settle = templates.offrampSettle({
      orderId: OID,
      currency: 'GHS',
      amount: '100',
      fee: '2',
      settlementAmount: '6.322581',
    });
    const refund = templates.offrampRefund({
      orderId: OID,
      userId: U1,
      currency: 'GHS',
      amount: '100',
    });
    for (const j of [hold, settle, refund]) {
      expect([...perCurrency(j).values()].every((v) => v === 0n)).toBe(true);
      validateJournal(j);
    }
    expect(new Set([hold.journalId, settle.journalId, refund.journalId]).size).toBe(3);
    // SUSPENSE returns to zero on either exit path
    const susp = (j: typeof hold) =>
      j.entries
        .filter((e) => e.account.kind === 'SUSPENSE')
        .reduce((s, e) => s + toMicro(e.amount), 0n);
    expect(susp(hold) + susp(settle)).toBe(0n);
    expect(susp(hold) + susp(refund)).toBe(0n);
  });
  it('rejects a fee that eats the whole amount and a missing settlement amount', () => {
    expect(() =>
      templates.onrampSettle({
        orderId: OID,
        userId: U1,
        currency: 'GHS',
        fiatAmount: '10',
        fee: '10',
        settlementAmount: '1',
      }),
    ).toThrow(JournalInvalidError);
    expect(() =>
      templates.offrampSettle({
        orderId: OID,
        currency: 'GHS',
        amount: '10',
        fee: '1',
        settlementAmount: '0',
      }),
    ).toThrow(JournalInvalidError);
  });
});
