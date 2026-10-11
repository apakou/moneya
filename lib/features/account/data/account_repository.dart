import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import 'account_dtos.dart';

/// Read-side account API: balance (`/v1/wallet`) and history
/// (`/v1/transactions`).
class AccountRepository {
  AccountRepository() : _client = null;

  @visibleForTesting
  AccountRepository.test(ApiClient client) : _client = client;

  final ApiClient? _client;
  ApiClient get _api => _client ?? Get.find<ApiClient>();

  /// Balance in [currency] (wire code); the server's home currency when null.
  Future<ApiResult<WalletBalance>> wallet({String? currency}) {
    return _api.request<WalletBalance>(
      '/v1/wallet',
      queryParameters: {'currency': ?currency},
      decode: (b) => WalletBalance.fromJson(_map(b)),
    );
  }

  Future<ApiResult<TransactionPage>> transactions({
    int limit = 20,
    String? cursor,
  }) {
    return _api.request<TransactionPage>(
      '/v1/transactions',
      queryParameters: {'limit': '$limit', 'cursor': ?cursor},
      decode: (b) => TransactionPage.fromJson(_map(b)),
    );
  }

  static Map<String, Object?> _map(Object? body) {
    if (body is! Map) {
      throw FormatException('Expected a JSON object, got ${body.runtimeType}');
    }
    return body.cast<String, Object?>();
  }
}
