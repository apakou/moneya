import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/config/env.dart';

/// `Env` is built from `const String.fromEnvironment` values, which means
/// they're frozen at compile-time of the test binary. `flutter test`
/// doesn't expose `--dart-define` per case, so this test only asserts the
/// safe defaults are what we expect. Per-flavor coverage is the job of
/// CI matrix builds (`scripts/run_{dev,staging,prod}.sh`).
void main() {
  group('Env defaults', () {
    test('flavor defaults to dev', () {
      expect(Env.flavorName, 'dev');
      expect(Env.flavor, AppFlavor.dev);
      expect(Env.isProd, isFalse);
    });

    test('apiBaseUrl is empty by default', () {
      expect(Env.apiBaseUrl, '');
    });

    test('sentryDsn and posthogApiKey are empty by default', () {
      expect(Env.sentryDsn, '');
      expect(Env.posthogApiKey, '');
    });

    test('posthogHost defaults to EU cloud', () {
      expect(Env.posthogHost, 'https://eu.i.posthog.com');
    });

    test('bypassOnboardingAllowed is false by default', () {
      expect(Env.bypassOnboardingAllowed, isFalse);
      // bypassOnboarding === kDebugMode && flavor!=prod && allowed.
      // Default allowed=false ⇒ effective flag is false.
      expect(Env.bypassOnboarding, isFalse);
    });
  });
}
