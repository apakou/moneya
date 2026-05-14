/// Strongly-typed error hierarchy returned by the network layer.
///
/// `ErrorMappingInterceptor` converts every `DioException` and every
/// `application/problem+json` response into one of these subtypes. Callers
/// (repositories, controllers) handle them via switch / pattern-match, never
/// by inspecting raw `DioException` fields.
///
/// Codes correspond to the stable error-code list in
/// `docs/backend/client-integration-notes.md` §7. Unknown server codes fall
/// through to [UnknownError] but preserve `code` so call sites can still
/// branch on it during development.
sealed class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.title,
    this.detail,
    this.statusCode,
    this.traceId,
    this.retryAfter,
    this.cause,
  });

  final String code;
  final String title;
  final String? detail;
  final int? statusCode;
  final String? traceId;
  final Duration? retryAfter;
  final Object? cause;

  @override
  String toString() {
    final buf = StringBuffer(runtimeType.toString());
    buf.write('(code=$code');
    if (statusCode != null) buf.write(', status=$statusCode');
    if (traceId != null) buf.write(', trace=$traceId');
    buf.write(')');
    return buf.toString();
  }
}

/// Transport-level failure: no HTTP response. DNS, connection refused,
/// timeout, TLS error.
class NetworkError extends ApiError {
  const NetworkError({super.code = 'NETWORK_ERROR', super.title = 'Network error', super.detail, super.cause})
      : super(statusCode: null);
}

/// 401 / 423. The caller's session is no longer valid or the account is
/// locked. `AuthInterceptor` produces this after a failed refresh attempt.
class AuthError extends ApiError {
  const AuthError({
    required super.code,
    required super.title,
    super.detail,
    super.statusCode,
    super.traceId,
    super.retryAfter,
    super.cause,
  });
}

/// 400 / 422. Client-supplied data was rejected.
class ValidationError extends ApiError {
  const ValidationError({
    required super.code,
    required super.title,
    super.detail,
    super.statusCode = 400,
    super.traceId,
    super.cause,
    this.fieldErrors = const {},
  });

  /// Optional per-field error map (server-driven). Empty when the server
  /// didn't include field-level detail.
  final Map<String, String> fieldErrors;
}

/// 409 / 410. Resource state conflicts (quote expired, claim redeemed,
/// transfer not cancellable, idempotency mismatch).
class ConflictError extends ApiError {
  const ConflictError({
    required super.code,
    required super.title,
    super.detail,
    super.statusCode = 409,
    super.traceId,
    super.cause,
  });
}

/// 402 / 403. Money-specific blocks: insufficient funds, compliance, KYC
/// gate, velocity limit.
class PaymentError extends ApiError {
  const PaymentError({
    required super.code,
    required super.title,
    super.detail,
    super.statusCode,
    super.traceId,
    super.cause,
  });
}

/// 429. Carries [retryAfter] when the server set the header.
class RateLimitError extends ApiError {
  const RateLimitError({
    super.code = 'RATE_LIMITED',
    super.title = 'Too many requests',
    super.detail,
    super.traceId,
    super.retryAfter,
    super.cause,
  }) : super(statusCode: 429);
}

/// 5xx. Server problem. Safe to retry with backoff.
class ServerError extends ApiError {
  const ServerError({
    super.code = 'SERVER_ERROR',
    super.title = 'Server error',
    super.detail,
    super.statusCode,
    super.traceId,
    super.cause,
  });
}

/// Catch-all for unmapped responses. If you see this in logs in any
/// frequency, add a dedicated mapping in `ErrorMappingInterceptor`.
class UnknownError extends ApiError {
  const UnknownError({
    super.code = 'UNKNOWN_ERROR',
    super.title = 'Unexpected error',
    super.detail,
    super.statusCode,
    super.traceId,
    super.cause,
  });
}
