import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'create_account_screen.dart';

/// Auth landing screen shown after the onboarding flow finishes.
///
/// Presents the MoneyA wordmark + tagline and two CTAs (Login / Create
/// Account). No app bar, no onboarding chrome — the brand gradient is the
/// only background.
class AuthLandingScreen extends StatelessWidget {
  const AuthLandingScreen({super.key});

  static const String routePath = '/auth';
  static const String routeName = 'auth_landing';

  void _goToLogin(BuildContext context) {
    // TODO: navigate to the login screen once it exists.
  }

  void _goToCreateAccount(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CreateAccountScreen(),
        settings: const RouteSettings(name: CreateAccountScreen.routeName),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 5),

                  // Brand wordmark + tagline.
                  SvgPicture.asset(
                    'assets/logo/logo-horizontal.svg',
                    height: 96,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Say it. We send it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.onBrandMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Primary actions.
                  _AuthPillButton(
                    label: 'Login',
                    background: Colors.white,
                    foreground: AppColors.actionPurple,
                    onPressed: () => _goToLogin(context),
                  ),
                  const SizedBox(height: 12),
                  _AuthPillButton(
                    label: 'Create Account',
                    background: AppColors.actionPurple,
                    foreground: AppColors.onBrand,
                    onPressed: () => _goToCreateAccount(context),
                  ),

                  const Spacer(flex: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width pill button used by the auth landing screen.
class _AuthPillButton extends StatelessWidget {
  const _AuthPillButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.subsectionTitle.copyWith(
                color: foreground,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
