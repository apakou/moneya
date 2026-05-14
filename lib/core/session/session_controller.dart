import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../logging/app_logger.dart';
import '../logging/pii.dart';
import 'auth_session.dart';
import 'session_store.dart';

/// Single-source-of-truth for the authenticated user's session.
///
/// Registered as a `GetxService` via `Get.putAsync(() => SessionController().bootstrap())`
/// in `main.dart` so it is alive before any screen builds.
///
/// **What this owns:**
/// - The current [AuthSession] (nullable).
/// - The persistent `deviceId` (always non-null after bootstrap).
/// - The refresh mutex (single-flight via [Completer]).
///
/// **What this does NOT own:**
/// - Network calls. [refresher] is injected so the network layer can supply
///   a bare Dio instance without provoking a circular dependency through
///   `AuthInterceptor`.
/// - UI routing. Callers (e.g., `AuthInterceptor`) react to [authState]
///   transitions; routing decisions belong upstream.
class SessionController extends GetxService {
  SessionController({
    required SessionStore store,
    required SessionRefresher refresher,
  })  : _store = store,
        _refresher = refresher;

  final SessionStore _store;
  final SessionRefresher _refresher;

  /// Reactive session. Listen via `Get.find<SessionController>().sessionRx`
  /// or use [hasSession] / [currentAccessToken] for one-shot reads.
  final Rxn<AuthSession> sessionRx = Rxn<AuthSession>();

  String _deviceId = '';
  String get deviceId => _deviceId;

  bool get hasSession => sessionRx.value != null;
  String? get currentAccessToken => sessionRx.value?.accessToken;
  String? get currentRefreshToken => sessionRx.value?.refreshToken;
  String? get currentUserId => sessionRx.value?.userId;
  KycTier? get currentKycTier => sessionRx.value?.kycTier;

  Completer<AuthSession>? _refreshInFlight;

  /// Load any persisted session and device id. Safe to call exactly once;
  /// subsequent calls are no-ops. Always returns `this` so the
  /// `Get.putAsync` idiom works:
  ///
  /// ```dart
  /// await Get.putAsync<SessionController>(() async {
  ///   final c = SessionController(store: ..., refresher: ...);
  ///   return c.bootstrap();
  /// });
  /// ```
  Future<SessionController> bootstrap() async {
    _deviceId = await _store.readOrCreateDeviceId();
    final loaded = await _store.readSession();
    if (loaded == null) {
      AppLogger.i('session.bootstrap.empty', {'device_id': _deviceId});
      return this;
    }
    sessionRx.value = loaded;
    AppLogger.i('session.bootstrap.loaded', {
      'user_id': loaded.userId,
      'phone': maskPhone(loaded.phone),
      'kyc_tier': loaded.kycTier.wire,
      'expires_at': loaded.expiresAt.toIso8601String(),
    });
    return this;
  }

  /// Replace the current session and persist it. Use after `verifyOtp`
  /// success or any other login path.
  Future<void> setSession(AuthSession session) async {
    await _store.writeSession(session);
    sessionRx.value = session;
    AppLogger.i('session.set', {
      'user_id': session.userId,
      'phone': maskPhone(session.phone),
      'kyc_tier': session.kycTier.wire,
    });
  }

  /// Clear the session (logout). Does NOT wipe [deviceId] — see
  /// [SessionStore.readOrCreateDeviceId] for rationale.
  Future<void> clear() async {
    await _store.clearSession();
    sessionRx.value = null;
    AppLogger.i('session.cleared');
  }

  /// Refresh the access token. Single-flight: concurrent callers receive the
  /// same in-flight future.
  ///
  /// Returns the new session on success. Throws [SessionRefreshFailure] on
  /// failure (caller — `AuthInterceptor` — should treat this as a forced
  /// logout: call [clear] and surface AuthError upstream).
  Future<AuthSession> refresh() {
    final inflight = _refreshInFlight;
    if (inflight != null) return inflight.future;

    final completer = Completer<AuthSession>();
    _refreshInFlight = completer;

    _doRefresh().then((session) {
      _refreshInFlight = null;
      completer.complete(session);
    }, onError: (Object e, StackTrace s) {
      _refreshInFlight = null;
      completer.completeError(e, s);
    });

    return completer.future;
  }

  Future<AuthSession> _doRefresh() async {
    final current = sessionRx.value;
    if (current == null) {
      AppLogger.w('session.refresh.no_session');
      throw const SessionRefreshFailure(reason: 'no_session');
    }
    try {
      final fresh = await _refresher.refresh(current);
      await _store.writeSession(fresh);
      sessionRx.value = fresh;
      AppLogger.i('session.refresh.ok', {
        'user_id': fresh.userId,
        'expires_at': fresh.expiresAt.toIso8601String(),
      });
      return fresh;
    } catch (e, s) {
      AppLogger.w('session.refresh.failed', {'reason': e.runtimeType.toString()}, e, s);
      throw SessionRefreshFailure(reason: e.toString(), cause: e);
    }
  }

  /// Test seam: replace the in-memory session without touching storage.
  @visibleForTesting
  void debugSetSession(AuthSession? value) => sessionRx.value = value;
}

/// Injected at construction so [SessionController] does not depend on
/// the network layer directly. The implementation in
/// `lib/core/network/dio_session_refresher.dart` uses a bare Dio without
/// interceptors to avoid recursing through [AuthInterceptor].
abstract class SessionRefresher {
  Future<AuthSession> refresh(AuthSession current);
}

class SessionRefreshFailure implements Exception {
  const SessionRefreshFailure({required this.reason, this.cause});
  final String reason;
  final Object? cause;

  @override
  String toString() => 'SessionRefreshFailure(reason=$reason)';
}
