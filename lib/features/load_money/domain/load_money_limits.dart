import '../../home/domain/supported_currency.dart';

/// Daily / per-transaction onramp limits, expressed in the user's
/// home currency.
///
/// These are the *client-side* caps shown in the UI; the backend
/// re-validates against the user's KYC tier at request time and is
/// the ultimate authority. The amounts here are deliberately
/// conservative — under-shooting and letting the server explain the
/// real cap is far better UX than letting a user enter an amount
/// that will be rejected after they swipe to confirm.
///
/// Source of numbers: BCEAO mobile-money instruction (UEMOA tiers
/// 1/2), CBN three-tier KYC (Nigeria), and BoG GHIPSS guidance
/// (Ghana). See the african-payment-rails skill for the full matrix.
class LoadMoneyLimits {
  const LoadMoneyLimits._({
    required this.maxPerTransaction,
    required this.maxDaily,
    required this.tierLabel,
  });

  /// Single-transaction ceiling in the home currency's smallest UI
  /// unit (i.e. whole XOF — no decimal for CFA; major units for NGN
  /// / GHC / KES). Stored as `num` so the typical CFA case stays an
  /// `int` while NGN/KES can carry one decimal when we localize the
  /// formatting later.
  final num maxPerTransaction;

  /// Rolling 24-hour ceiling. Always >= [maxPerTransaction]. For
  /// MVP we surface a single cap (= daily); the per-txn vs daily
  /// split exists so we can lower per-txn under fraud-rule pressure
  /// without dropping the daily budget.
  final num maxDaily;

  /// Short human label of the active KYC tier ("Tier 2", "BVN
  /// Verified", …). Surfaced inline in the helper text so the user
  /// understands *why* the cap is what it is and what unlocking the
  /// next tier would do.
  final String tierLabel;

  /// MVP defaults per corridor.
  ///
  /// Numbers are intentionally rounded — the exact regulator figure
  /// is moot until backend KYC ladder is wired. Once `/v1/me/limits`
  /// exists, drop this static map and feed [LoadMoneyLimits] from
  /// the API response instead.
  static LoadMoneyLimits defaultFor(SupportedCurrency currency) {
    switch (currency) {
      case SupportedCurrency.xof:
      case SupportedCurrency.xaf:
        // BCEAO/BEAC Tier 2 — ~1,000,000 CFA daily (~ USD 1,650).
        return const LoadMoneyLimits._(
          maxPerTransaction: 1000000,
          maxDaily: 1000000,
          tierLabel: 'Tier 2',
        );
      case SupportedCurrency.ngn:
        // CBN Tier 2 (BVN-verified) — ~500,000 NGN daily.
        return const LoadMoneyLimits._(
          maxPerTransaction: 500000,
          maxDaily: 500000,
          tierLabel: 'Tier 2',
        );
      case SupportedCurrency.ghs:
        // BoG medium-account threshold — ~10,000 GHS daily.
        return const LoadMoneyLimits._(
          maxPerTransaction: 10000,
          maxDaily: 10000,
          tierLabel: 'Medium',
        );
      case SupportedCurrency.kes:
        // M-Pesa standard cap — ~250,000 KES daily.
        return const LoadMoneyLimits._(
          maxPerTransaction: 250000,
          maxDaily: 250000,
          tierLabel: 'Standard',
        );
    }
  }

  /// `true` when [amount] is strictly within the per-transaction cap.
  /// `amount` is expected to be the parsed numeric value of the
  /// keypad input (e.g. `15000` for "15,000"). Negative / NaN inputs
  /// short-circuit to `false` so the caller doesn't need to guard.
  bool isWithinLimit(num amount) {
    if (amount.isNaN || amount.isNegative) return false;
    return amount > 0 && amount <= maxPerTransaction;
  }
}
