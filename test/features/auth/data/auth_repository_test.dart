import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_client.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/network/dio_session_refresher.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';
import 'package:moneya/features/auth/data/auth_repository.dart';

const _device = '3f8c1d2e-5a4b-4c6d-8e7f-0a1b2c3d4e5f';

const _tokens = {
  'access_token': 'a.b.c',
  'refresh_token': 'r-1',
  'expires_in': 900,
  'passcode_set': false,
  'user': {
    'id': '11111111-1111-4111-8111-111111111111',
    'phone': '+233201234567',
    'country': 'GH',
    'full_name': null,
    'photo_url': null,
    'kyc_tier': 'TIER_0',
    'created_at': '2026-10-10T00:00:00.000Z',
  },
};

void main() {
  late _Adapter adapter;
  late AuthRepository repo;

  setUp(() async {
    final session = SessionController(
      store: SessionStore(InMemorySecureStorage()),
      refresher: _NoRefresh(),
    );
    await session.bootstrap();
    final api = ApiClient.build(
      session: session,
      appVersion: '1.0.0',
      localeProvider: () => 'en',
      baseUrlOverride: 'https://api.test',
    );
    adapter = _Adapter();
    api.dio.httpClientAdapter = adapter;
    repo = AuthRepository.test(api);
  });

  group('requestOtp', () {
    test('POSTs phone + device and parses the masked destination', () async {
      adapter.reply(202, {'retry_after_seconds': 60, 'masked_destination': '+233 20 ** ** 67'});
      final r = await repo.requestOtp(phoneE164: '+233201234567', deviceId: _device, deviceKind: 'ANDROID');
      expect(r, isA<Success<dynamic>>());
      final ok = (r as Success).value;
      expect(ok.retryAfterSeconds, 60);
      expect(ok.maskedDestination, contains('**'));
      expect(adapter.last.path, '/v1/auth/otp');
      expect(jsonDecode(adapter.last.body), {'phone': '+233201234567', 'device_id': _device, 'device_kind': 'ANDROID'});
      expect(adapter.last.headers.containsKey('Authorization'), isFalse);
    });

    test('429 surfaces RateLimitError with the server code and Retry-After', () async {
      adapter.reply(429, {'code': 'RATE_LIMITED', 'title': 'Too many requests', 'status': 429}, headers: {'retry-after': ['600']});
      final r = await repo.requestOtp(phoneE164: '+233201234567', deviceId: _device);
      final err = (r as Failure).error;
      expect(err, isA<RateLimitError>());
      expect(err.code, 'RATE_LIMITED');
      expect(err.retryAfter, const Duration(seconds: 600));
    });
  });

  group('verifyOtp', () {
    test('builds the session from AuthTokens (expires_in → expiresAt) and flags first login', () async {
      adapter.reply(200, _tokens);
      final before = DateTime.now();
      final r = await repo.verifyOtp(phoneE164: '+233201234567', code: '482916', deviceId: _device);
      final login = (r as Success).value;
      expect(login.passcodeSet, isFalse);
      expect(login.session.userId, '11111111-1111-4111-8111-111111111111');
      expect(login.session.countryIso2, 'GH');
      expect(login.session.kycTier, KycTier.tier0);
      expect(login.session.expiresAt.isAfter(before.add(const Duration(minutes: 14))), isTrue);
      expect(login.session.expiresAt.isBefore(before.add(const Duration(minutes: 16))), isTrue);
    });

    test('wrong code: 401 OTP_INVALID is a single request (no refresh/retry)', () async {
      adapter.reply(401, {'code': 'OTP_INVALID', 'title': 'Invalid or expired code', 'status': 401});
      final r = await repo.verifyOtp(phoneE164: '+233201234567', code: '000000', deviceId: _device);
      final err = (r as Failure).error;
      expect(err, isA<AuthError>());
      expect(err.code, 'OTP_INVALID');
      expect(adapter.requests.length, 1);
    });

    test('lockout: 429 OTP_LOCKED', () async {
      adapter.reply(429, {'code': 'OTP_LOCKED', 'title': 'Too many attempts', 'status': 429}, headers: {'retry-after': ['900']});
      final r = await repo.verifyOtp(phoneE164: '+233201234567', code: '000000', deviceId: _device);
      expect((r as Failure).error.code, 'OTP_LOCKED');
    });

    test('a malformed body throws instead of producing a half-built session', () async {
      adapter.reply(200, {'access_token': 'x'});
      expect(
        () => repo.verifyOtp(phoneE164: '+233201234567', code: '482916', deviceId: _device),
        throwsFormatException,
      );
    });
  });

  group('setPasscode', () {
    test('204 → Success; sends current_passcode only when given', () async {
      adapter.reply(204, null);
      expect(await repo.setPasscode(passcode: '482916'), isA<Success<void>>());
      expect(jsonDecode(adapter.last.body), {'passcode': '482916'});
      adapter.reply(204, null);
      await repo.setPasscode(passcode: '739104', currentPasscode: '482916');
      expect(jsonDecode(adapter.last.body), {'passcode': '739104', 'current_passcode': '482916'});
    });

    test('weak passcode → ValidationError PASSCODE_TOO_WEAK', () async {
      adapter.reply(400, {'code': 'PASSCODE_TOO_WEAK', 'title': 'Choose a less predictable passcode', 'status': 400});
      final r = await repo.setPasscode(passcode: '123456');
      final err = (r as Failure).error;
      expect(err, isA<ValidationError>());
      expect(err.code, 'PASSCODE_TOO_WEAK');
    });
  });

  group('DioSessionRefresher parsing (contract: expires_in, rotated tokens)', () {
    final fallback = AuthSession(
      accessToken: 'old',
      refreshToken: 'old-r',
      expiresAt: DateTime(2020),
      userId: 'u',
      phone: '+233201234567',
      countryIso2: 'GH',
      kycTier: KycTier.tier0,
    );
    test('computes expiresAt from expires_in and replaces both tokens', () {
      final now = DateTime.utc(2026, 10, 10, 12);
      final s = DioSessionRefresher.parseForTest(_tokens, fallback: fallback, now: now);
      expect(s.accessToken, 'a.b.c');
      expect(s.refreshToken, 'r-1');
      expect(s.expiresAt, now.add(const Duration(seconds: 900)));
      expect(s.userId, 'u'); // identity preserved from the existing session
    });
    test('picks up a tier change echoed in user', () {
      final upgraded = {..._tokens, 'user': {...(_tokens['user']! as Map), 'kyc_tier': 'TIER_1'}};
      expect(DioSessionRefresher.parseForTest(upgraded, fallback: fallback).kycTier, KycTier.tier1);
    });
    test('rejects the old expires_at shape instead of mis-parsing it', () {
      expect(
        () => DioSessionRefresher.parseForTest({'access_token': 'a', 'refresh_token': 'r', 'expires_at': '2026-01-01T00:00:00Z'}, fallback: fallback),
        throwsFormatException,
      );
    });
  });
}

class _NoRefresh implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) async => throw StateError('no refresh in this test');
}

class _Req {
  _Req(this.path, this.headers, this.body);
  final String path;
  final Map<String, dynamic> headers;
  final String body;
}

class _Adapter implements HttpClientAdapter {
  final List<_Req> requests = [];
  final List<(int, Object?, Map<String, List<String>>)> _script = [];
  _Req get last => requests.last;

  void reply(int status, Object? body, {Map<String, List<String>> headers = const {}}) =>
      _script.add((status, body, headers));

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final c in requestStream) {
        bytes.addAll(c);
      }
    }
    requests.add(_Req(options.path, Map<String, dynamic>.from(options.headers), utf8.decode(bytes)));
    final (status, body, headers) = _script.removeAt(0);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [status >= 400 ? 'application/problem+json' : 'application/json'],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
