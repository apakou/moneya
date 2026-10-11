import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../session/auth_session.dart';
import '../session/session_controller.dart';

/// [SessionRefresher] backed by a bare Dio instance with NO interceptors.
///
/// The bare client is the only way to refresh without recursing through
/// `AuthInterceptor` (which would itself trigger a refresh on 401, ad
/// infinitum). It also bypasses the request-logging interceptor's
/// (already-redacted) body logging — refresh-token payloads should not
/// appear in logs at all.
///
/// Wire from `ApiClient` setup:
/// ```dart
/// final refresher = DioSessionRefresher(baseUrl: Env.apiBaseUrl);
/// final session = SessionController(store: ..., refresher: refresher);
/// ```
class DioSessionRefresher implements SessionRefresher {
  DioSessionRefresher({required String baseUrl, Dio? client})
      : _client = client ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
              contentType: 'application/json',
            ));

  final Dio _client;

  @override
  Future<AuthSession> refresh(AuthSession current) async {
    final response = await _client.post<Map<String, Object?>>(
      '/v1/auth/refresh',
      data: <String, Object?>{'refresh_token': current.refreshToken},
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('refresh endpoint returned empty body');
    }
    return _parse(data, fallback: current);
  }

  /// Parses `AuthTokens` (`openapi.yaml`): `access_token`, `refresh_token`,
  /// `expires_in` (seconds) and the `user`. The server rotates the refresh
  /// token on every call, so BOTH tokens are replaced. Profile fields come
  /// from the echoed `user` when present, else from [fallback].
  static AuthSession _parse(
    Map<String, Object?> data, {
    required AuthSession fallback,
    DateTime? now,
  }) {
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    final expiresIn = data['expires_in'];
    if (accessToken == null || refreshToken == null || expiresIn is! int) {
      throw const FormatException('refresh response missing required fields');
    }
    final user = data['user'];
    var session = fallback.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: (now ?? DateTime.now()).add(Duration(seconds: expiresIn)),
    );
    if (user is Map) {
      session = session.copyWith(
        kycTier: KycTier.fromWire(
          (user['kyc_tier'] as String?) ?? fallback.kycTier.wire,
        ),
        fullName: user['full_name'] as String? ?? fallback.fullName,
        photoUrl: user['photo_url'] as String? ?? fallback.photoUrl,
      );
    }
    return session;
  }

  /// Test seam for the pure parsing step.
  @visibleForTesting
  static AuthSession parseForTest(
    Map<String, Object?> data, {
    required AuthSession fallback,
    DateTime? now,
  }) =>
      _parse(data, fallback: fallback, now: now);
}
