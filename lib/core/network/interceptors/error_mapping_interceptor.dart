import 'package:dio/dio.dart';

import '../api_error.dart';

/// Converts every `DioException` into an [ApiError] subtype and rejects with
/// that error attached as `DioException.error`. Sits LAST in the chain so
/// every other interceptor (logging, auth-retry, etc.) has already run.
///
/// Mapping strategy (per backend Q1 being unresolved): branch primarily on
/// HTTP status code; preserve the server-supplied `code` string verbatim
/// when present, so call sites can switch on stable codes once they're
/// published. RFC 7807 `application/problem+json` envelopes are parsed
/// best-effort.
///
/// Callers never see raw `DioException`. After this interceptor every
/// rejection carries `error` of type [ApiError]; `ApiClient.request<T>`
/// unwraps it into `ApiResult<T>`.
class ErrorMappingInterceptor extends Interceptor {
  ErrorMappingInterceptor();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // If a previous interceptor (AuthInterceptor) already attached an
    // ApiError, just re-reject with the same error preserved.
    if (err.error is ApiError) {
      handler.next(err);
      return;
    }

    final mapped = _map(err);
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: mapped,
        stackTrace: err.stackTrace,
        message: mapped.title,
      ),
    );
  }

  ApiError _map(DioException err) {
    final response = err.response;

    // Transport-level: no response.
    if (response == null) {
      switch (err.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return NetworkError(
            code: 'TIMEOUT',
            title: 'Request timed out',
            cause: err,
          );
        case DioExceptionType.badCertificate:
          return NetworkError(
            code: 'TLS_ERROR',
            title: 'Secure connection failed',
            cause: err,
          );
        case DioExceptionType.cancel:
          return NetworkError(
            code: 'CANCELLED',
            title: 'Request cancelled',
            cause: err,
          );
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
        case DioExceptionType.badResponse:
          return NetworkError(
            detail: err.message,
            cause: err,
          );
      }
    }

    final status = response.statusCode ?? 0;
    final problem = _parseProblem(response.data);
    final code = problem.code ?? _defaultCodeForStatus(status);
    final title = problem.title ?? _defaultTitleForStatus(status);
    final detail = problem.detail;
    final traceId = problem.traceId ??
        response.headers.value('x-trace-id') ??
        response.headers.value('traceparent');
    final retryAfter = _parseRetryAfter(response.headers.value('retry-after'));

    switch (status) {
      case 400:
      case 422:
        return ValidationError(
          code: code,
          title: title,
          detail: detail,
          statusCode: status,
          traceId: traceId,
          fieldErrors: problem.fieldErrors,
          cause: err,
        );
      case 401:
      case 423:
        return AuthError(
          code: code,
          title: title,
          detail: detail,
          statusCode: status,
          traceId: traceId,
          cause: err,
        );
      case 402:
      case 403:
        return PaymentError(
          code: code,
          title: title,
          detail: detail,
          statusCode: status,
          traceId: traceId,
          cause: err,
        );
      case 409:
      case 410:
        return ConflictError(
          code: code,
          title: title,
          detail: detail,
          statusCode: status,
          traceId: traceId,
          cause: err,
        );
      case 429:
        return RateLimitError(
          code: code,
          title: title,
          detail: detail,
          traceId: traceId,
          retryAfter: retryAfter,
          cause: err,
        );
      default:
        if (status >= 500 && status < 600) {
          return ServerError(
            code: code,
            title: title,
            detail: detail,
            statusCode: status,
            traceId: traceId,
            cause: err,
          );
        }
        return UnknownError(
          code: code,
          title: title,
          detail: detail,
          statusCode: status,
          traceId: traceId,
          cause: err,
        );
    }
  }

  static String _defaultCodeForStatus(int status) {
    switch (status) {
      case 400:
        return 'BAD_REQUEST';
      case 401:
        return 'UNAUTHENTICATED';
      case 402:
        return 'PAYMENT_REQUIRED';
      case 403:
        return 'FORBIDDEN';
      case 404:
        return 'NOT_FOUND';
      case 409:
        return 'CONFLICT';
      case 410:
        return 'GONE';
      case 422:
        return 'VALIDATION_FAILED';
      case 423:
        return 'LOCKED';
      case 429:
        return 'RATE_LIMITED';
      default:
        if (status >= 500) return 'SERVER_ERROR';
        return 'HTTP_$status';
    }
  }

  static String _defaultTitleForStatus(int status) {
    if (status >= 500) return 'Server error';
    if (status == 429) return 'Too many requests';
    if (status == 401 || status == 423) return 'Authentication required';
    if (status == 402 || status == 403) return 'Not allowed';
    if (status == 404) return 'Not found';
    if (status == 409 || status == 410) return 'Conflict';
    if (status == 400 || status == 422) return 'Invalid request';
    return 'Request failed';
  }

  static Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) return Duration(seconds: seconds);
    // HTTP-date form is rare from our backend; ignore for now.
    return null;
  }

  static _Problem _parseProblem(Object? body) {
    if (body is! Map) return const _Problem();
    final map = body.cast<String, Object?>();
    final fieldsRaw = map['errors'];
    final fieldErrors = <String, String>{};
    if (fieldsRaw is Map) {
      fieldsRaw.forEach((k, v) {
        if (v is String) fieldErrors[k.toString()] = v;
      });
    }
    return _Problem(
      code: map['code'] as String?,
      title: map['title'] as String?,
      detail: map['detail'] as String?,
      traceId: map['trace_id'] as String?,
      fieldErrors: fieldErrors,
    );
  }
}

class _Problem {
  const _Problem({
    this.code,
    this.title,
    this.detail,
    this.traceId,
    this.fieldErrors = const {},
  });
  final String? code;
  final String? title;
  final String? detail;
  final String? traceId;
  final Map<String, String> fieldErrors;
}
