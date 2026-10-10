import { chainToLedgerAmount, InvalidAmountError, ledgerToChainAmount } from '@moneya/chain';

describe('ledgerToChainAmount (6 dp → 7 dp)', () => {
  it.each([
    ['1', '1.0000000'],
    ['0.000001', '0.0000010'],
    ['12345.67', '12345.6700000'],
    ['5000', '5000.0000000'],
    ['0.5', '0.5000000'],
  ])('%s → %s', (input, expected) => {
    expect(ledgerToChainAmount(input)).toBe(expected);
  });

  it.each(['0', '0.0', '0.000000', '-1', '1.0000001', '1e3', '', ' 1', '01', '1.', '.5', 'abc'])(
    'rejects %p',
    (input) => {
      expect(() => ledgerToChainAmount(input)).toThrow(InvalidAmountError);
    },
  );
});

describe('chainToLedgerAmount (7 dp → 6 dp)', () => {
  it.each([
    ['1.0000000', '1.000000'],
    ['0.0000010', '0.000001'],
    ['12.5', '12.500000'],
    ['7', '7.000000'],
  ])('%s → %s', (input, expected) => {
    expect(chainToLedgerAmount(input)).toBe(expected);
  });

  it('rejects sub-micro precision instead of rounding money', () => {
    expect(() => chainToLedgerAmount('0.0000001')).toThrow(InvalidAmountError);
    expect(() => chainToLedgerAmount('1.0000009')).toThrow(InvalidAmountError);
  });

  it('rejects malformed input', () => {
    expect(() => chainToLedgerAmount('1.00000001')).toThrow(InvalidAmountError);
    expect(() => chainToLedgerAmount('-1')).toThrow(InvalidAmountError);
  });

  it('round-trips every 6 dp value', () => {
    for (const v of ['0.000001', '1.234567', '999999.999999']) {
      expect(chainToLedgerAmount(ledgerToChainAmount(v))).toBe(v.padEnd(v.indexOf('.') + 7, '0'));
    }
  });
});
