/// Direction of a transaction relative to the current user.
///
/// We deliberately model only `sent` / `received` here. "Paid"
/// (merchant transactions) was an early concept on the home screen
/// but in practice it collapses to `sent` for transfer history;
/// merchant context lives on the [Transaction] separately when the
/// backend lands.
enum TxnKind { sent, received }

/// Settlement status of a transaction.
///
/// The home screen + transactions list filter chips both read this
/// directly. `pending` covers anything that has been accepted by
/// the backend but not yet confirmed on rail (mobile-money queue,
/// settlement pending, FX rebalancing, etc.); `failed` covers anything
/// the user should consider unsuccessful.
enum TxnStatus { success, pending, failed }

/// One transfer row, used by both the home dashboard's recent-txn
/// strip and the dedicated transactions tab.
///
/// Mock-only for now — once `GET /transfers` lands this will be a
/// freezed model populated by a Riverpod provider; everything down
/// to the detail screen consumes it the same way.
///
/// `counterparty` is the user-facing name we show on the detail
/// screen ("From Axel Asamoa" / "To Maria Diop"). On the list rows
/// today we only show the direction label (`Sent` / `Received`)
/// because the design mocks haven't introduced counterparty there
/// yet; lifting that lookup is a downstream change.
class Transaction {
  const Transaction({
    required this.id,
    required this.kind,
    required this.when,
    required this.amount,
    required this.status,
    required this.counterparty,
    required this.counterpartyPhone,
    required this.paymentMethod,
    this.fee = '0',
  });

  /// Short user-visible reference (first 8 chars of a UUID once
  /// real). Used for support lookups and copy-to-clipboard on the
  /// detail screen. Mock data uses an 8-char hex slice.
  final String id;

  final TxnKind kind;
  final DateTime when;

  /// Pre-formatted amount string (no currency symbol, no fee). The
  /// transaction list and detail screens both render this verbatim
  /// alongside the screen-level currency code; once the backend
  /// model lands this will become a numeric type so we can run real
  /// formatting / FX conversion on it.
  final String amount;

  /// Provider-side fee, same formatting rules as [amount]. Defaults
  /// to `'0'` for `received` transfers (the recipient never pays a
  /// fee on this rail).
  final String fee;

  final TxnStatus status;

  /// Display name of the other party. Sender on `received`,
  /// recipient on `sent`. Mock data; will come from the contacts
  /// resolver / backend once wired.
  final String counterparty;

  /// E.164 phone number of the counterparty, e.g. `+233241234567`.
  /// Mocked.
  final String counterpartyPhone;

  /// User-facing payment-method label, e.g. `Mobile Money • MTN MoMo`
  /// or `Bank Transfer • Ecobank`. Mocked.
  final String paymentMethod;

  /// "Sent" / "Received" — the user-facing direction label.
  String get directionLabel => switch (kind) {
        TxnKind.sent => 'Sent',
        TxnKind.received => 'Received',
      };

  /// "From" / "To" — the preposition that pairs with the
  /// counterparty name on the detail screen.
  String get counterpartyLabel => switch (kind) {
        TxnKind.sent => 'To',
        TxnKind.received => 'From',
      };

  /// `amount + fee` as a string, computed only for display, with exact decimal arithmetic (amounts
  /// are decimal strings like `98.5`, never doubles). Falls back to [amount] alone if either
  /// component is not a plain decimal — a malformed value must never crash the detail screen.
  String get total {
    final a = _micro(amount);
    final f = _micro(fee);
    if (a == null || f == null) return amount;
    final sum = a + f;
    final whole = sum ~/ 1000000;
    final frac = (sum % 1000000).toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '');
    return frac.isEmpty ? '$whole' : '$whole.$frac';
  }

  /// Micro-units (6 decimals) of a plain non-negative decimal string, or null.
  static int? _micro(String v) {
    final m = RegExp(r'^(\d+)(?:\.(\d{1,6}))?$').firstMatch(v);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 1000000 + int.parse((m.group(2) ?? '').padRight(6, '0'));
  }

  /// Display timestamp, e.g. `Jun 12, 2025 - 10:25 AM`. Single
  /// source of truth for the formatted form so list rows and the
  /// detail screen stay in sync.
  String get timestamp {
    const monthNames = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h12 = when.hour == 0
        ? 12
        : (when.hour > 12 ? when.hour - 12 : when.hour);
    final mm = when.minute.toString().padLeft(2, '0');
    final period = when.hour < 12 ? 'AM' : 'PM';
    return '${monthNames[when.month]} ${when.day}, ${when.year} - $h12:$mm $period';
  }
}
