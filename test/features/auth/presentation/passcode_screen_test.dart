import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/preferences/app_prefs.dart';
import 'package:moneya/core/storage/secure_storage.dart';
import 'package:moneya/features/auth/data/auth_flow.dart';
import 'package:moneya/features/auth/presentation/screens/passcode_screen.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';

class _FakeFlow extends AuthFlow {
  _FakeFlow() : super();
  ApiResult<void> result = const Success<void>(null);
  final saved = <String>[];

  @override
  Future<ApiResult<void>> savePasscode(String passcode, {String? currentPasscode}) async {
    saved.add(passcode);
    return result;
  }
}

void main() {
  late _FakeFlow flow;

  setUp(() async {
    Get.reset();
    flow = _FakeFlow();
    Get.put<AuthFlow>(flow);
    final prefs = AppPrefs(InMemorySecureStorage());
    await prefs.load();
    Get.put<AppPrefs>(prefs);
  });
  tearDown(Get.reset);

  Future<void> pumpConfirm(WidgetTester tester) async {
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
      home: const PasscodeScreen(mode: PasscodeMode.confirm, expectedCode: '482916'),
    ));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String code) async {
    final fields = find.byType(TextField);
    for (var i = 0; i < code.length; i++) {
      await tester.enterText(fields.at(i), code[i]);
      await tester.pump();
    }
  }

  testWidgets('six boxes fit a 320dp phone', (tester) async {
    await pumpConfirm(tester);
    expect(find.byType(TextField), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mismatch never reaches the server', (tester) async {
    await pumpConfirm(tester);
    await type(tester, '739104');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text("Passcodes don't match."), findsOneWidget);
    expect(flow.saved, isEmpty);
  });

  testWidgets('server rejection (too weak) shows the localized message and stays on the screen', (tester) async {
    flow.result = const Failure(ValidationError(code: 'PASSCODE_TOO_WEAK', title: 'x'));
    await pumpConfirm(tester);
    await type(tester, '482916');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(flow.saved, ['482916']);
    expect(find.text('Choose a less predictable passcode.'), findsOneWidget);
    expect(find.byType(PasscodeScreen), findsOneWidget);
  });

  testWidgets('success saves once and leaves the screen', (tester) async {
    await pumpConfirm(tester);
    await type(tester, '482916');
    await tester.tap(find.text('Save'));
    await tester.pump();
    // Biometric enrolment calls a platform channel (no plugin in tests → caught →
    // treated as unavailable); its failure resolves in real time, not fake time.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(flow.saved, ['482916']);
    expect(find.byType(PasscodeScreen), findsNothing);
  });

  // Regression: both steps are the same widget type, and GetX names closure
  // routes by runtimeType, so `Get.to` used to drop the push as a "duplicate"
  // and Next did nothing after setting the passcode.
  testWidgets('set → Next opens the confirm step', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
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
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Get.off<void>(() => const PasscodeScreen(mode: PasscodeMode.set)),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Set a passcode'), findsOneWidget);

    await type(tester, '482916');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm the passcode'), findsOneWidget);
  });
}
