import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive_scale.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/app_language.dart';
import '../widgets/onboarding_dropdown.dart';
import '../widgets/onboarding_hero.dart';

/// Onboarding step 1 — language selection.
///
/// The page itself is layout-only; navigation controls (top skip, bottom
/// Next button, page indicator) live on the parent [OnboardingScreen].
///
/// Language names in the dropdown are rendered as **endonyms** (each
/// language in its own name — "English", "Français") regardless of the
/// active UI locale. This is the standard i18n convention used by
/// Apple, Google, Microsoft, etc.: a French speaker arriving on an
/// English UI must still recognize their own language in the picker,
/// and vice versa.
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key, required this.value, required this.onChanged});

  final AppLanguage value;
  final ValueChanged<AppLanguage> onChanged;

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  /// Endonym for a given [AppLanguage], pulled from the localization
  /// catalog. Lives on `AppLocalizations` rather than the enum so
  /// translators can correct the spelling/punctuation per locale
  /// without a code change. The strings themselves do NOT vary by
  /// active UI locale — both `app_en.arb` and `app_fr.arb` carry the
  /// same endonyms, intentionally (see class doc above).
  String _endonym(BuildContext context, AppLanguage lang) {
    final l10n = AppLocalizations.of(context);
    switch (lang) {
      case AppLanguage.english:
        return l10n.languageEnglish;
      case AppLanguage.french:
        return l10n.languageFrench;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 3),
          Center(
            child: SizedBox(
              // The language step's hero is slightly smaller than
              // steps 2 + 3 (78% vs 82% of viewport) — design intent
              // is "softer landing on the first screen". Additionally
              // capped at 34% of viewport height (vs 38% on later
              // steps) because this page has a dropdown sibling
              // *below* the headline, which competes for vertical
              // space on short 640dp screens.
              width: ResponsiveScale.clampSquare(
                context: context,
                minWidth: 360,
                maxWidth: 600,
                minValue: 360 * 0.78,
                maxValue: 420,
                maxHeightFraction: 0.34,
              ),
              child: const OnboardingHero(
                iconAsset: 'assets/images/Language_Skill.png',
                iconSize: 100,
              ),
            ),
          ),
          const Spacer(flex: 3),
          Text(
            l10n.onboardingLanguageHeadline,
            textAlign: TextAlign.center,
            style: AppTextStyles.heroOnboarding,
          ),
          const SizedBox(height: 28),
          OnboardingDropdown<AppLanguage>(
            value: widget.value,
            items: AppLanguage.values
                .map(
                  (lang) => DropdownMenuItem<AppLanguage>(
                    value: lang,
                    child: Text(
                      _endonym(context, lang),
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Satoshi',
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) widget.onChanged(v);
            },
          ),
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}
