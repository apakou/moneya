import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import 'wallet_dtos.dart';

/// `GET /v1/wallet` and `GET /v1/transfers`.
class WalletRepository {
  WalletRepository() : _client = null;

  @visibleForTesting
  WalletRepository.test(ApiClient client) : _client = client;

  final ApiClient? _client;
  ApiClient get _api => _client ?? Get.find<ApiClient>();

  Future<ApiResult<WalletInfo>> getWallet() =>
      _api.request<WalletInfo>('/v1/wallet', decode: (b) => WalletInfo.fromJson(_map(b)));

  Future<ApiResult<TransfersPage>> listTransfers({int limit = 20, String? cursor, String? kind}) {
    return _api.request<TransfersPage>(
      '/v1/transfers',
      queryParameters: {
        'limit': limit,
        'cursor': ?cursor,
        'kind': ?kind,
      },
      decode: (b) => TransfersPage.fromJson(_map(b)),
    );
  }

  static Map<String, Object?> _map(Object? body) {
    if (body is! Map) throw FormatException('Expected a JSON object, got ${body.runtimeType}');
    return body.cast<String, Object?>();
  }
}
