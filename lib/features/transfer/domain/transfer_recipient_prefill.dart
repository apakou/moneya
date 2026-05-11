import '../../auth/domain/supported_country.dart';

/// Prefill payload for [TransferMoneyScreen].
///
/// Used when the transfer flow is opened from a deep entry point that
/// already knows the recipient — currently the Home screen's "Your
/// Favorites" strip. Carries just enough to populate the recipient
/// country, recipient phone (national digits, no dial code), and an
/// optimistic display name. The real name is overwritten by the
/// directory lookup result when it resolves.
///
/// `nationalPhone` MUST be national digits only — no leading `0`, no
/// dial code, no spaces. Validation against [country] happens inside
/// the screen via `phone_numbers_parser`.
class TransferRecipientPrefill {
  const TransferRecipientPrefill({
    required this.country,
    required this.nationalPhone,
    required this.displayName,
  });

  final SupportedCountry country;
  final String nationalPhone;
  final String displayName;
}
