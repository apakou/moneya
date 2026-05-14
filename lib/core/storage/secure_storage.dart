import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around `flutter_secure_storage` with sensible Android/iOS
/// options and a fake-able interface for tests.
///
/// Why an interface: `flutter_secure_storage` uses platform channels and
/// can't be exercised in `flutter test` without an integration harness.
/// [InMemorySecureStorage] is the test fake.
abstract class SecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Production-backed implementation.
class SecureStorageImpl implements SecureStorage {
  SecureStorageImpl([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// In-memory fake for tests and for tooling that can't talk to platform
/// channels. Not safe for production use — no encryption, no persistence.
@visibleForTesting
class InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _map = {};

  Map<String, String> get snapshot => Map.unmodifiable(_map);

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _map.clear();
  }
}

/// Canonical secure-storage keys. Centralising them prevents typos
/// from creating new "rooms" that nobody reads from.
class SecureStorageKeys {
  SecureStorageKeys._();

  static const String session = 'session.v1';
  static const String deviceId = 'device.id';
  static const String onboardingComplete = 'onboarding.complete';
  static const String biometricEnabled = 'biometric.enabled';
  static const String currencyPreferred = 'currency.preferred';
  static const String localeOverride = 'locale.override';
}
