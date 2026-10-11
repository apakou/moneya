import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/features/auth/data/auth_dtos.dart';
import 'package:moneya/features/auth/data/auth_flow.dart';
import 'package:moneya/features/auth/presentation/screens/verify_phone_screen.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';

class _FakeFlow extends AuthFlow {
  _FakeFlow() : super();
  ApiResult<LoginResult> verifyResult = const Failure(UnknownError());
  ApiResult<OtpRequested> requestResult = const Success(OtpRequested(retryAfterSeconds: 60));
  final verified = <(String, String)>[];
  int requested = 0;

  @override
  Future<ApiResult<LoginResult>> verifyCode(String phoneE164, String code) async {
    verified.add((phoneE164, code));
    return verifyResult;
  }

  @override
  Future<ApiResult<OtpRequested>> requestCode(String phoneE164) async {
    requested++;
    return requestResult;
  }
}

LoginResult _login({required bool passcodeSet}) => LoginResult(
      passcodeSet: passcodeSet,
      session: AuthSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        userId: 'u',
        phone: '+233201234567',
        countryIso2: 'GH',
        kycTier: KycTier.tier0,
      ),
    );

void main() {
  late _FakeFlow flow;

  setUp(() {
    Get.reset();
    flow = _FakeFlow();
    Get.put<AuthFlow>(flow);
  });
  tearDown(Get.reset);

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const VerifyPhoneScreen(dialCode: '233', nationalNumber: '201234567', phoneE164: '+233201234567'),
    ));
    await tester.pump();
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    final fields = find.byType(TextField);
    for (var i = 0; i < code.length; i++) {
      await tester.enterText(fields.at(i), code[i]);
      await tester.pump();
    }
  }

  testWidgets('shows six boxes (contract: 6-digit code) without overflow on a 320dp phone', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(TextField), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a full code is sent once with the E.164 number; a new user goes to passcode creation', (tester) async {
    flow.verifyResult = Success(_login(passcodeSet: false));
    await pumpScreen(tester);
    await typeCode(tester, '482916');
    await tester.pumpAndSettle();
    expect(flow.verified, [('+233201234567', '482916')]);
    expect(find.text('Set a passcode'), findsOneWidget);
  });

  testWidgets('wrong code → the incorrect-code sheet, boxes cleared', (tester) async {
    flow.verifyResult = const Failure(AuthError(code: 'OTP_INVALID', title: 'x', statusCode: 401));
    await pumpScreen(tester);
    await typeCode(tester, '000000');
    await tester.pumpAndSettle();
    expect(find.text('Incorrect code entered'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.every((f) => f.controller!.text.isEmpty), isTrue);
  });

  testWidgets('lockout → snackbar with the wait time, no incorrect-code sheet', (tester) async {
    flow.verifyResult = const Failure(RateLimitError(code: 'OTP_LOCKED', title: 'Too many attempts', retryAfter: Duration(minutes: 15)));
    await pumpScreen(tester);
    await typeCode(tester, '000000');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Try again in 15 min'), findsOneWidget);
    expect(find.text('Incorrect code entered'), findsNothing);
  });

  testWidgets('network failure → generic connection message', (tester) async {
    flow.verifyResult = const Failure(NetworkError());
    await pumpScreen(tester);
    await typeCode(tester, '123789');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('No connection'), findsOneWidget);
  });
}
