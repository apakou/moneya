import '../../home/domain/transaction.dart';

/// `Wallet` (openapi.yaml): the spendable balance in the user's home currency. Fiat only.
class WalletInfo {
  const WalletInfo({required this.provisioned, required this.balance, required this.currency});

  final bool provisioned;

  /// Decimal string, never a double.
  final String balance;

  /// ISO code on the wire (`GHS`); the app displays the cedi as `GHC`.
  final String currency;

  factory WalletInfo.fromJson(Map<String, Object?> j) {
    final p = j['provisioned'];
    final b = j['balance'];
    final c = j['currency'];
    if (p is! bool || b is! String || c is! String) {
      throw const FormatException('balance response is malformed');
    }
    return WalletInfo(provisioned: p, balance: b, currency: c);
  }
}

/// One entry of `GET /v1/transfers` (`Transfer`): a top-up, a cash-out, and later peer-to-peer sends.
class TransferItem {
  const TransferItem({
    required this.id,
    required this.kind,
    required this.status,
    required this.amount,
    required this.fee,
    required this.currency,
    required this.counterpartyPhone,
    required this.createdAt,
    this.counterpartyName,
    this.failureReason,
  });

  final String id;

  /// SENT | RECEIVED | ONRAMP | OFFRAMP
  final String kind;

  /// PROCESSING | COMPLETED | FAILED | AWAITING_CLAIM | EXPIRED_REFUNDED | CANCELLED
  final String status;
  final String amount;
  final String fee;
  final String currency;
  final String counterpartyPhone;
  final String? counterpartyName;
  final String? failureReason;
  final DateTime createdAt;

  /// Money coming IN to the balance (a top-up or a received transfer).
  bool get isIncoming => kind == 'ONRAMP' || kind == 'RECEIVED';

  factory TransferItem.fromJson(Map<String, Object?> j) {
    String s(String k) {
      final v = j[k];
      if (v is! String) throw FormatException('transfer.$k missing');
      return v;
    }

    final kind = s('kind');
    final incoming = kind == 'ONRAMP' || kind == 'RECEIVED';
    // For an incoming item the other party is the sender; for an outgoing one, the recipient.
    final other = (incoming ? j['sender'] : j['recipient']);
    final party = other is Map ? other.cast<String, Object?>() : const <String, Object?>{};
    return TransferItem(
      id: s('id'),
      kind: kind,
      status: s('status'),
      amount: s('amount'),
      fee: s('fee'),
      currency: s('currency'),
      counterpartyPhone: (party['phone'] as String?) ?? '',
      counterpartyName: party['display_name'] as String?,
      failureReason: j['failure_reason'] as String?,
      createdAt: DateTime.parse(s('created_at')),
    );
  }

  /// Adapts to the existing list/detail UI model.
  Transaction toTransaction() {
    return Transaction(
      id: id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase(),
      kind: isIncoming ? TxnKind.received : TxnKind.sent,
      when: createdAt.toLocal(),
      amount: amount,
      fee: fee,
      status: switch (status) {
        'COMPLETED' => TxnStatus.success,
        'FAILED' || 'EXPIRED_REFUNDED' || 'CANCELLED' => TxnStatus.failed,
        _ => TxnStatus.pending,
      },
      counterparty: counterpartyName ?? counterpartyPhone,
      counterpartyPhone: counterpartyPhone,
      paymentMethod: 'Mobile Money',
    );
  }
}

class TransfersPage {
  const TransfersPage({required this.items, required this.hasMore, this.nextCursor});

  final List<TransferItem> items;
  final bool hasMore;
  final String? nextCursor;

  factory TransfersPage.fromJson(Map<String, Object?> j) {
    final items = j['items'];
    if (items is! List) throw const FormatException('transfers page is malformed');
    return TransfersPage(
      items: [for (final i in items) TransferItem.fromJson((i as Map).cast<String, Object?>())],
      hasMore: j['has_more'] == true,
      nextCursor: j['next_cursor'] as String?,
    );
  }
}
