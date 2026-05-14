import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/domain/supported_country.dart';
import '../../../home/domain/supported_currency.dart';
import '../../../transfer/presentation/widgets/country_picker_sheet.dart';
import '../../domain/momo_provider.dart';
import '../widgets/momo_provider_tile.dart';
import 'load_amount_screen.dart';

/// Step 1/2 of the Load Money flow — choose the *source* country and
/// mobile-money rail to debit.
///
/// The list of providers is filtered against [_country] via
/// [MomoProvider.byCountry] so the user only sees rails that actually
/// operate where they live. Switching country re-runs the filter so
/// the list never goes stale.
///
/// Tapping a provider tile pushes [LoadAmountScreen] (step 2) with
/// the country + provider locked in. There's no "Next" CTA: the tap
/// itself is the commit, matching the Wise and Revolut funding-source
/// picker patterns.
class LoadProviderScreen extends StatefulWidget {
  const LoadProviderScreen({
    required this.currency,
    this.initialCountry = SupportedCountry.ivoryCoast,
    super.key,
  });

  /// Home-screen currency. Carried through both Load steps so the
  /// amount keypad and limits use the user's selected unit.
  final SupportedCurrency currency;

  /// Country used to seed the provider filter. Defaults to Côte
  /// d'Ivoire — matches `TransferMoneyScreen`'s default and the
  /// MVP-corridor priority. Once we have a user-profile country
  /// field, that becomes the seed instead.
  final SupportedCountry initialCountry;

  static const String routePath = '/load/provider';

  @override
  State<LoadProviderScreen> createState() => _LoadProviderScreenState();
}

class _LoadProviderScreenState extends State<LoadProviderScreen> {
  late SupportedCountry _country = widget.initialCountry;

  Future<void> _onPickCountry() async {
    final picked = await showTransferCountryPickerSheet(
      context: context,
      selected: _country,
    );
    if (picked == null || picked == _country) return;
    setState(() => _country = picked);
  }

  void _onPickProvider(MomoProvider provider) {
    Get.to<void>(
      () => LoadAmountScreen(
        currency: widget.currency,
        country: _country,
        provider: provider,
      ),
    );
  }

  void _onBack() {
    FocusManager.instance.primaryFocus?.unfocus();
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final providers = MomoProvider.byCountry(_country);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header — same chrome as TransferMoneyScreen._Header.
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
                  child: Row(
                    children: [
                      BackChevronButton(
                        onTap: _onBack,
                        tooltip: l10n.commonBack,
                      ),
                      Text(
                        l10n.loadProviderHeaderTitle,
                        style: AppTextStyles.screenTitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.loadProviderSubtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Country chip — same idiom as the From row
                        // on TransferMoneyScreen but takes the full
                        // width since there's no provider pair.
                        Text(
                          l10n.loadProviderCountryLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _CountryChip(
                          country: _country,
                          onTap: _onPickCountry,
                        ),
                        const SizedBox(height: 28),

                        Text(
                          l10n.loadProviderListLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (providers.isEmpty)
                          _EmptyState(message: l10n.loadProviderEmptyMessage)
                        else
                          ...List.generate(providers.length, (i) {
                            final p = providers[i];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                    i == providers.length - 1 ? 0 : 10,
                              ),
                              child: MomoProviderTile(
                                provider: p,
                                onTap: () => _onPickProvider(p),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Country selector pill. Inlined (rather than imported from the
/// transfer feature) because the equivalent in
/// `transfer_money_screen.dart` is `_PrivateClass` and the styling is
/// trivially small (~30 lines). Once a second screen needs this, lift
/// to `lib/core/widgets/country_chip.dart`.
class _CountryChip extends StatelessWidget {
  const _CountryChip({required this.country, required this.onTap});

  final SupportedCountry country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              ClipOval(
                child: CountryFlag.fromCountryCode(
                  country.isoCode,
                  theme: const ImageTheme(
                    width: 28,
                    height: 28,
                    shape: Circle(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  country.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }
}
