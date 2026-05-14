import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/interceptors/error_mapping_interceptor.dart';

void main() {
  late _ScriptedAdapter adapter;
  late Dio dio;

  setUp(() {
    adapter = _ScriptedAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(ErrorMappingInterceptor());
  });

  Future<ApiError> expectFailure(Future<void> Function() call) async {
    try {
      await call();
      fail('expected DioException');
    } on DioException catch (e) {
      expect(e.error, isA<ApiError>(), reason: 'error: ${e.error}');
      return e.error! as ApiError;
    }
  }

  group('transport-level errors', () {
    test('connection timeout → NetworkError(TIMEOUT)', () async {
      adapter.script.add(_Reply.transportError(DioExceptionType.connectionTimeout));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err, isA<NetworkError>());
      expect(err.code, 'TIMEOUT');
    });

    test('bad cert → NetworkError(TLS_ERROR)', () async {
      adapter.script.add(_Reply.transportError(DioExceptionType.badCertificate));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err.code, 'TLS_ERROR');
    });

    test('connectionError → NetworkError(NETWORK_ERROR)', () async {
      adapter.script.add(_Reply.transportError(DioExceptionType.connectionError));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err, isA<NetworkError>());
      expect(err.code, 'NETWORK_ERROR');
    });
  });

  group('HTTP status mapping', () {
    test('400 → ValidationError with field errors', () async {
      adapter.script.add(_Reply.http(400, body: {
        'code': 'VALIDATION_FAILED',
        'title': 'Invalid',
        'detail': 'phone is required',
        'errors': {'phone': 'must be E.164'},
      }));
      final err = await expectFailure(() => dio.post<Object?>('/x', data: {}));
      expect(err, isA<ValidationError>());
      expect(err.code, 'VALIDATION_FAILED');
      expect((err as ValidationError).fieldErrors['phone'], 'must be E.164');
    });

    test('401 → AuthError', () async {
      adapter.script.add(_Reply.http(401, body: {}));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err, isA<AuthError>());
      expect(err.code, 'UNAUTHENTICATED');
    });

    test('403 → PaymentError (KYC + insufficient funds bucket)', () async {
      adapter.script.add(_Reply.http(403, body: {
        'code': 'KYC_REQUIRED',
        'title': 'KYC required',
      }));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err, isA<PaymentError>());
      expect(err.code, 'KYC_REQUIRED');
    });

    test('409 → ConflictError', () async {
      adapter.script.add(_Reply.http(409, body: {}));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err, isA<ConflictError>());
    });

    test('429 → RateLimitError, parses Retry-After', () async {
      adapter.script.add(_Reply.http(
        429,
        body: {},
        headers: {'retry-after': ['30']},
      ));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err, isA<RateLimitError>());
      expect((err as RateLimitError).retryAfter, const Duration(seconds: 30));
    });

    test('5xx → ServerError', () async {
      adapter.script.add(_Reply.http(503, body: {}));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err, isA<ServerError>());
    });

    test('404 → UnknownError (no dedicated subtype)', () async {
      adapter.script.add(_Reply.http(404, body: {}));
      final err = await expectFailure(() => dio.get<Object?>('/x'));
      expect(err, isA<UnknownError>());
      expect(err.code, 'NOT_FOUND');
    });
  });
}

class _ScriptedAdapter implements HttpClientAdapter {
  final List<_Reply> script = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (script.isEmpty) throw StateError('script exhausted');
    final reply = script.removeAt(0);
    if (reply.transportType != null) {
      throw DioException(
        requestOptions: options,
        type: reply.transportType!,
        message: 'simulated ${reply.transportType}',
      );
    }
    return ResponseBody.fromString(
      reply.bodyJson,
      reply.status!,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Reply {
  _Reply._({this.status, this.bodyJson = '{}', this.headers = const {}, this.transportType});

  factory _Reply.http(int status, {Object body = const {}, Map<String, List<String>> headers = const {}}) {
    final encoded = body is String ? body : _jsonEncode(body);
    return _Reply._(status: status, bodyJson: encoded, headers: headers);
  }

  factory _Reply.transportError(DioExceptionType type) =>
      _Reply._(transportType: type);

  final int? status;
  final String bodyJson;
  final Map<String, List<String>> headers;
  final DioExceptionType? transportType;

  static String _jsonEncode(Object body) {
    // Tiny dependency-free JSON encoder good enough for test bodies (maps of
    // strings, ints, nested maps, lists).
    if (body is Map) {
      final entries = body.entries
          .map((e) => '"${e.key}":${_jsonEncode(e.value as Object)}')
          .join(',');
      return '{$entries}';
    }
    if (body is List) {
      return '[${body.map((e) => _jsonEncode(e as Object)).join(',')}]';
    }
    if (body is num || body is bool) return body.toString();
    return '"${body.toString().replaceAll('"', r'\"')}"';
  }
}
