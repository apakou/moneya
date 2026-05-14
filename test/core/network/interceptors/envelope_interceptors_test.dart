import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/interceptors/idempotency_interceptor.dart';
import 'package:moneya/core/network/interceptors/trace_interceptor.dart';

void main() {
  late _CapturingAdapter adapter;

  setUp(() {
    adapter = _CapturingAdapter();
  });

  group('IdempotencyInterceptor', () {
    test('omits header when neither flag nor key supplied', () async {
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(IdempotencyInterceptor());
      await dio.get<Object?>('https://api.test/v1/quote');
      expect(adapter.last.headers.containsKey('Idempotency-Key'), isFalse);
    });

    test('auto-mints UUID v4 when extra.idempotent == true', () async {
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(IdempotencyInterceptor());
      await dio.post<Object?>(
        'https://api.test/v1/transfers',
        data: {'amount': '1'},
        options: Options(extra: {IdempotencyInterceptor.idempotentFlag: true}),
      );
      final key = adapter.last.headers['Idempotency-Key'] as String;
      expect(key.length, 36);
      expect(key[14], '4');
    });

    test('honours caller-supplied idempotencyKey verbatim', () async {
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(IdempotencyInterceptor());
      await dio.post<Object?>(
        'https://api.test/v1/transfers',
        data: {'amount': '1'},
        options: Options(extra: {
          IdempotencyInterceptor.idempotencyKeyExtra: 'caller-uuid-1234',
        }),
      );
      expect(adapter.last.headers['Idempotency-Key'], 'caller-uuid-1234');
    });
  });

  group('TraceInterceptor', () {
    Dio buildDio() {
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(TraceInterceptor(
        deviceIdProvider: () => 'device-xyz',
        appVersion: '1.0.0+1',
        localeProvider: () => 'fr-FR',
      ));
      return dio;
    }

    test('attaches all envelope headers', () async {
      final dio = buildDio();
      await dio.get<Object?>('https://api.test/v1/me');
      final h = adapter.last.headers;
      expect(h['X-Device-Id'], 'device-xyz');
      expect(h['X-App-Version'], '1.0.0+1');
      expect(h['Accept-Language'], 'fr-FR');
      expect(h['traceparent'], matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-01$')));
      expect(h['X-Platform'], isNotNull);
    });

    test('per-request acceptLanguage override wins over provider', () async {
      final dio = buildDio();
      await dio.get<Object?>(
        'https://api.test/v1/me',
        options: Options(extra: {'acceptLanguage': 'en-US'}),
      );
      expect(adapter.last.headers['Accept-Language'], 'en-US');
    });

    test('mints a fresh traceparent for every request', () async {
      final dio = buildDio();
      await dio.get<Object?>('https://api.test/v1/a');
      final first = adapter.last.headers['traceparent'] as String;
      await dio.get<Object?>('https://api.test/v1/b');
      final second = adapter.last.headers['traceparent'] as String;
      expect(first, isNot(equals(second)));
    });
  });
}

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> _captured = [];
  RequestOptions get last => _captured.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _captured.add(options);
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}
