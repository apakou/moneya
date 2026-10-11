/// `Quote` (openapi.yaml). Amounts are decimal STRINGS — never doubles.
class RampQuote {
  const RampQuote({
    required this.id,
    required this.kind,
    required this.fromCurrency,
    required this.fromAmount,
    required this.toCurrency,
    required this.toAmount,
    required this.rate,
    required this.fee,
    required this.expiresAt,
  });

  final String id;
  final String kind; // ONRAMP | OFFRAMP
  final String fromCurrency;
  final String fromAmount;
  final String toCurrency;
  final String toAmount;
  final String rate;
  final String fee;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  /// True when the user-visible numbers differ from [other] — a re-quote must be
  /// shown and re-confirmed, never swapped in silently.
  bool differsFrom(RampQuote other) =>
      toAmount != other.toAmount || fee != other.fee || fromAmount != other.fromAmount;

  factory RampQuote.fromJson(Map<String, Object?> j) {
    String s(String k) {
      final v = j[k];
      if (v is! String) throw FormatException('quote.$k missing');
      return v;
    }

    return RampQuote(
      id: s('id'),
      kind: s('kind'),
      fromCurrency: s('from_currency'),
      fromAmount: s('from_amount'),
      toCurrency: s('to_currency'),
      toAmount: s('to_amount'),
      rate: s('rate'),
      fee: s('fee'),
      expiresAt: DateTime.parse(s('expires_at')),
    );
  }
}

enum RampDirection { onramp, offramp }

/// `OnrampOrder` / `OfframpOrder` (openapi.yaml), unified.
class RampOrder {
  const RampOrder({
    required this.id,
    required this.direction,
    required this.status,
    required this.quote,
    required this.createdAt,
    this.providerReference,
    this.failureReason,
    this.ussdInstructions,
    this.checkoutUrl,
    this.finishedAt,
  });

  final String id;
  final RampDirection direction;

  /// Onramp: AWAITING_PAYMENT, COLLECTED, CREDITING_WALLET, COMPLETED, FAILED, EXPIRED.
  /// Offramp: PROCESSING, SETTLED, FAILED, REFUNDED.
  final String status;
  final RampQuote quote;
  final String? providerReference;
  final String? failureReason;
  final String? ussdInstructions;
  final String? checkoutUrl;
  final DateTime createdAt;
  final DateTime? finishedAt;

  /// The money arrived (top-up credited / cash-out paid).
  bool get isSuccess => status == 'COMPLETED' || status == 'SETTLED';

  /// Nothing more will happen to this order.
  bool get isTerminal => const {'COMPLETED', 'SETTLED', 'FAILED', 'EXPIRED', 'REFUNDED'}.contains(status);

  /// Cash-out failed and the money went back to the balance.
  bool get wasRefunded => status == 'REFUNDED';

  factory RampOrder.fromJson(Map<String, Object?> j, RampDirection direction) {
    final id = j['id'];
    final status = j['status'];
    final quote = j['quote'];
    final created = j['created_at'];
    if (id is! String || status is! String || quote is! Map || created is! String) {
      throw const FormatException('order response is malformed');
    }
    final finished = (j['completed_at'] ?? j['settled_at']) as String?;
    return RampOrder(
      id: id,
      direction: direction,
      status: status,
      quote: RampQuote.fromJson(quote.cast<String, Object?>()),
      providerReference: j['provider_reference'] as String?,
      failureReason: j['failure_reason'] as String?,
      ussdInstructions: j['ussd_instructions'] as String?,
      checkoutUrl: j['checkout_url'] as String?,
      createdAt: DateTime.parse(created),
      finishedAt: finished == null ? null : DateTime.parse(finished),
    );
  }
}
