import 'package:dio/dio.dart';

import '../../logging/app_logger.dart';
import '../../logging/pii.dart';

/// Request/response logger with PII redaction.
///
/// - In debug builds, logs method, path, status, latency, and a redacted
///   view of headers + body.
/// - In release/profile, logs nothing on success. Errors are forwarded to
///   `AppLogger.w/e` which goes through the crash reporter.
///
/// Sits at the TOP of the interceptor chain so it sees the original payload
/// without `Idempotency-Key` / `traceparent` / `Authorization` munging from
/// downstream interceptors (those are added later in the chain → see
/// ApiClient.addInterceptors).
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor();

  static const String _stopwatchKey = '_loggingStopwatchStart';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_stopwatchKey] = DateTime.now();
    AppLogger.d('http.request', {
      'method': options.method,
      'path': options.path,
      'headers': redactHeaders(options.headers),
      'query': redactMap(Map<String, Object?>.from(options.queryParameters)),
      'body': _redactBody(options.data),
    });
    handler.next(options);
  }

  @override
  void onResponse(Response<Object?> response, ResponseInterceptorHandler handler) {
    final start = response.requestOptions.extra[_stopwatchKey];
    final latencyMs = start is DateTime
        ? DateTime.now().difference(start).inMilliseconds
        : null;
    AppLogger.d('http.response', {
      'method': response.requestOptions.method,
      'path': response.requestOptions.path,
      'status': response.statusCode,
      'latency_ms': ?latencyMs,
    });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final start = err.requestOptions.extra[_stopwatchKey];
    final latencyMs = start is DateTime
        ? DateTime.now().difference(start).inMilliseconds
        : null;
    AppLogger.w('http.error', {
      'method': err.requestOptions.method,
      'path': err.requestOptions.path,
      'status': err.response?.statusCode,
      'type': err.type.name,
      'latency_ms': ?latencyMs,
    });
    handler.next(err);
  }

  Object? _redactBody(Object? body) {
    if (body == null) return null;
    if (body is Map<String, Object?>) return redactMap(body);
    if (body is List) {
      return body
          .map((e) => e is Map<String, Object?> ? redactMap(e) : e)
          .toList(growable: false);
    }
    if (body is String) {
      // Don't try to parse — could be multipart or already a redacted blob.
      return body.length > 200 ? '${body.substring(0, 200)}…' : body;
    }
    return body.runtimeType.toString();
  }
}
