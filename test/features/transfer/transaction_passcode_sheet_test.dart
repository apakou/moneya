import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/session/step_up_controller.dart';
import 'package:moneya/features/transfer/data/transaction_auth_outcome.dart';
import 'package:moneya/features/transfer/presentation/widgets/transaction_passcode_sheet.dart';

void main() {
  /// Tap the 6 boxes via the visible TextFields, one digit at a time.
  Future<void> enterCode(WidgetTester tester, String code) async {
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(6));
    for (var i = 0; i < code.length; i++) {
      await tester.enterText(fields.at(i), code[i]);
      await tester.pump();
    }
  }

  Future<Future<TransactionAuthOutcome>> openSheet(
    WidgetTester tester,
    _FakeStepUp fake, {
    int maxAttempts = 3,
  }) async {
    final outcomeCompleter = Completer<TransactionAuthOutcome>();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showTransactionPasscodeSheet(
                      context: context,
                      maxAttempts: maxAttempts,
                      stepUp: fake,
                    );
                    outcomeCompleter.complete(result);
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return outcomeCompleter.future;
  }

  testWidgets('correct passcode → Authorised with txn_token', (tester) async {
    final fake = _FakeStepUp(
      response: const Success<String>('tok-abc'),
    );
    final future = await openSheet(tester, fake);
    await enterCode(tester, '123456');
    await tester.pumpAndSettle();

    final outcome = await future;
    expect(outcome, isA<TransactionAuthAuthorised>());
    expect((outcome as TransactionAuthAuthorised).txnToken, 'tok-abc');
    expect(fake.calls, ['123456']);
  });

  testWidgets('401 retries in-place; third wrong entry pops LockedOut',
      (tester) async {
    final fake = _FakeStepUp(
      response: const Failure<String>(AuthError(
        code: 'INVALID_PASSCODE',
        title: 'Wrong passcode',
        detail: 'Try again.',
        statusCode: 401,
      )),
    );
    final future = await openSheet(tester, fake, maxAttempts: 3);

    // Three consecutive wrong entries. The sheet stays open between
    // attempts (verified by the fact that calls.length grows past 1);
    // after the third the 423-equivalent client-side cap is hit and
    // the sheet pops with LockedOut.
    await enterCode(tester, '000001');
    await tester.pumpAndSettle();
    await enterCode(tester, '000002');
    await tester.pumpAndSettle();
    await enterCode(tester, '000003');
    await tester.pumpAndSettle();

    final outcome = await future;
    expect(outcome, isA<TransactionAuthLockedOut>());
    expect((outcome as TransactionAuthLockedOut).message, 'Try again.');
    expect(fake.calls.length, 3);
  });

  testWidgets('423 lockout pops immediately', (tester) async {
    final fake = _FakeStepUp(
      response: const Failure<String>(AuthError(
        code: 'PASSCODE_LOCKED',
        title: 'Locked',
        detail: 'Try again in 10 minutes.',
        statusCode: 423,
      )),
    );
    final future = await openSheet(tester, fake);

    await enterCode(tester, '111111');
    await tester.pumpAndSettle();

    final outcome = await future;
    expect(outcome, isA<TransactionAuthLockedOut>());
    expect((outcome as TransactionAuthLockedOut).message,
        'Try again in 10 minutes.');
    expect(fake.calls.length, 1);
  });

  testWidgets('network error pops NetworkError', (tester) async {
    final fake = _FakeStepUp(
      response: const Failure<String>(NetworkError(detail: 'offline')),
    );
    final future = await openSheet(tester, fake);

    await enterCode(tester, '222222');
    await tester.pumpAndSettle();

    final outcome = await future;
    expect(outcome, isA<TransactionAuthNetworkError>());
    expect((outcome as TransactionAuthNetworkError).error, isA<NetworkError>());
  });
}

/// In-memory [StepUpController] stand-in. Records every passcode it
/// receives and replays the same scripted [response] on each call.
class _FakeStepUp implements StepUpController {
  _FakeStepUp({required this.response});

  final ApiResult<String> response;
  final List<String> calls = [];

  @override
  Future<ApiResult<String>> fresh({required String passcode}) async {
    calls.add(passcode);
    return response;
  }

  // Members below are unused by the sheet but required by the
  // interface; keep them as defensible no-ops so a typo in production
  // code that hits them inside a test would fail loud.
  @override
  String? get currentToken =>
      throw UnimplementedError('not used by the sheet');

  @override
  void consume() => throw UnimplementedError('not used by the sheet');

  @override
  Map<String, Object?>? extra() =>
      throw UnimplementedError('not used by the sheet');

  // GetxService surface — the sheet never registers / boots us, so
  // these never fire. Mark unimplemented for safety.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
