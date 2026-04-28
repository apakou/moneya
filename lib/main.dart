import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'features/home/presentation/screens/home_shell.dart';
import 'features/splash/presentation/screens/splash_screen.dart';

void main() {
  runApp(const MoneyaApp());
}

/// Dev-only flag to bypass the splash → onboarding → auth → KYC chain
/// and land directly on [HomeShell].
///
/// Defaults to `true` while we iterate on the post-onboarding screens
/// (home, transfer, confirm, success/pending/failed, transactions) so
/// hot-reloading doesn't kick us back to the country picker every
/// time. Flip back to `false` — or guard with `kReleaseMode` (already
/// done below) — before shipping.
///
/// Override at run-time without code edits via:
/// `flutter run --dart-define=BYPASS_ONBOARDING=false`
const bool _bypassOnboarding = bool.fromEnvironment(
  'BYPASS_ONBOARDING',
  defaultValue: true,
);

class MoneyaApp extends StatelessWidget {
  const MoneyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // In release builds we ALWAYS run the real flow regardless of the
    // dart-define — this prevents us shipping a build that skips KYC.
    final useBypass = _bypassOnboarding && !kReleaseMode;
    return MaterialApp(
      title: 'MoneyA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brandPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppColors.black,
        fontFamily: 'Satoshi',
      ),
      home: useBypass ? const HomeShell() : const SplashScreen(),
    );
  }
}
