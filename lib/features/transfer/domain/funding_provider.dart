/// Funding rails (a.k.a. "providers") that can debit the sender's
/// MoneyA balance to start a transfer.
///
/// Mock-faithful: the design lists "Moov Africa" as the funding source.
/// The full provider mix is broader and follows the african-payment-rails
/// skill (per-corridor MoMo + the in-app MoneyA balance). For now
/// these are hardcoded; later they'll be filtered server-side based on
/// the sender's KYC tier and corridor.
enum FundingProvider {
  moneyaBalance(
    id: 'moneya_balance',
    label: 'MoneyA balance',
    iconAsset: null,
  ),
  moovAfrica(
    id: 'moov_africa',
    label: 'Moov Africa',
    iconAsset: 'assets/images/Moov Money.png',
  ),
  orangeMoney(
    id: 'orange_money',
    label: 'Orange Money',
    iconAsset: null,
  ),
  mtnMomo(
    id: 'mtn_momo',
    label: 'MTN MoMo',
    iconAsset: null,
  ),
  wave(
    id: 'wave',
    label: 'Wave',
    iconAsset: null,
  );

  const FundingProvider({
    required this.id,
    required this.label,
    required this.iconAsset,
  });

  /// Stable id used by the backend (matches the provider key in the
  /// african-payment-rails skill).
  final String id;

  /// Display label shown in the picker and on the chip.
  final String label;

  /// Optional asset path for the provider's logo. When `null`, the
  /// picker renders a generic glyph (a colored square with the
  /// provider's first letter).
  final String? iconAsset;
}
