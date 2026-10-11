import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/network/interceptors/auth_interceptor.dart';
import '../../../core/network/interceptors/idempotency_interceptor.dart';
import 'ramp_dtos.dart';

/// Top-up (`/v1/onramp/*`) and cash-out (`/v1/offramp/*`).
///
/// Order creation needs BOTH headers: the single-use `X-Txn-Token` from step-up
/// and an `Idempotency-Key`. The key is minted by the caller once per logical
/// attempt and REUSED on retries, so a lost response replays the stored result
/// instead of creating a second order (`client-integration-notes.md` §6).
class RampRepository {
  RampRepository() : _client = null;

  @visibleForTesting
  RampRepository.test(ApiClient client) : _client = client;

  final ApiClient? _client;
  ApiClient get _api => _client ?? Get.find<ApiClient>();

  Future<ApiResult<RampQuote>> quoteOnramp({required String currency, required String amount}) {
    return _api.request<RampQuote>(
      '/v1/onramp/quote',
      method: 'POST',
      data: {'fiat_currency': currency, 'fiat_amount': amount},
      decode: (b) => RampQuote.fromJson(_map(b)),
    );
  }

  Future<ApiResult<RampQuote>> quoteOfframp({
    required String amount,
    required String currency,
    required String payoutCurrency,
  }) {
    return _api.request<RampQuote>(
      '/v1/offramp/quote',
      method: 'POST',
      data: {'amount': amount, 'currency': currency, 'payout_currency': payoutCurrency},
      decode: (b) => RampQuote.fromJson(_map(b)),
    );
  }

  Future<ApiResult<RampOrder>> createOnramp({
    required String quoteId,
    required String paymentMethod,
    required String payerMsisdn,
    required String txnToken,
    required String idempotencyKey,
  }) {
    return _api.request<RampOrder>(
      '/v1/onramp/orders',
      method: 'POST',
      data: {'quote_id': quoteId, 'payment_method': paymentMethod, 'payer_msisdn': payerMsisdn},
      options: _orderOptions(txnToken, idempotencyKey),
      decode: (b) => RampOrder.fromJson(_map(b), RampDirection.onramp),
    );
  }

  Future<ApiResult<RampOrder>> createOfframp({
    required String quoteId,
    required String payoutMethod,
    required String payeeMsisdn,
    String? payeeName,
    required String txnToken,
    required String idempotencyKey,
  }) {
    return _api.request<RampOrder>(
      '/v1/offramp/orders',
      method: 'POST',
      data: {
        'quote_id': quoteId,
        'payout_method': payoutMethod,
        'payee_msisdn': payeeMsisdn,
        'payee_name': ?payeeName,
      },
      options: _orderOptions(txnToken, idempotencyKey),
      decode: (b) => RampOrder.fromJson(_map(b), RampDirection.offramp),
    );
  }

  Future<ApiResult<RampOrder>> getOrder(RampDirection direction, String id) {
    final path = direction == RampDirection.onramp ? '/v1/onramp/orders/$id' : '/v1/offramp/orders/$id';
    return _api.request<RampOrder>(path, decode: (b) => RampOrder.fromJson(_map(b), direction));
  }

  static Options _orderOptions(String txnToken, String idempotencyKey) => Options(extra: {
        IdempotencyInterceptor.idempotencyKeyExtra: idempotencyKey,
        AuthInterceptor.txnTokenKey: txnToken,
      });

  static Map<String, Object?> _map(Object? body) {
    if (body is! Map) throw FormatException('Expected a JSON object, got ${body.runtimeType}');
    return body.cast<String, Object?>();
  }
}
