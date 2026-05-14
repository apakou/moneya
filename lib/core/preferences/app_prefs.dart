import 'package:get/get.dart';

import '../logging/app_logger.dart';
import '../storage/secure_storage.dart';

/// Persistent app-level flags that are **not** auth identity:
///
///   • [onboardingComplete]: has the user walked through the splash →
///     onboarding → auth → KYC chain at least once on this install?
///     Used by the splash to decide whether to route to onboarding or
///     straight to the auth landing.
///   • [biometricEnabled]: did the user opt into biometric step-up
///     during the passcode-set screen? Consulted by
///     `TransactionAuthService` before prompting for fingerprint/Face ID.
///
/// Persisted to `flutter_secure_storage` (not SharedPreferences) for
/// two reasons:
///   1. The keys live alongside `session.v1` and `device.id`; one
///      storage backend is simpler to reason about and to clear on
///      logout.
///   2. iOS Keychain entries survive app reinstall (when the user
///      keeps the same backup) — which is exactly the UX we want for
///      `onboarding.complete`. SharedPreferences would force a fresh
///      onboarding after reinstall.
///
/// `clear()` wipes both flags. Used by logout: a logged-out device
/// should NOT short-circuit onboarding because the next user on the
/// same handset would skip KYC.
///
/// Bootstrap pattern (called from `main.dart`):
/// ```dart
/// final prefs = AppPrefs(secureStorage);
/// await prefs.load();
/// Get.put<AppPrefs>(prefs, permanent: true);
/// ```
class AppPrefs extends GetxService {
  AppPrefs(this._storage);

  final SecureStorage _storage;

  bool _onboardingComplete = false;
  bool _biometricEnabled = false;

  bool get onboardingComplete => _onboardingComplete;
  bool get biometricEnabled => _biometricEnabled;

  /// Hydrate flags from storage. Must complete before the first frame
  /// — splash routing reads [onboardingComplete] synchronously.
  Future<void> load() async {
    _onboardingComplete = await _readBool(SecureStorageKeys.onboardingComplete);
    _biometricEnabled = await _readBool(SecureStorageKeys.biometricEnabled);
    AppLogger.i(
      'prefs.load',
      {
        'onboarding_complete': _onboardingComplete,
        'biometric_enabled': _biometricEnabled,
      },
    );
  }

  Future<void> setOnboardingComplete(bool value) async {
    if (_onboardingComplete == value) return;
    _onboardingComplete = value;
    await _writeBool(SecureStorageKeys.onboardingComplete, value);
    AppLogger.i('prefs.onboarding_complete.set', {'value': value});
  }

  Future<void> setBiometricEnabled(bool value) async {
    if (_biometricEnabled == value) return;
    _biometricEnabled = value;
    await _writeBool(SecureStorageKeys.biometricEnabled, value);
    AppLogger.i('prefs.biometric_enabled.set', {'value': value});
  }

  /// Wipe persisted flags. Called from the logout flow so the next
  /// session starts from a clean splash → onboarding sequence.
  Future<void> clear() async {
    _onboardingComplete = false;
    _biometricEnabled = false;
    await _storage.delete(SecureStorageKeys.onboardingComplete);
    await _storage.delete(SecureStorageKeys.biometricEnabled);
    AppLogger.i('prefs.clear', const {});
  }

  Future<bool> _readBool(String key) async {
    final raw = await _storage.read(key);
    return raw == 'true';
  }

  Future<void> _writeBool(String key, bool value) =>
      _storage.write(key, value ? 'true' : 'false');
}
