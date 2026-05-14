import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;

import '../config/env.dart';
import '../session/session_controller.dart';
import 'api_error.dart';
import 'api_result.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_mapping_interceptor.dart';
import 'interceptors/idempotency_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/trace_interceptor.dart';

/// Application-wide HTTP client.
///
/// Wraps a single Dio instance with the canonical interceptor chain and
/// exposes [request] / [requestRaw] helpers that return [ApiResult<T>] —
/// callers never see `DioException`.
///
/// **Interceptor order** (matches `client-integration-notes.md` §6):
/// `LoggingInterceptor → AuthInterceptor → IdempotencyInterceptor →
/// TraceInterceptor → ErrorMappingInterceptor`.
///
/// Logging is first so it sees the original payload before downstream
/// interceptors add `Authorization`, `X-Txn-Token`, `Idempotency-Key`, and
/// `traceparent`. Error mapping is last so every other interceptor's
/// `onError` runs first.
///
/// Registered as a `GetxService` in `main.dart`:
/// ```dart
/// Get.put<ApiClient>(ApiClient.build(...), permanent: true);
/// ```
class ApiClient extends GetxService {
  ApiClient._(this._dio);

  final Dio _dio;
  Dio get dio => _dio;

  /// Factory used by `main.dart`. The bare `retryClient` passed to
  /// `AuthInterceptor` is a SECOND Dio without interceptors — it is used to
  /// re-fire the original request after a successful refresh, bypassing
  /// `AuthInterceptor` itself.
  factory ApiClient.build({
    required SessionController session,
    required String appVersion,
    required String Function() localeProvider,
    String? baseUrlOverride,
  }) {
    final baseUrl = baseUrlOverride ?? Env.apiBaseUrl;
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
      responseType: ResponseType.json,
      // We never want Dio to throw on non-2xx — the
      // ErrorMappingInterceptor needs to inspect the response. But we
      // keep the default behaviour because DioException is what drives
      // the onError chain; we just map it before the caller sees it.
    ));

    final retryClient = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    ));

    dio.interceptors.addAll([
      LoggingInterceptor(),
      AuthInterceptor(session, retryClient: retryClient),
      IdempotencyInterceptor(),
      TraceInterceptor(
        deviceIdProvider: () => session.deviceId,
        appVersion: appVersion,
        localeProvider: localeProvider,
      ),
      ErrorMappingInterceptor(),
    ]);

    return ApiClient._(dio);
  }

  /// JSON-decoded request. `T` is the decoded response type. Pass `null`
  /// for `T` if you want raw access — use [requestRaw] instead.
  Future<ApiResult<T>> request<T>(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
    T Function(Object? json)? decode,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method),
      );
      final body = response.data;
      final value = decode != null ? decode(body) : body as T;
      return Success<T>(value);
    } on DioException catch (e) {
      final err = e.error;
      if (err is ApiError) return Failure<T>(err);
      // Defence in depth — should not happen because
      // ErrorMappingInterceptor always attaches an ApiError.
      return Failure<T>(UnknownError(cause: e, detail: e.message));
    }
  }

  /// Raw response variant for callers that need headers / status.
  Future<ApiResult<Response<Object?>>> requestRaw(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method),
      );
      return Success(response);
    } on DioException catch (e) {
      final err = e.error;
      if (err is ApiError) return Failure(err);
      return Failure(UnknownError(cause: e, detail: e.message));
    }
  }
}
