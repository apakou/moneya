import 'package:dio/dio.dart';

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

  /// Parses an `AuthRefreshResponse`. The server returns the rotated tokens
  /// plus an expiry; the rest of the session (userId, phone, kycTier) is
  /// preserved from [fallback] because `/v1/auth/refresh` does not echo
  /// profile fields.
  static AuthSession _parse(
    Map<String, Object?> data, {
    required AuthSession fallback,
  }) {
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    final expiresAtRaw = data['expires_at'] as String?;
    if (accessToken == null || refreshToken == null || expiresAtRaw == null) {
      throw const FormatException('refresh response missing required fields');
    }
    return fallback.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.parse(expiresAtRaw),
    );
  }
}
