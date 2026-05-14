import 'package:get/get.dart';

import '../logging/app_logger.dart';
import '../network/api_client.dart';
import '../network/api_error.dart';
import '../network/api_result.dart';
import '../network/interceptors/auth_interceptor.dart';

/// Acquires and caches the short-lived `X-Txn-Token` (step-up token) used
/// to authorise high-risk operations (`createTransfer`, `createOnrampOrder`,
/// `createOfframpOrder`, and per the client default also `cancelTransfer`,
/// `createPaymentRequest`, `redeemClaim`).
///
/// Server contract (per `client-integration-notes.md` §5): the token is
/// single-use **per call site** but the same token can be re-presented
/// within its 60-second window if the caller retries. To stay well within
/// that window after acquisition + UX latency, this controller treats any
/// token older than 50 seconds as stale.
///
/// **UI integration** is W2: a passcode bottom sheet will obtain the
/// passcode from the user and pass it to [fresh]. This controller does NOT
/// own the sheet.
///
/// Usage from a transfer flow:
/// ```dart
/// final tokenResult = await Get.find<StepUpController>().fresh(passcode: pin);
/// switch (tokenResult) {
///   case Success(:final value):
///     final result = await transferRepo.create(req, txnToken: value);
///   case Failure(:final error):
///     // Surface error.title to the user.
/// }
/// ```
class StepUpController extends GetxService {
  StepUpController(this._api);

  final ApiClient _api;

  /// Tokens older than this are considered stale and re-acquired
  /// transparently. Server TTL is 60s; we leave a 10s margin for the
  /// caller's confirmation UX.
  static const Duration freshness = Duration(seconds: 50);

  String? _token;
  DateTime? _acquiredAt;

  /// The currently-cached token if it is still fresh, otherwise `null`.
  String? get currentToken {
    final acquiredAt = _acquiredAt;
    final token = _token;
    if (token == null || acquiredAt == null) return null;
    if (DateTime.now().difference(acquiredAt) > freshness) return null;
    return token;
  }

  /// Return a fresh step-up token. Hits `/v1/auth/step-up` with the
  /// supplied [passcode] (plaintext over TLS; server hashes with
  /// Argon2id — see `client-integration-notes.md` §3 / fintech-security
  /// skill). Caches the result for [freshness].
  ///
  /// On 401 / locked the caller is expected to show the lockout state
  /// from the underlying [AuthError] — this controller does not retry.
  Future<ApiResult<String>> fresh({required String passcode}) async {
    final result = await _api.request<Map<String, Object?>>(
      '/v1/auth/step-up',
      method: 'POST',
      data: <String, Object?>{'passcode': passcode},
      decode: (json) => (json as Map).cast<String, Object?>(),
    );
    return switch (result) {
      Success(:final value) => _ingestToken(value),
      Failure(:final error) => Failure<String>(error),
    };
  }

  ApiResult<String> _ingestToken(Map<String, Object?> body) {
    final token = body['txn_token'] as String?;
    if (token == null || token.isEmpty) {
      AppLogger.w('stepup.token.missing');
      return const Failure<String>(UnknownError(
        code: 'STEPUP_TOKEN_MISSING',
        title: 'Step-up token missing',
      ));
    }
    _token = token;
    _acquiredAt = DateTime.now();
    AppLogger.i('stepup.token.acquired', {'len': token.length});
    return Success<String>(token);
  }

  /// Drop the cached token. Call after a successful high-risk operation
  /// to enforce single-use semantics on the client side, even if the
  /// server would have accepted re-presentation within the 60s window.
  void consume() {
    _token = null;
    _acquiredAt = null;
  }

  /// Build an `Options` that carries the current token in
  /// `extra['txnToken']` for `AuthInterceptor` to attach as `X-Txn-Token`.
  /// Returns `null` if no fresh token is cached — the caller must
  /// re-acquire first.
  ///
  /// This is a convenience: the caller can also build the `Options`
  /// manually.
  Map<String, Object?>? extra() {
    final token = currentToken;
    if (token == null) return null;
    return {AuthInterceptor.txnTokenKey: token};
  }
}
