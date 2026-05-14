import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// Attaches `Idempotency-Key: <uuid v4>` to requests that opt in via
/// `Options.extra['idempotent'] == true`.
///
/// Two modes:
/// - **Auto-mint** (`extra['idempotent'] == true`): a fresh UUIDv4 is
///   generated per request. Suitable for one-shot calls where the caller
///   does not retry on network errors.
/// - **Caller-supplied** (`extra['idempotencyKey'] == '<uuid>'`): the
///   interceptor uses the provided key verbatim. Use this when the caller
///   may retry the same logical operation after a network failure — the
///   stable key lets the server collapse retries into one.
class IdempotencyInterceptor extends Interceptor {
  IdempotencyInterceptor({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  static const String idempotentFlag = 'idempotent';
  static const String idempotencyKeyExtra = 'idempotencyKey';
  static const String headerName = 'Idempotency-Key';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final supplied = options.extra[idempotencyKeyExtra];
    if (supplied is String && supplied.isNotEmpty) {
      options.headers[headerName] = supplied;
    } else if (options.extra[idempotentFlag] == true) {
      options.headers[headerName] = _uuid.v4();
    }
    handler.next(options);
  }
}
