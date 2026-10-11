import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/network/interceptors/auth_interceptor.dart';
import 'auth_dtos.dart';

/// Repository over `/v1/auth/otp`, `/v1/auth/otp/verify` and `/v1/auth/passcode`
/// (refresh and step-up live in `DioSessionRefresher` / `StepUpController`).
///
/// OTP calls set `skipAuth` so a stale bearer from a previous login is never
/// sent. Errors are `ApiError`s with the server's stable `code`
/// (`OTP_INVALID`, `OTP_LOCKED`, `RATE_LIMITED`, `PASSCODE_TOO_WEAK`, ...).
class AuthRepository {
  AuthRepository() : _client = null;

  @visibleForTesting
  AuthRepository.test(ApiClient client) : _client = client;

  final ApiClient? _client;
  ApiClient get _api => _client ?? Get.find<ApiClient>();

  static final Options _noAuth =
      Options(extra: {AuthInterceptor.skipAuthKey: true});

  /// `POST /v1/auth/otp` → 202. [phoneE164] is `+` and digits only.
  Future<ApiResult<OtpRequested>> requestOtp({
    required String phoneE164,
    required String deviceId,
    String? deviceKind,
    String? deviceName,
  }) {
    return _api.request<OtpRequested>(
      '/v1/auth/otp',
      method: 'POST',
      data: <String, Object?>{
        'phone': phoneE164,
        'device_id': deviceId,
        'device_kind': ?deviceKind,
        'device_name': ?deviceName,
      },
      options: _noAuth,
      decode: (b) => OtpRequested.fromJson(_map(b, '/v1/auth/otp')),
    );
  }

  /// `POST /v1/auth/otp/verify` → 200 `AuthTokens`.
  Future<ApiResult<LoginResult>> verifyOtp({
    required String phoneE164,
    required String code,
    required String deviceId,
  }) {
    return _api.request<LoginResult>(
      '/v1/auth/otp/verify',
      method: 'POST',
      data: <String, Object?>{
        'phone': phoneE164,
        'code': code,
        'device_id': deviceId,
      },
      options: _noAuth,
      decode: (b) => LoginResult.fromJson(_map(b, '/v1/auth/otp/verify')),
    );
  }

  /// `POST /v1/auth/passcode` → 204. Needs the session set by [verifyOtp].
  /// [currentPasscode] is required when changing an existing passcode.
  Future<ApiResult<void>> setPasscode({
    required String passcode,
    String? currentPasscode,
  }) {
    return _api.request<void>(
      '/v1/auth/passcode',
      method: 'POST',
      data: <String, Object?>{
        'passcode': passcode,
        'current_passcode': ?currentPasscode,
      },
      decode: (_) {},
    );
  }

  static Map<String, Object?> _map(Object? body, String path) {
    if (body is! Map) {
      throw FormatException('Expected a JSON object from $path, got ${body.runtimeType}');
    }
    return body.cast<String, Object?>();
  }
}
