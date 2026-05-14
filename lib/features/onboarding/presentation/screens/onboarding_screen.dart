import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/preferences/app_prefs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../main.dart' show LocaleScope;
import '../../../auth/presentation/screens/auth_landing_screen.dart';
import '../../domain/app_language.dart';
import '../pages/cross_corridor_page.dart';
import '../pages/language_page.dart';
import '../pages/send_money_page.dart';
import '../widgets/onboarding_next_button.dart';
import '../widgets/onboarding_page_indicator.dart';

/// Host screen for the 3-step onboarding flow.
///
/// Steps: language selection, send-money pitch, cross-corridor pitch. After
/// the final step (or "Skip") the user lands on [AuthLandingScreen].
///
/// The language selected on step 1 is applied **live** to the app via
/// [LocaleScope]/`LocaleController.setLocale` so the headlines on
/// steps 2 + 3 (and the Next/Skip/Back labels) immediately appear in
/// the chosen language. This is the entire point of putting the
/// language step first — picking Français at step 1 and then reading
/// English on step 2 would be a UX bug.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String routePath = '/onboarding';
  static const String routeName = 'onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _pageCount = 3;

  final PageController _controller = PageController();
  int _index = 0;

  /// Local mirror of the picker selection. Initialized lazily from
  /// the active app locale in [didChangeDependencies] (we can't read
  /// inherited widgets in [initState]). This way the picker always
  /// opens reflecting reality — if the user is already on French
  /// (e.g. they returned through dev-bypass), the dropdown opens on
  /// Français rather than snapping back to English.
  AppLanguage? _language;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed only once; subsequent locale changes are driven by the
    // user via the picker itself.
    _language ??= AppLanguage.fromAppLocale(
      LocaleScope.of(context, listen: false).current,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLanguageChanged(AppLanguage lang) {
    setState(() => _language = lang);
    // Fire-and-forget — `setLocale` persists to SharedPreferences but
    // we don't need to await it; the in-memory switch (which is what
    // drives the UI rebuild) is synchronous via `notifyListeners`.
    LocaleScope.of(context, listen: false).setLocale(lang.appLocale);
  }

  void _goNext() {
    if (_index < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _goBack() {
    if (_index > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  void _skip() => _finishOnboarding();

  void _finishOnboarding() {
    // Mark onboarding complete BEFORE navigating so a forced restart
    // (e.g. process kill mid-route) doesn't drop the user back into
    // step 1. Fire-and-forget is safe: the write goes to secure
    // storage and the next splash boot reads the same key.
    Get.find<AppPrefs>().setOnboardingComplete(true);
    Get.off<void>(
      () => const AuthLandingScreen(),
      routeName: AuthLandingScreen.routeName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Guard: `_language` is hydrated in `didChangeDependencies` which
    // runs before `build`, so this null-coalesce is defensive only.
    final language = _language ?? AppLanguage.english;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Stack(
              children: [
                // --- Page content ---
                // PageView (not a Navigator-based wizard) is intentional
                // here: the three onboarding pages are *peers* the user
                // can swipe between freely, with no per-page state to
                // discard and no commit semantics. System back from any
                // page exits the app, which matches the
                // "before-the-app-starts" mental model — going back from
                // onboarding should drop the user out, not surface a
                // previous page. Switching to `Navigator.push` would
                // wrongly turn back into a "previous-page" gesture and
                // require us to manage a route stack we don't need. See
                // flutter-navigation skill §1 (root vs. push routes).
                PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    LanguagePage(
                      value: language,
                      onChanged: _onLanguageChanged,
                    ),
                    const SendMoneyPage(),
                    const CrossCorridorPage(),
                  ],
                ),

                // --- Top-right "Skip" shortcut ---
                Positioned(
                  top: 8,
                  right: 12,
                  child: OnboardingSkipButton(
                    onPressed: _skip,
                    label: l10n.onboardingSkip,
                  ),
                ),

                // --- Bottom controls: indicator (left) + Next pill (right) ---
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: 24,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: OnboardingPageIndicator(
                            currentIndex: _index,
                            count: _pageCount,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 24,
                  bottom: 60,
                  child: OnboardingNextButton(
                    onPressed: _goNext,
                    label: l10n.onboardingNext,
                  ),
                ),

                // --- Bottom-left "Back" pill (hidden on the first page) ---
                if (_index > 0)
                  Positioned(
                    left: 24,
                    bottom: 60,
                    child: OnboardingBackButton(
                      onPressed: _goBack,
                      label: l10n.onboardingBack,
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
