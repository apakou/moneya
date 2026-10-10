/// Currencies the home dashboard can display the user's balance in.
///
/// MVP scope: the five African corridor currencies MoneyA targets first.
/// USD / EUR may be added later for the diaspora corridors.
///
/// `code` is the ISO 4217 alpha code shown in the pill and used as the
/// stable identifier. `symbol` is the currency glyph shown in lists
/// (uses the local convention: "CFA" for both XOF and XAF since the
/// glyph "₣" is unfamiliar to most West/Central African users).
/// `name` is the human-readable name surfaced in the picker.
enum SupportedCurrency {
  xof(code: 'XOF', symbol: 'CFA', name: 'CFA Franc (West Africa)'),
  xaf(code: 'XAF', symbol: 'CFA', name: 'CFA Franc (Central Africa)'),
  ngn(code: 'NGN', symbol: '₦', name: 'Nigerian Naira'),
  ghs(code: 'GHC', symbol: '₵', name: 'Ghanaian Cedi'),
  kes(code: 'KES', symbol: 'Sh', name: 'Kenyan Shilling');

  const SupportedCurrency({
    required this.code,
    required this.symbol,
    required this.name,
  });

  /// ISO 4217 alpha-3 code, e.g. "NGN".
  ///
  /// Note: Ghana's true ISO 4217 code is `GHS`, but the existing mocks and
  /// in-country branding consistently use the legacy `GHC` form. Surface
  /// `GHC` to users for now; if/when we wire FX backends that demand the
  /// canonical ISO, add a separate `iso4217` field.
  final String code;

  /// Short symbol shown in compact UI surfaces, e.g. "₵", "₦", "CFA".
  final String symbol;

  /// Full human-readable name shown in the picker.
  final String name;

  /// Lookup by ISO code; returns null if no matching currency.
  static SupportedCurrency? fromCode(String code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}
