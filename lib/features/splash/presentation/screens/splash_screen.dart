import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../../../core/preferences/app_prefs.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/screens/auth_landing_screen.dart';
import '../../../home/presentation/screens/home_shell.dart';
import '../../../onboarding/presentation/screens/onboarding_screen.dart';

/// Path to the MoneyA mark (white version) used on dark/brand surfaces.
const String _brandLogoAsset = 'assets/logo/logo-white.svg';

/// First screen shown on app launch.
///
/// Full-bleed purple→black gradient with the MoneyA logo centered slightly
/// below middle. Status bar icons are forced to light for contrast.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const String routePath = '/';
  static const String routeName = 'splash';

  /// How long the splash logo is shown before auto-advancing.
  static const Duration _splashDuration = Duration(seconds: 2);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen._splashDuration, _goToOnboarding);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goToOnboarding() {
    if (!mounted) return;
    // A stored session means the user already signed in on this device:
    // skip onboarding and auth. An expired access token is refreshed
    // transparently by AuthInterceptor on the first 401.
    if (Get.isRegistered<SessionController>() &&
        Get.find<SessionController>().hasSession) {
      Get.off<void>(() => const HomeShell());
      return;
    }
    // If the user has already completed onboarding on this install
    // (flag persisted in secure storage, hydrated at boot), skip
    // straight to the auth landing. Onboarding is a first-run
    // experience and re-walking it on every cold start would be jarring.
    //
    // `Get.isRegistered` guards against test harnesses that don't
    // bootstrap AppPrefs — in that case we fall back to onboarding,
    // which is the safe default.
    final completed = Get.isRegistered<AppPrefs>()
        ? Get.find<AppPrefs>().onboardingComplete
        : false;
    if (completed) {
      Get.off<void>(
        () => const AuthLandingScreen(),
        routeName: AuthLandingScreen.routeName,
      );
    } else {
      Get.off<void>(() => const OnboardingScreen());
    }
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
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: const SafeArea(child: _SplashContent()),
        ),
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  @override
  Widget build(BuildContext context) {
    // Logo sits slightly below center (~55% down the screen), matching spec.
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoSize = constraints.maxWidth * 0.33;
        return Stack(
          children: [
            Align(
              alignment: const Alignment(0, 0.15),
              child: SizedBox(
                width: logoSize,
                height: logoSize,
                child: const _BrandLogo(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Loads the MoneyA mark from the bundled SVG asset.
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _brandLogoAsset,
      fit: BoxFit.contain,
      semanticsLabel: 'MoneyA',
    );
  }
}
