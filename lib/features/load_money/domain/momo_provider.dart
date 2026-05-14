import '../../auth/domain/supported_country.dart';

/// Mobile-money provider that can credit the MoneyA balance.
///
/// These are the *debit-side* rails of an onramp ("load money") flow:
/// the user picks the wallet they want to pull funds FROM, the MoneyA
/// backend issues a USSD push / API call to the chosen provider, the
/// user authorizes on their phone, and the funds land in MoneyA.
///
/// This is intentionally a separate enum from `FundingProvider` in
/// the transfer feature even though several names overlap. The Send
/// flow's `FundingProvider` is the *source of funds* for an outgoing
/// debit (MoneyA wallet, Moov, …) and includes the in-app wallet
/// itself; here we only list *external* MoMo wallets that can be
/// debited to top up — the MoneyA wallet itself has nothing to credit
/// from. Keeping the enums separate lets each feature evolve its
/// availability rules without cross-feature breakage.
///
/// The provider catalog matches the african-payment-rails skill's
/// country matrix. As Phase-2/3 corridors come online (NG, GH, KE,
/// CM, GA) this list is extended; the country filter ([byCountry])
/// is what decides what the user actually sees.
enum MomoProvider {
  /// Wave. Dominant in Senegal (~60% share), heavy in Côte d'Ivoire,
  /// growing in Mali. Branded yellow.
  wave(
    id: 'wave',
    label: 'Wave',
    iconAsset: null,
    countries: {
      SupportedCountry.senegal,
      SupportedCountry.ivoryCoast,
      SupportedCountry.mali,
    },
  ),

  /// Orange Money. Pan-francophone footprint — present in most
  /// UEMOA countries plus CEMAC. The default rail outside Senegal
  /// (Wave country).
  orangeMoney(
    id: 'orange_money',
    label: 'Orange Money',
    iconAsset: null,
    countries: {
      SupportedCountry.senegal,
      SupportedCountry.ivoryCoast,
      SupportedCountry.mali,
      SupportedCountry.burkinaFaso,
    },
  ),

  /// MTN MoMo. Dominant in Ghana (~80% share), strong in Benin,
  /// growing in Côte d'Ivoire. Pan-anglophone-Africa footprint plus
  /// francophone Benin.
  mtnMomo(
    id: 'mtn_momo',
    label: 'MTN MoMo',
    iconAsset: null,
    countries: {
      SupportedCountry.ghana,
      SupportedCountry.ivoryCoast,
      SupportedCountry.benin,
    },
  ),

  /// Moov Money. Operates in most UEMOA states; branded as "Flooz"
  /// in Benin and Togo but shares the same backend, so we surface a
  /// single entry and let the backend route by country.
  moovAfrica(
    id: 'moov_africa',
    label: 'Moov Money',
    iconAsset: 'assets/images/Moov Money.png',
    countries: {
      SupportedCountry.ivoryCoast,
      SupportedCountry.mali,
      SupportedCountry.burkinaFaso,
      SupportedCountry.benin,
      SupportedCountry.togo,
    },
  ),

  /// T-Money (Togocom). The dominant rail in Togo alongside Flooz.
  tMoney(
    id: 't_money',
    label: 'T-Money',
    iconAsset: null,
    countries: {SupportedCountry.togo},
  ),

  /// OPay. Nigeria-only. Largest non-bank wallet in NG. Bank-transfer
  /// rails (NIP) will be added as a separate provider later.
  opay(
    id: 'opay',
    label: 'OPay',
    iconAsset: null,
    countries: {SupportedCountry.nigeria},
  );

  const MomoProvider({
    required this.id,
    required this.label,
    required this.iconAsset,
    required this.countries,
  });

  /// Stable id used by the backend (matches the provider key in the
  /// african-payment-rails skill).
  final String id;

  /// Display label shown in the picker. Not localized: provider
  /// names are proper nouns/trademarks and stay consistent across
  /// languages.
  final String label;

  /// Optional asset path for the provider's logo. When `null` the
  /// tile renders a generic colored disc with the provider's first
  /// letter — placeholder until real asset SVGs are added.
  final String? iconAsset;

  /// Countries where this provider is active. Used by [byCountry]
  /// to filter the picker; backend will revalidate at request time
  /// (the user's KYC tier may also restrict the list further).
  final Set<SupportedCountry> countries;

  /// Providers active in [country], in the canonical display order
  /// (declaration order of the enum). Returns an empty list when
  /// the country has no rails in scope yet — the caller is
  /// responsible for showing an "unavailable" empty state in that
  /// case rather than crashing.
  static List<MomoProvider> byCountry(SupportedCountry country) {
    return MomoProvider.values
        .where((p) => p.countries.contains(country))
        .toList(growable: false);
  }
}
