import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/features/account/data/account_dtos.dart';
import 'package:moneya/features/home/domain/transaction.dart';

Map<String, Object?> _row({
  String kind = 'TOP_UP',
  String status = 'COMPLETED',
  String amount = '197',
  String fee = '3',
  String currency = 'GHS',
  String method = 'MTN_MOMO',
  String? name,
}) => {
  'id': 'abcdef12-0000-4000-8000-000000000000',
  'kind': kind,
  'status': status,
  'amount': amount,
  'currency': currency,
  'fee': fee,
  'payment_method': method,
  'counterparty_phone': '+233201234567',
  'counterparty_name': name,
  'created_at': '2026-10-11T21:00:00.000Z',
  'completed_at': null,
};

void main() {
  group('transactionFromJson', () {
    test('a completed top-up is a successful credit', () {
      final t = transactionFromJson(_row());
      expect(t.kind, TxnKind.received);
      expect(t.status, TxnStatus.success);
      expect(t.id, 'ABCDEF12');
      expect((t.amount, t.fee), ('197', '3'));
      expect(t.paymentMethod, 'Mobile Money • MTN MoMo');
      expect(t.counterparty, '+233201234567'); // no name → the number
    });

    test('a cash-out is a debit and shows the payee name', () {
      final t = transactionFromJson(
        _row(kind: 'CASH_OUT', name: 'Ama Mensah', method: 'BANK_TRANSFER'),
      );
      expect(t.kind, TxnKind.sent);
      expect(t.counterparty, 'Ama Mensah');
      expect(t.paymentMethod, 'Bank Transfer');
    });

    test('statuses map to the three UI states', () {
      expect(
        transactionFromJson(_row(status: 'PENDING')).status,
        TxnStatus.pending,
      );
      expect(
        transactionFromJson(_row(status: 'FAILED')).status,
        TxnStatus.failed,
      );
      expect(
        transactionFromJson(_row(status: 'COMPLETED')).status,
        TxnStatus.success,
      );
    });

    test("Ghana's ISO GHS is shown as the app's legacy GHC", () {
      expect(transactionFromJson(_row()).currencyCode, 'GHC');
      expect(transactionFromJson(_row(currency: 'XOF')).currencyCode, 'XOF');
    });

    test('total adds fractional amounts correctly', () {
      expect(
        transactionFromJson(_row(amount: '98.5', fee: '1.5')).total,
        '100',
      );
      expect(
        transactionFromJson(_row(amount: '10.25', fee: '0.5')).total,
        '10.75',
      );
      expect(transactionFromJson(_row(amount: '197', fee: '3')).total, '200');
    });
  });

  group('page + wallet', () {
    test('TransactionPage keeps the cursor', () {
      final p = TransactionPage.fromJson({
        'items': [_row()],
        'next_cursor': '2026-10-11 21:00:00+00|abc',
      });
      expect(p.items, hasLength(1));
      expect(p.nextCursor, '2026-10-11 21:00:00+00|abc');
    });

    test('WalletBalance exposes the spendable amount as a number', () {
      final w = WalletBalance.fromJson({
        'currency': 'GHS',
        'balance': '197',
        'available_balance': '150.5',
        'provisioned': false,
      });
      expect(w.balance, '197');
      expect(w.availableNum, 150.5);
    });

    test('equivalent balance: flagged as converted only when it differs from what is held', () {
      WalletBalance w(String held, String? equivalent) =>
          WalletBalance.fromJson({
            'currency': 'XOF',
            'balance': held,
            'available_balance': held,
            'equivalent_balance': ?equivalent,
            'provisioned': false,
          });
      expect(w('0', '7625').equivalentBalance, '7625');
      expect(w('0', '7625').isConverted, isTrue);
      expect(w('197', '197').isConverted, isFalse);
      expect(w('197', '197.0').isConverted, isFalse); // numeric compare, not string
      expect(w('197', null).equivalentBalance, '197'); // older server: no conversion
    });
  });
}
