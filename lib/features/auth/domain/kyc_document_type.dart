/// Identity documents accepted for MoneyA KYC verification.
///
/// Only [nationalId] and [passport] are accepted at MVP. Driver's license is
/// permitted by some UEMOA states for BCEAO Tier 2 but is intentionally
/// excluded for the first release to keep the verification pipeline simple.
/// Nigeria's BVN is *not* a document and is handled in a separate flow.
enum KycDocumentType {
  nationalId,
  passport;

  /// Human-facing label shown in the picker. Not localized yet — l10n is not
  /// wired in the project at this stage.
  String get label {
    switch (this) {
      case KycDocumentType.nationalId:
        return 'National ID';
      case KycDocumentType.passport:
        return 'Passport';
    }
  }
}
