import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';

void main() {
  AuthSession buildSession({String access = 'acc-1', String refresh = 'rfr-1'}) =>
      AuthSession(
        accessToken: access,
        refreshToken: refresh,
        // Use UTC so encode→decode round-trips to the same DateTime
        // (decode always returns a UTC instant).
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
        userId: 'user-1',
        phone: '+221770000000',
        countryIso2: 'SN',
        kycTier: KycTier.tier1,
      );

  late InMemorySecureStorage storage;
  late SessionStore store;

  setUp(() {
    storage = InMemorySecureStorage();
    store = SessionStore(storage);
  });

  group('bootstrap', () {
    test('with empty storage produces non-null deviceId and null session',
        () async {
      final controller = SessionController(
        store: store,
        refresher: _FakeRefresher(),
      );
      await controller.bootstrap();
      expect(controller.hasSession, isFalse);
      expect(controller.deviceId, isNotEmpty);
    });

    test('loads previously-persisted session', () async {
      final existing = buildSession();
      await store.writeSession(existing);
      final controller = SessionController(
        store: store,
        refresher: _FakeRefresher(),
      );
      await controller.bootstrap();
      expect(controller.hasSession, isTrue);
      expect(controller.currentAccessToken, existing.accessToken);
      expect(controller.currentUserId, existing.userId);
    });
  });

  group('setSession / clear', () {
    test('setSession persists and updates the rx value', () async {
      final controller = SessionController(
        store: store,
        refresher: _FakeRefresher(),
      );
      await controller.bootstrap();
      final session = buildSession();
      await controller.setSession(session);
      expect(controller.currentAccessToken, session.accessToken);
      expect(await store.readSession(), equals(session));
    });

    test('clear wipes session but preserves deviceId', () async {
      final controller = SessionController(
        store: store,
        refresher: _FakeRefresher(),
      );
      await controller.bootstrap();
      final originalDeviceId = controller.deviceId;
      await controller.setSession(buildSession());
      await controller.clear();
      expect(controller.hasSession, isFalse);
      expect(await store.readSession(), isNull);
      expect(await store.readOrCreateDeviceId(), originalDeviceId);
    });
  });

  group('refresh', () {
    test('throws SessionRefreshFailure when no session is loaded', () async {
      final controller = SessionController(
        store: store,
        refresher: _FakeRefresher(),
      );
      await controller.bootstrap();
      await expectLater(
        controller.refresh(),
        throwsA(isA<SessionRefreshFailure>()),
      );
    });

    test('persists refreshed tokens on success', () async {
      final refresher = _FakeRefresher();
      final controller = SessionController(store: store, refresher: refresher);
      await controller.bootstrap();
      final original = buildSession(access: 'acc-old', refresh: 'rfr-old');
      await controller.setSession(original);

      refresher.next = original.copyWith(
        accessToken: 'acc-new',
        refreshToken: 'rfr-new',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      final refreshed = await controller.refresh();
      expect(refreshed.accessToken, 'acc-new');
      expect(refreshed.refreshToken, 'rfr-new');
      expect(controller.currentAccessToken, 'acc-new');
      expect((await store.readSession())!.accessToken, 'acc-new');
    });

    test('single-flight: concurrent callers share one network call', () async {
      final refresher = _FakeRefresher();
      final controller = SessionController(store: store, refresher: refresher);
      await controller.bootstrap();
      final original = buildSession();
      await controller.setSession(original);
      refresher.next = original.copyWith(accessToken: 'acc-fresh');

      // Three concurrent refresh requests.
      final results = await Future.wait([
        controller.refresh(),
        controller.refresh(),
        controller.refresh(),
      ]);
      expect(refresher.callCount, 1);
      for (final r in results) {
        expect(r.accessToken, 'acc-fresh');
      }
    });

    test('after a failed refresh, a subsequent refresh tries again', () async {
      final refresher = _FakeRefresher();
      final controller = SessionController(store: store, refresher: refresher);
      await controller.bootstrap();
      await controller.setSession(buildSession());

      refresher.failNext = true;
      await expectLater(
        controller.refresh(),
        throwsA(isA<SessionRefreshFailure>()),
      );

      // Second attempt — refresher now succeeds.
      refresher.next = buildSession(access: 'acc-recovered');
      final ok = await controller.refresh();
      expect(ok.accessToken, 'acc-recovered');
      expect(refresher.callCount, 2);
    });
  });
}

class _FakeRefresher implements SessionRefresher {
  AuthSession? next;
  bool failNext = false;
  int callCount = 0;

  @override
  Future<AuthSession> refresh(AuthSession current) async {
    callCount++;
    // Yield so all concurrent callers enter `refresh` before this completes.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failNext) {
      failNext = false;
      throw StateError('boom');
    }
    final fresh = next ?? current;
    return fresh;
  }
}
