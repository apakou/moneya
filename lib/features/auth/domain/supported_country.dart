/// Supported countries for the phone-number country-code picker.
///
/// Scoped to West Africa: UEMOA (XOF) members plus the two key anglophone
/// markets (Nigeria, Ghana). The ISO code matches `phone_numbers_parser`'s
/// `IsoCode` so we can translate without an extra mapping table, and is also
/// the input expected by `CountryFlag.fromCountryCode`.
enum SupportedCountry {
  togo('TG', '228', 'Togo'),
  senegal('SN', '221', 'Sénégal'),
  ivoryCoast('CI', '225', "Côte d'Ivoire"),
  mali('ML', '223', 'Mali'),
  burkinaFaso('BF', '226', 'Burkina Faso'),
  benin('BJ', '229', 'Bénin'),
  nigeria('NG', '234', 'Nigeria'),
  ghana('GH', '233', 'Ghana');

  const SupportedCountry(this.isoCode, this.dialCode, this.label);

  /// ISO 3166-1 alpha-2 code (matches `phone_numbers_parser` IsoCode names
  /// and `country_flags` country codes).
  final String isoCode;

  /// International dial code without the leading '+'.
  final String dialCode;

  /// Human-readable name (localized later via l10n).
  final String label;
}
