import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';

void main() {
  late InMemorySecureStorage storage;
  late SessionStore store;

  setUp(() {
    storage = InMemorySecureStorage();
    store = SessionStore(storage);
  });

  AuthSession buildSession() => AuthSession(
        accessToken: 'access-123',
        refreshToken: 'refresh-123',
        expiresAt: DateTime.utc(2026, 5, 14, 12),
        userId: 'user-1',
        phone: '+221770000000',
        countryIso2: 'SN',
        kycTier: KycTier.tier1,
      );

  group('session round-trip', () {
    test('readSession returns null when nothing persisted', () async {
      expect(await store.readSession(), isNull);
    });

    test('writeSession then readSession returns the same value', () async {
      final session = buildSession();
      await store.writeSession(session);
      expect(await store.readSession(), equals(session));
    });

    test('clearSession removes the persisted blob', () async {
      await store.writeSession(buildSession());
      await store.clearSession();
      expect(await store.readSession(), isNull);
      expect(storage.snapshot.containsKey(SecureStorageKeys.session), isFalse);
    });

    test('corrupt blob is dropped and treated as empty', () async {
      await storage.write(SecureStorageKeys.session, 'not-json');
      expect(await store.readSession(), isNull);
      expect(storage.snapshot.containsKey(SecureStorageKeys.session), isFalse);
    });
  });

  group('readOrCreateDeviceId', () {
    test('mints a fresh UUID v4 on first call', () async {
      final id = await store.readOrCreateDeviceId();
      expect(id, isNotEmpty);
      // UUID v4 — 36 chars including hyphens.
      expect(id.length, 36);
      expect(id[14], '4');
    });

    test('returns the same id on subsequent calls', () async {
      final id1 = await store.readOrCreateDeviceId();
      final id2 = await store.readOrCreateDeviceId();
      expect(id2, id1);
    });

    test('device id survives clearSession', () async {
      final id = await store.readOrCreateDeviceId();
      await store.writeSession(buildSession());
      await store.clearSession();
      expect(await store.readOrCreateDeviceId(), id);
    });
  });
}
