import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/network/interceptors/auth_interceptor.dart';
import '../../../core/network/interceptors/idempotency_interceptor.dart';
import 'transfer_dtos.dart';

/// Thin repository over `POST /v1/transfers`.
///
/// ## Scope
///
/// Only the *create* path is implemented in this PR. `getTransfer`,
/// `listTransfers`, and `cancelTransfer` will land alongside the
/// transactions screen and the cancel-claim UX. The shape of those
/// endpoints is locked in `openapi.yaml` lines 647–781 and uses the
/// same DTOs declared in `transfer_dtos.dart`.
///
/// ## Idempotency & step-up
///
/// `createTransfer` does NOT mint its own idempotency key — the
/// caller (`PaymentConfirmScreen`) mints the UUIDv4 once in
/// `initState` and re-uses it across retries so the server can
/// dedupe a double-swipe or a "Try again" tap on the failed screen.
/// We pass it via [IdempotencyInterceptor.idempotencyKeyExtra] so
/// the interceptor writes the `Idempotency-Key` header.
///
/// The step-up `X-Txn-Token` is the one minted by
/// `StepUpController.fresh()` immediately before the call. It's
/// passed via [AuthInterceptor.txnTokenKey]; `AuthInterceptor` reads
/// `Options.extra[txnToken]` and writes the header. Both must be
/// present — server rejects with `400` otherwise (the OpenAPI marks
/// both as `required` on `createTransfer`).
///
/// ## DI
///
/// Default constructor reads `Get.find<ApiClient>()` so production
/// callers stay one-liners (`TransferRepository().createTransfer(...)`).
/// Tests inject an `ApiClient` directly via [TransferRepository.test]
/// to swap the underlying Dio's adapter with a scripted mock — see
/// `test/features/transfer/data/transfer_repository_test.dart`.
class TransferRepository {
  /// Production constructor. Resolves `ApiClient` lazily from the
  /// service locator the first time a method is called, so unit
  /// tests of *callers* don't have to register a real `ApiClient`
  /// unless they exercise the network path.
  TransferRepository() : _client = null;

  /// Test seam — pass an `ApiClient` whose `dio.httpClientAdapter`
  /// has been swapped with a scripted adapter.
  @visibleForTesting
  TransferRepository.test(ApiClient client) : _client = client;

  final ApiClient? _client;

  ApiClient get _api => _client ?? Get.find<ApiClient>();

  /// Submit a new P2P transfer.
  ///
  /// Returns:
  /// - `Success(Transfer)` for `202 Accepted` (the only success code
  ///   in the OpenAPI for this endpoint). The `Transfer.status` will
  ///   be one of `PROCESSING` / `COMPLETED` / `AWAITING_CLAIM` /
  ///   `FAILED` — callers branch on it to choose the terminal
  ///   screen.
  /// - `Failure(ApiError)` for any non-2xx:
  ///   - `400` / `422` → `ValidationError`
  ///   - `401` / `423` → `AuthError` (auth-interceptor will already
  ///     have attempted a refresh + retry; if it surfaces here the
  ///     session is unrecoverable on this device)
  ///   - `402` insufficient funds, `403` compliance blocked →
  ///     `PaymentError`
  ///   - `422` per OpenAPI is "daily/velocity limit exceeded"; we
  ///     keep the `ValidationError` mapping because the wire-level
  ///     status code is the same; the server `code` distinguishes.
  ///   - `429` → `RateLimitError`
  ///   - `5xx` → `ServerError`
  ///   - transport failures → `NetworkError`
  Future<ApiResult<Transfer>> createTransfer({
    required TransferRequest request,
    required String txnToken,
    required String idempotencyKey,
  }) {
    return _api.request<Transfer>(
      '/v1/transfers',
      method: 'POST',
      data: request.toJson(),
      options: Options(extra: {
        IdempotencyInterceptor.idempotencyKeyExtra: idempotencyKey,
        AuthInterceptor.txnTokenKey: txnToken,
      }),
      decode: (body) {
        if (body is! Map) {
          // Defence in depth — Envelope/Logging shouldn't reshape,
          // but if they ever do, fail loudly so we notice in tests
          // before users see "Unexpected error" snackbars.
          throw FormatException(
            'Expected Map for /v1/transfers response, got ${body.runtimeType}',
          );
        }
        return Transfer.fromJson(body.cast<String, Object?>());
      },
    );
  }
}

