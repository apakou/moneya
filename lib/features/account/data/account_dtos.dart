import '../../home/domain/transaction.dart';
import '../../ramp/domain/ramp_mapping.dart';

/// A balance in one currency (`GET /v1/wallet`). Amounts stay decimal strings
/// end to end; [availableNum] is only for guards such as "enough to withdraw".
class WalletBalance {
  const WalletBalance({
    required this.currency,
    required this.balance,
    required this.availableBalance,
    required this.equivalentBalance,
    required this.provisioned,
  });

  /// Wire currency (`GHS`, not the app's `GHC`).
  final String currency;
  final String balance;
  final String availableBalance;

  /// Everything the user holds, in any currency, expressed in [currency] at the
  /// current rates (rounded down). Display only: just [balance] / [availableBalance]
  /// can be spent in [currency].
  final String equivalentBalance;
  final bool provisioned;

  /// True when [equivalentBalance] includes money held in other currencies.
  bool get isConverted =>
      num.tryParse(equivalentBalance) != num.tryParse(balance);

  num get availableNum => num.tryParse(availableBalance) ?? 0;

  factory WalletBalance.fromJson(Map<String, Object?> j) => WalletBalance(
    currency: j['currency'] as String,
    balance: j['balance'] as String,
    availableBalance: (j['available_balance'] ?? j['balance']) as String,
    equivalentBalance: (j['equivalent_balance'] ?? j['balance']) as String,
    provisioned: j['provisioned'] as bool? ?? false,
  );
}

/// One page of `GET /v1/transactions`.
class TransactionPage {
  const TransactionPage({required this.items, required this.nextCursor});

  final List<Transaction> items;
  final String? nextCursor;

  factory TransactionPage.fromJson(Map<String, Object?> j) => TransactionPage(
    items: [
      for (final raw in (j['items'] as List<Object?>))
        transactionFromJson((raw! as Map).cast<String, Object?>()),
    ],
    nextCursor: j['next_cursor'] as String?,
  );
}

/// `Transaction` for one API row. A top-up credits the balance (`received`);
/// a cash-out debits it (`sent`).
Transaction transactionFromJson(Map<String, Object?> j) {
  final kind = j['kind'] as String;
  final phone = j['counterparty_phone'] as String;
  final name = j['counterparty_name'] as String?;
  final id = j['id'] as String;
  return Transaction(
    id: id.substring(0, 8).toUpperCase(),
    kind: kind == 'TOP_UP' ? TxnKind.received : TxnKind.sent,
    when: DateTime.parse(j['created_at'] as String).toLocal(),
    amount: j['amount'] as String,
    currencyCode: RampMapping.displayCurrency(j['currency'] as String),
    fee: j['fee'] as String,
    status: switch (j['status'] as String) {
      'COMPLETED' => TxnStatus.success,
      'FAILED' => TxnStatus.failed,
      _ => TxnStatus.pending,
    },
    counterparty: (name != null && name.isNotEmpty) ? name : phone,
    counterpartyPhone: phone,
    paymentMethod: _methodLabel(j['payment_method'] as String),
  );
}

String _methodLabel(String method) => switch (method) {
  'WAVE' => 'Mobile Money • Wave',
  'MTN_MOMO' => 'Mobile Money • MTN MoMo',
  'ORANGE_MONEY' => 'Mobile Money • Orange Money',
  'MOOV_MONEY' => 'Mobile Money • Moov Money',
  'AIRTEL_MONEY' => 'Mobile Money • Airtel Money',
  'MPESA' => 'Mobile Money • M-Pesa',
  'BANK_TRANSFER' => 'Bank Transfer',
  _ => method,
};
