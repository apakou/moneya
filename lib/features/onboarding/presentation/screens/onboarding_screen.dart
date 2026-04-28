import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
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
  AppLanguage _language = AppLanguage.english;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    // TODO: persist that onboarding has been completed (e.g. SharedPreferences)
    // before routing.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const AuthLandingScreen(),
        settings: const RouteSettings(name: AuthLandingScreen.routeName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    LanguagePage(
                      value: _language,
                      onChanged: (lang) => setState(() => _language = lang),
                    ),
                    const SendMoneyPage(),
                    const CrossCorridorPage(),
                  ],
                ),

                // --- Top-right "Skip" shortcut ---
                Positioned(
                  top: 8,
                  right: 12,
                  child: OnboardingSkipButton(onPressed: _skip),
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
                  child: OnboardingNextButton(onPressed: _goNext),
                ),

                // --- Bottom-left "Back" pill (hidden on the first page) ---
                if (_index > 0)
                  Positioned(
                    left: 24,
                    bottom: 60,
                    child: OnboardingBackButton(onPressed: _goBack),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
