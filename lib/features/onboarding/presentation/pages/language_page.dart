import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/app_language.dart';
import '../widgets/onboarding_dropdown.dart';
import '../widgets/onboarding_hero.dart';

/// Onboarding step 1 — "Which language are you speaking?".
///
/// The page itself is layout-only; navigation controls (top skip, bottom
/// Next button, page indicator) live on the parent [OnboardingScreen].
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key, required this.value, required this.onChanged});

  final AppLanguage value;
  final ValueChanged<AppLanguage> onChanged;

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 3),
          Center(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.78,
              child: const OnboardingHero(
                iconAsset: 'assets/images/Language_Skill.png',
                iconSize: 100,
              ),
            ),
          ),
          const Spacer(flex: 3),
          const Text(
            'Which language are you speaking ?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onBrand,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 28),
          OnboardingDropdown<AppLanguage>(
            value: widget.value,
            items: AppLanguage.values
                .map(
                  (lang) => DropdownMenuItem<AppLanguage>(
                    value: lang,
                    child: Text(
                      lang.displayName,
                      style: TextStyle(
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
