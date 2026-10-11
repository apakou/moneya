import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/interceptors/auth_interceptor.dart';
import 'package:moneya/core/network/interceptors/error_mapping_interceptor.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';

void main() {
  AuthSession buildSession({String access = 'access-1', String refresh = 'rfr-1'}) =>
      AuthSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        userId: 'user-1',
        phone: '+221770000000',
        countryIso2: 'SN',
        kycTier: KycTier.tier1,
      );

  late _FakeRefresher refresher;
  late SessionController session;
  late _ScriptedAdapter adapter;
  late Dio dio;

  setUp(() async {
    final store = SessionStore(InMemorySecureStorage());
    refresher = _FakeRefresher();
    session = SessionController(store: store, refresher: refresher);
    await session.bootstrap();
    await session.setSession(buildSession());

    adapter = _ScriptedAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    final retryClient = Dio(BaseOptions(baseUrl: 'https://api.test'));
    dio.httpClientAdapter = adapter;
    retryClient.httpClientAdapter = adapter;
    dio.interceptors.addAll([
      AuthInterceptor(session, retryClient: retryClient),
      ErrorMappingInterceptor(),
    ]);
  });

  test('attaches Authorization header on outgoing request', () async {
    adapter.script.add(_Reply(status: 200, body: '{"ok":true}'));
    await dio.get<Object?>('/v1/me');
    expect(adapter.captured.last.headers['Authorization'], 'Bearer access-1');
  });

  test('skipAuth omits Authorization', () async {
    adapter.script.add(_Reply(status: 200, body: '{"ok":true}'));
    await dio.get<Object?>(
      '/v1/auth/refresh',
      options: Options(extra: {AuthInterceptor.skipAuthKey: true}),
    );
    expect(adapter.captured.last.headers.containsKey('Authorization'), isFalse);
  });

  test('forwards X-Txn-Token from options.extra', () async {
    adapter.script.add(_Reply(status: 200, body: '{"ok":true}'));
    await dio.post<Object?>(
      '/v1/transfers',
      data: {'amount': '1'},
      options: Options(extra: {AuthInterceptor.txnTokenKey: 'txn-abc'}),
    );
    expect(adapter.captured.last.headers['X-Txn-Token'], 'txn-abc');
  });

  test('401 triggers refresh and retries with new token', () async {
    refresher.next = buildSession(access: 'access-2', refresh: 'rfr-2');
    adapter.script
      ..add(_Reply(status: 401, body: '{"code":"UNAUTHENTICATED"}'))
      ..add(_Reply(status: 200, body: '{"ok":true}'));

    final res = await dio.get<Object?>('/v1/me');
    expect(res.statusCode, 200);
    expect(adapter.captured.length, 2);
    expect(adapter.captured[0].headers['Authorization'], 'Bearer access-1');
    expect(adapter.captured[1].headers['Authorization'], 'Bearer access-2');
    expect(session.currentAccessToken, 'access-2');
  });

  test('401 UNAUTHORIZED (bad bearer) triggers a refresh', () async {
    refresher.next = buildSession(access: 'access-2');
    adapter.script
      ..add(_Reply(status: 401, body: '{"code":"UNAUTHORIZED"}'))
      ..add(_Reply(status: 200, body: '{"ok":true}'));
    final res = await dio.get<Object?>('/v1/me');
    expect(res.statusCode, 200);
    expect(adapter.captured.length, 2);
  });

  test('401 PASSCODE_INVALID is NOT retried: one wrong passcode = one attempt', () async {
    adapter.script.add(_Reply(status: 401, body: '{"code":"PASSCODE_INVALID"}'));
    try {
      await dio.post<Object?>('/v1/auth/step-up', data: {'passcode': '111111'});
      fail('expected DioException');
    } on DioException catch (e) {
      expect((e.error! as AuthError).code, 'PASSCODE_INVALID');
    }
    expect(adapter.captured.length, 1, reason: 'no refresh + retry');
    expect(session.currentAccessToken, 'access-1', reason: 'session untouched');
  });

  test('401 retries exactly once: second 401 surfaces AuthError', () async {
    refresher.next = buildSession(access: 'access-2');
    adapter.script
      ..add(_Reply(status: 401, body: '{}'))
      ..add(_Reply(status: 401, body: '{}'));

    try {
      await dio.get<Object?>('/v1/me');
      fail('expected DioException');
    } on DioException catch (e) {
      expect(e.error, isA<AuthError>());
      expect((e.error! as AuthError).statusCode, 401);
    }
    expect(adapter.captured.length, 2);
  });

  test('refresh failure surfaces AuthError(AUTH_REFRESH_FAILED)', () async {
    refresher.failNext = true;
    adapter.script.add(_Reply(status: 401, body: '{}'));

    try {
      await dio.get<Object?>('/v1/me');
      fail('expected DioException');
    } on DioException catch (e) {
      expect(e.error, isA<AuthError>());
      expect((e.error! as AuthError).code, 'AUTH_REFRESH_FAILED');
    }
  });
}

class _FakeRefresher implements SessionRefresher {
  AuthSession? next;
  bool failNext = false;

  @override
  Future<AuthSession> refresh(AuthSession current) async {
    if (failNext) {
      failNext = false;
      throw StateError('refresh denied');
    }
    return next ?? current;
  }
}

/// HttpClientAdapter that replays a scripted sequence of replies and
/// records every captured RequestOptions.
class _ScriptedAdapter implements HttpClientAdapter {
  final List<_Reply> script = [];
  final List<_Captured> captured = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Snapshot headers eagerly: the AuthInterceptor mutates the same
    // RequestOptions object on retry, so a reference-only capture would
    // show the LAST header state on every entry.
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
        Headers.contentTypeHeader: ['application/json'],
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
  _Reply({required this.status, required this.body});
  final int status;
  final String body;
}
