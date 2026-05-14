import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/preferences/app_prefs.dart';
import 'package:moneya/core/storage/secure_storage.dart';

/// Counts writes so we can assert no-op short-circuits don't hit storage.
class _CountingStorage extends InMemorySecureStorage {
  int writes = 0;
  int deletes = 0;

  @override
  Future<void> write(String key, String value) async {
    writes++;
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    await super.delete(key);
  }
}

void main() {
  group('AppPrefs', () {
    test('load from empty storage yields false for both flags', () async {
      final prefs = AppPrefs(InMemorySecureStorage());
      await prefs.load();

      expect(prefs.onboardingComplete, isFalse);
      expect(prefs.biometricEnabled, isFalse);
    });

    test('setOnboardingComplete persists across instances', () async {
      final storage = InMemorySecureStorage();
      final first = AppPrefs(storage);
      await first.load();
      await first.setOnboardingComplete(true);

      // Fresh instance backed by same storage.
      final second = AppPrefs(storage);
      await second.load();

      expect(second.onboardingComplete, isTrue);
      expect(second.biometricEnabled, isFalse);
    });

    test('setBiometricEnabled persists across instances', () async {
      final storage = InMemorySecureStorage();
      final first = AppPrefs(storage);
      await first.load();
      await first.setBiometricEnabled(true);

      final second = AppPrefs(storage);
      await second.load();

      expect(second.biometricEnabled, isTrue);
      expect(second.onboardingComplete, isFalse);
    });

    test('clear() resets both flags in memory and on disk', () async {
      final storage = InMemorySecureStorage();
      final prefs = AppPrefs(storage);
      await prefs.load();
      await prefs.setOnboardingComplete(true);
      await prefs.setBiometricEnabled(true);

      await prefs.clear();

      expect(prefs.onboardingComplete, isFalse);
      expect(prefs.biometricEnabled, isFalse);

      final rehydrated = AppPrefs(storage);
      await rehydrated.load();
      expect(rehydrated.onboardingComplete, isFalse);
      expect(rehydrated.biometricEnabled, isFalse);
    });

    test('setters short-circuit when value is unchanged', () async {
      final storage = _CountingStorage();
      final prefs = AppPrefs(storage);
      await prefs.load();

      // Default is false → setting false again is a no-op.
      await prefs.setOnboardingComplete(false);
      await prefs.setBiometricEnabled(false);
      expect(storage.writes, 0);

      // First true-write does hit storage.
      await prefs.setOnboardingComplete(true);
      expect(storage.writes, 1);

      // Setting true again is a no-op.
      await prefs.setOnboardingComplete(true);
      expect(storage.writes, 1);
    });
  });
}
