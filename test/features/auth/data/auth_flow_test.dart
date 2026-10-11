import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';
import 'package:moneya/features/auth/data/auth_dtos.dart';
import 'package:moneya/features/auth/data/auth_flow.dart';
import 'package:moneya/features/auth/data/auth_repository.dart';

class _Repo extends AuthRepository {
  _Repo() : super();
  ApiResult<LoginResult>? verifyResult;
  final calls = <String>[];

  @override
  Future<ApiResult<LoginResult>> verifyOtp({required String phoneE164, required String code, required String deviceId}) async {
    calls.add('verify:$phoneE164:$code:$deviceId');
    return verifyResult!;
  }

  @override
  Future<ApiResult<OtpRequested>> requestOtp({required String phoneE164, required String deviceId, String? deviceKind, String? deviceName}) async {
    calls.add('request:$phoneE164:$deviceId');
    return const Success(OtpRequested(retryAfterSeconds: 60));
  }
}

class _NoRefresh implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) async => throw StateError('unused');
}

AuthSession _session() => AuthSession(
      accessToken: 'a.b.c',
      refreshToken: 'r-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      userId: 'u-1',
      phone: '+233201234567',
      countryIso2: 'GH',
      kycTier: KycTier.tier0,
    );

void main() {
  late SessionController session;
  late _Repo repo;
  late AuthFlow flow;

  setUp(() async {
    session = SessionController(store: SessionStore(InMemorySecureStorage()), refresher: _NoRefresh());
    await session.bootstrap();
    repo = _Repo();
    flow = AuthFlow(repository: repo, session: session);
  });

  test('requestCode sends the number with this device id', () async {
    await flow.requestCode('+233201234567');
    expect(repo.calls.single, 'request:+233201234567:${session.deviceId}');
    expect(session.deviceId, isNotEmpty);
  });

  test('verifyCode success stores the session before returning', () async {
    repo.verifyResult = Success(LoginResult(session: _session(), passcodeSet: false));
    final r = await flow.verifyCode('+233201234567', '482916');
    expect(r, isA<Success<LoginResult>>());
    expect(session.hasSession, isTrue);
    expect(session.currentUserId, 'u-1');
    expect(repo.calls.single, 'verify:+233201234567:482916:${session.deviceId}');
  });

  test('verifyCode failure leaves the session empty', () async {
    repo.verifyResult = const Failure(AuthError(code: 'OTP_INVALID', title: 'Invalid or expired code', statusCode: 401));
    final r = await flow.verifyCode('+233201234567', '000000');
    expect(r, isA<Failure<LoginResult>>());
    expect(session.hasSession, isFalse);
  });
}
