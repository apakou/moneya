import 'package:flutter/foundation.dart';

/// Build-time configuration.
///
/// Every field is sourced from `--dart-define` so flavor wiring (PR3, deferred)
/// can supply different values per environment without changing Dart code.
///
/// Empty defaults are intentional. Code that depends on a value being set
/// (e.g., `CrashReporter` wanting a Sentry DSN) must check `isPresent` and
/// degrade to a no-op when absent. Cold boot must succeed even with all
/// values empty.
class Env {
  Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String flavorName = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  static const String posthogApiKey = String.fromEnvironment(
    'POSTHOG_API_KEY',
    defaultValue: '',
  );

  static const String posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );

  /// Debug-only escape hatch that lets engineers skip onboarding + KYC during
  /// local UI work. Honoured **only** when the build is debug AND the flavor
  /// is not prod AND this flag is true. Production builds ignore it
  /// unconditionally.
  static const bool bypassOnboardingAllowed = bool.fromEnvironment(
    'BYPASS_ONBOARDING',
    defaultValue: false,
  );

  static bool get bypassOnboarding =>
      kDebugMode && flavorName != 'prod' && bypassOnboardingAllowed;

  static AppFlavor get flavor {
    switch (flavorName) {
      case 'prod':
        return AppFlavor.prod;
      case 'staging':
        return AppFlavor.staging;
      case 'dev':
      default:
        return AppFlavor.dev;
    }
  }

  static bool get isProd => flavor == AppFlavor.prod;
}

enum AppFlavor { dev, staging, prod }
