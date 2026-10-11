import 'package:dio/dio.dart';

import '../../session/session_controller.dart';
import '../api_error.dart';

/// Attaches `Authorization: Bearer <accessToken>` and `X-Txn-Token`, and
/// handles 401-driven token refresh via single-flight through
/// [SessionController.refresh].
///
/// Token sourcing:
/// - `Authorization` — `SessionController.currentAccessToken`. Omitted if
///   the request sets `options.extra['skipAuth'] == true` (used by the
///   refresh call itself).
/// - `X-Txn-Token` — `options.extra['txnToken']` if set. Step-up token
///   acquisition is the caller's responsibility (see `StepUpController`);
///   this interceptor only attaches it.
///
/// Refresh flow on 401:
/// 1. If the failing request set `skipAuth` or already retried, surface as
///    [AuthError] via the chain.
/// 2. Otherwise call `SessionController.refresh()`. On success, retry the
///    original request once with the new access token. On failure, surface
///    [AuthError].
///
/// The retry is *exactly one*. Subsequent 401s on the same request bubble
/// up as `AuthError` and the caller is expected to route to AuthLanding.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._session, {Dio? retryClient}) : _retryClient = retryClient;

  final SessionController _session;
  final Dio? _retryClient;

  static const String _retriedKey = '_authInterceptorRetried';
  static const String skipAuthKey = 'skipAuth';
  static const String txnTokenKey = 'txnToken';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[skipAuthKey] != true) {
      final token = _session.currentAccessToken;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    final txn = options.extra[txnTokenKey];
    if (txn is String && txn.isNotEmpty) {
      options.headers['X-Txn-Token'] = txn;
    }
    handler.next(options);
  }

  /// Server `code`s on a 401 that mean "your bearer token is bad" (refresh and
  /// retry). Any OTHER 401 code (`PASSCODE_INVALID`, `OTP_INVALID`,
  /// `STEP_UP_REQUIRED`, ...) is a credential check that failed on purpose:
  /// refreshing and retrying would re-submit the wrong passcode and burn a
  /// second attempt against the server-side lockout.
  static const Set<String> _tokenProblemCodes = {
    'UNAUTHORIZED',
    'UNAUTHENTICATED',
  };

  static bool _isTokenProblem(Object? body) {
    if (body is Map) {
      final code = body['code'];
      return code == null || (code is String && _tokenProblemCodes.contains(code));
    }
    return true; // no structured body → assume the token
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final status = response?.statusCode;
    final options = err.requestOptions;

    final canRetry = status == 401 &&
        _isTokenProblem(response?.data) &&
        options.extra[skipAuthKey] != true &&
        options.extra[_retriedKey] != true &&
        _session.hasSession;

    if (!canRetry) {
      handler.next(err);
      return;
    }

    try {
      final fresh = await _session.refresh();
      options.extra[_retriedKey] = true;
      options.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
      final client = _retryClient ?? Dio(BaseOptions(baseUrl: options.baseUrl));
      final retryResponse = await client.fetch<Object?>(options);
      handler.resolve(retryResponse);
    } on SessionRefreshFailure catch (e) {
      // Force-logout path. Surface as AuthError so the caller can react.
      handler.reject(
        DioException(
          requestOptions: options,
          response: response,
          type: DioExceptionType.unknown,
          error: AuthError(
            code: 'AUTH_REFRESH_FAILED',
            title: 'Session expired',
            statusCode: 401,
            cause: e,
          ),
        ),
      );
    } catch (e) {
      handler.next(err);
    }
  }
}
