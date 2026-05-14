import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_client.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/network/interceptors/auth_interceptor.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/session/step_up_controller.dart';
import 'package:moneya/core/storage/secure_storage.dart';

void main() {
  late _ScriptedAdapter adapter;
  late ApiClient api;
  late StepUpController controller;

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

    controller = StepUpController(api);
  });

  test('200 with txn_token caches and returns the token', () async {
    adapter.script.add(_Reply(
      status: 200,
      body: '{"txn_token":"tok-abc"}',
    ));

    final result = await controller.fresh(passcode: '123456');

    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, 'tok-abc');
    expect(controller.currentToken, 'tok-abc');
    expect(controller.extra(),
        {AuthInterceptor.txnTokenKey: 'tok-abc'});
    expect(adapter.captured.single.path, '/v1/auth/step-up');
  });

  test('200 with missing txn_token returns STEPUP_TOKEN_MISSING', () async {
    adapter.script.add(_Reply(status: 200, body: '{}'));

    final result = await controller.fresh(passcode: '123456');

    expect(result, isA<Failure<String>>());
    final err = (result as Failure<String>).error;
    expect(err, isA<UnknownError>());
    expect(err.code, 'STEPUP_TOKEN_MISSING');
    expect(controller.currentToken, isNull);
    expect(controller.extra(), isNull);
  });

  test('401 problem+json surfaces AuthError, does not cache', () async {
    adapter.script.add(_Reply(
      status: 401,
      body: '{"type":"about:blank","title":"Wrong passcode",'
          '"status":401,"code":"INVALID_PASSCODE",'
          '"detail":"Try again."}',
      contentType: 'application/problem+json',
    ));

    final result = await controller.fresh(passcode: '999999');

    expect(result, isA<Failure<String>>());
    final err = (result as Failure<String>).error;
    expect(err, isA<AuthError>());
    expect(err.statusCode, 401);
    expect(controller.currentToken, isNull);
  });

  test('423 problem+json surfaces AuthError with status 423', () async {
    adapter.script.add(_Reply(
      status: 423,
      body: '{"type":"about:blank","title":"Locked",'
          '"status":423,"code":"PASSCODE_LOCKED",'
          '"detail":"Try again in 10 minutes."}',
      contentType: 'application/problem+json',
    ));

    final result = await controller.fresh(passcode: '000000');

    expect(result, isA<Failure<String>>());
    final err = (result as Failure<String>).error;
    expect(err, isA<AuthError>());
    expect(err.statusCode, 423);
  });

  test('5xx surfaces ServerError', () async {
    adapter.script.add(_Reply(
      status: 503,
      body: '{"code":"SERVICE_UNAVAILABLE"}',
    ));

    final result = await controller.fresh(passcode: '123456');

    expect(result, isA<Failure<String>>());
    expect((result as Failure<String>).error, isA<ServerError>());
  });

  test('consume() clears cached token', () async {
    adapter.script.add(_Reply(status: 200, body: '{"txn_token":"tok-xyz"}'));
    await controller.fresh(passcode: '123456');
    expect(controller.currentToken, 'tok-xyz');

    controller.consume();

    expect(controller.currentToken, isNull);
    expect(controller.extra(), isNull);
  });
}

// --- Test doubles ----------------------------------------------------------

/// Refresher that never gets called by these tests — the step-up
/// endpoint is hit with a fresh, non-expired access token in every
/// case, so [SessionController.refresh] is unreachable. Throwing
/// makes any accidental refresh attempt loud.
class _NoopRefresher implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) {
    throw StateError('refresh should not be called from these tests');
  }
}

class _ScriptedAdapter implements HttpClientAdapter {
  final List<_Reply> script = [];
  final List<_Captured> captured = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(_Captured(
      path: options.path,
      headers: Map<String, dynamic>.from(options.headers),
      extra: Map<String, dynamic>.from(options.extra),
    ));
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
  _Captured({required this.path, required this.headers, required this.extra});
  final String path;
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
