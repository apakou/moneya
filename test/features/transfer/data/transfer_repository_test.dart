import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_client.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';
import 'package:moneya/features/transfer/data/transfer_dtos.dart';
import 'package:moneya/features/transfer/data/transfer_repository.dart';

/// Repository tests use the same `_ScriptedAdapter` pattern as
/// `auth_interceptor_test.dart` / `step_up_controller_test.dart` —
/// build a real `ApiClient` and swap `dio.httpClientAdapter` so the
/// full interceptor chain (Logging → Auth → Idempotency → Trace →
/// ErrorMapping) runs against canned replies. This is the only way to
/// verify the `Idempotency-Key` and `X-Txn-Token` headers actually
/// reach the wire — a mocked `ApiClient` would skip those interceptors.
void main() {
  late _ScriptedAdapter adapter;
  late ApiClient api;
  late TransferRepository repo;

  setUp(() async {
    final store = SessionStore(InMemorySecureStorage());
    final session = SessionController(
      store: store,
      refresher: _NoopRefresher(),
    );
    await session.bootstrap();
    await session.setSession(AuthSession(
      accessToken: 'access-1',
      refreshToken: 'rfr-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      userId: 'user-1',
      phone: '+221770000000',
      countryIso2: 'SN',
      kycTier: KycTier.tier1,
    ));

    api = ApiClient.build(
      session: session,
      appVersion: '1.0.0+1',
      localeProvider: () => 'en',
      baseUrlOverride: 'https://api.test',
    );
    adapter = _ScriptedAdapter();
    api.dio.httpClientAdapter = adapter;

    repo = TransferRepository.test(api);
  });

  TransferRequest buildRequest() => const TransferRequest(
        recipientPhone: '+221770000099',
        amount: '10',
        currency: 'XOF',
        note: 'lunch',
      );

  /// Minimal valid `Transfer` response body — only the required
  /// fields per OpenAPI: id, kind, status, amount, fee, currency,
  /// created_at. Optional fields omitted to assert the DTO tolerates
  /// missing-but-allowed keys.
  String transferBody({
    String status = 'COMPLETED',
    String? failureReason,
  }) {
    final reason = failureReason == null
        ? ''
        : ',"failure_reason":"$failureReason"';
    return '{'
        '"id":"00000000-0000-4000-8000-000000000001",'
        '"kind":"SENT",'
        '"status":"$status",'
        '"amount":"10",'
        '"fee":"0.10",'
        '"currency":"XOF",'
        '"created_at":"2026-05-15T10:00:00Z"'
        '$reason'
        '}';
  }

  group('createTransfer headers', () {
    test('attaches Idempotency-Key and X-Txn-Token to outgoing request',
        () async {
      adapter.script.add(_Reply(status: 202, body: transferBody()));

      final result = await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-123',
      );

      expect(result, isA<Success<Transfer>>());
      expect(adapter.captured, hasLength(1));
      final headers = adapter.captured.single.headers;
      expect(headers['Idempotency-Key'], 'idem-123');
      expect(headers['X-Txn-Token'], 'txn-abc');
      expect(headers['Authorization'], 'Bearer access-1');
      expect(adapter.captured.single.path, '/v1/transfers');
      expect(adapter.captured.single.method, 'POST');
    });

    test('reuses the same Idempotency-Key across two calls', () async {
      // The repository must NOT mint its own key — the caller passes
      // a stable UUID across retries so the server can dedupe.
      adapter.script
        ..add(_Reply(status: 500, body: '{}'))
        ..add(_Reply(status: 202, body: transferBody()));

      await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-stable',
      );
      await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-stable',
      );

      expect(adapter.captured, hasLength(2));
      expect(adapter.captured[0].headers['Idempotency-Key'], 'idem-stable');
      expect(adapter.captured[1].headers['Idempotency-Key'], 'idem-stable');
    });
  });

  group('createTransfer success', () {
    test('202 COMPLETED → Success(Transfer) with completed status', () async {
      adapter.script.add(_Reply(status: 202, body: transferBody()));

      final result = await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-1',
      );

      expect(result, isA<Success<Transfer>>());
      final transfer = (result as Success<Transfer>).value;
      expect(transfer.status, TransferStatus.completed);
      expect(transfer.id, '00000000-0000-4000-8000-000000000001');
      expect(transfer.amount, '10');
      expect(transfer.currency, 'XOF');
      expect(transfer.failureReason, isNull);
    });

    test('202 AWAITING_CLAIM → Success(Transfer) with pending-like status',
        () async {
      adapter.script
          .add(_Reply(status: 202, body: transferBody(status: 'AWAITING_CLAIM')));

      final result = await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-1',
      );

      final transfer = (result as Success<Transfer>).value;
      expect(transfer.status, TransferStatus.awaitingClaim);
      expect(transfer.status.isPendingLike, isTrue);
      expect(transfer.status.isSettledOk, isFalse);
    });

    test('202 FAILED with failure_reason → Success(Transfer) routable to '
        'failed screen', () async {
      adapter.script.add(_Reply(
        status: 202,
        body: transferBody(
          status: 'FAILED',
          failureReason: 'INSUFFICIENT_FUNDS',
        ),
      ));

      final result = await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-1',
      );

      final transfer = (result as Success<Transfer>).value;
      expect(transfer.status, TransferStatus.failed);
      expect(transfer.failureReason, TransferFailureReason.insufficientFunds);
    });
  });

  group('createTransfer error mapping', () {
    test('402 INSUFFICIENT_FUNDS → Failure(PaymentError)', () async {
      adapter.script.add(_Reply(
        status: 402,
        body: '{"type":"about:blank","title":"Insufficient funds",'
            '"status":402,"code":"INSUFFICIENT_FUNDS"}',
        contentType: 'application/problem+json',
      ));

      final result = await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-1',
      );

      expect(result, isA<Failure<Transfer>>());
      final err = (result as Failure<Transfer>).error;
      expect(err, isA<PaymentError>());
      expect(err.code, 'INSUFFICIENT_FUNDS');
    });

    test('422 VELOCITY_LIMIT → Failure(ValidationError)', () async {
      adapter.script.add(_Reply(
        status: 422,
        body: '{"type":"about:blank","title":"Daily limit reached",'
            '"status":422,"code":"VELOCITY_LIMIT"}',
        contentType: 'application/problem+json',
      ));

      final result = await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-1',
      );

      final err = (result as Failure<Transfer>).error;
      expect(err, isA<ValidationError>());
      expect(err.code, 'VELOCITY_LIMIT');
    });

    test('connection timeout → Failure(NetworkError)', () async {
      adapter.failNextWith = DioException.connectionTimeout(
        timeout: const Duration(seconds: 5),
        requestOptions: RequestOptions(path: '/v1/transfers'),
      );

      final result = await repo.createTransfer(
        request: buildRequest(),
        txnToken: 'txn-abc',
        idempotencyKey: 'idem-1',
      );

      final err = (result as Failure<Transfer>).error;
      expect(err, isA<NetworkError>());
    });
  });
}

class _NoopRefresher implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) async => current;
}

/// HttpClientAdapter that replays a scripted sequence of replies and
/// records every captured RequestOptions. Mirrors the helper in
/// `auth_interceptor_test.dart` but adds:
/// - `method` capture so we can assert POST vs GET
/// - configurable `contentType` per reply for `application/problem+json`
/// - `failNextWith` so the next call throws a synthesised
///   `DioException` (used for timeout / connection-error coverage)
class _ScriptedAdapter implements HttpClientAdapter {
  final List<_Reply> script = [];
  final List<_Captured> captured = [];
  DioException? failNextWith;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(_Captured(
      path: options.path,
      method: options.method,
      headers: Map<String, dynamic>.from(options.headers),
      extra: Map<String, dynamic>.from(options.extra),
    ));
    if (failNextWith != null) {
      final e = failNextWith!;
      failNextWith = null;
      throw e;
    }
    if (script.isEmpty) {
      throw StateError('script exhausted at ${options.path}');
    }
    final reply = script.removeAt(0);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [reply.contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Captured {
  _Captured({
    required this.path,
    required this.method,
    required this.headers,
    required this.extra,
  });
  final String path;
  final String method;
  final Map<String, dynamic> headers;
  final Map<String, dynamic> extra;
}

class _Reply {
  _Reply({
    required this.status,
    required this.body,
    this.contentType = 'application/json',
  });
  final int status;
  final String body;
  final String contentType;
}
