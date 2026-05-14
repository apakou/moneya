// Integration-style widget tests for the discard-changes flow on
// [WithdrawAmountScreen]. Exercises the system-back path against a
// real screen instance — i.e. real controllers, real `_isDirty`
// getter, real `DirtyFormScope` wiring.
//
// We pick Withdraw (rather than Load / Transfer / Receive) because
// it has the simplest constructor surface: no Riverpod providers, no
// initState prefill, no Get bindings — just plain enum + scalar
// inputs. The dirty-form mechanics are identical across all four
// screens, so this single test exercises the production wiring
// end-to-end.
//
// We test the system-back path only (not the chevron tap). The
// chevron path is exhaustively covered by the unit-level
// `dirty_form_scope_test.dart` against `confirmAndPopIfDirty`;
// tapping the chevron inside this full-screen widget tree hits a
// `Tooltip` + `Semantics` + `GestureDetector` chain whose tap
// arbitration is fragile under `flutter_test` (the post-frame
// callback never fires consistently). The system-back path
// exercises the same `DirtyFormScope` plumbing without that
// gesture-arena complication.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:moneya/features/auth/domain/supported_country.dart';
import 'package:moneya/features/home/domain/supported_currency.dart';
import 'package:moneya/features/load_money/domain/momo_provider.dart';
import 'package:moneya/features/withdraw/presentation/screens/withdraw_amount_screen.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';

/// Pumps the withdraw screen on top of a placeholder root route so we
/// can observe pops without falling off the navigator stack. Uses
/// `GetMaterialApp` because production code path through
/// `DirtyFormScope` calls `Get.back()`, which needs GetX to be the
/// app's navigation root.
Future<void> _pumpWithdrawScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (rootCtx) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(rootCtx).push(
              MaterialPageRoute<void>(
                builder: (_) => const WithdrawAmountScreen(
                  currency: SupportedCurrency.xof,
                  balanceMinor: 50000,
                  country: SupportedCountry.senegal,
                  provider: MomoProvider.wave,
                ),
              ),
            );
          });
          return const Scaffold(body: Text('root'));
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the dialog action matching [label]. On Material (test
/// default platform), the action is a `TextButton`; on iOS it would
/// be a `CupertinoDialogAction`. Mirrors `dirty_form_scope_test.dart`.
Future<void> _tapDialogAction(WidgetTester tester, String label) async {
  final material = find.widgetWithText(TextButton, label);
  if (material.evaluate().isNotEmpty) {
    await tester.tap(material);
    await tester.pumpAndSettle();
    return;
  }
  final cupertino = find.byWidgetPredicate(
    (w) =>
        w is CupertinoDialogAction &&
        w.child is Text &&
        (w.child as Text).data == label,
  );
  expect(cupertino, findsOneWidget);
  await tester.tap(cupertino);
  await tester.pumpAndSettle();
}

/// Returns the destination-phone `TextField` (the only one on the
/// screen besides amount, which uses a keypad sheet not a field).
Finder _phoneField() => find.byType(TextField);

/// Simulates the Android system-back gesture. With
/// `DirtyFormScope`'s `PopScope(canPop: false)` on a dirty form,
/// this fires `onPopInvokedWithResult` which opens the dialog. On a
/// clean form, the route pops directly.
Future<void> _systemBack(WidgetTester tester) async {
  final navState = tester.state<NavigatorState>(
    find.byType(Navigator).first,
  );
  // ignore: unawaited_futures
  navState.maybePop();
  await tester.pumpAndSettle();
}

void main() {
  group('WithdrawAmountScreen discard-changes (system back)', () {
    testWidgets('clean form: system back pops without dialog',
        (tester) async {
      await _pumpWithdrawScreen(tester);
      expect(find.byType(WithdrawAmountScreen), findsOneWidget);

      await _systemBack(tester);

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(WithdrawAmountScreen), findsNothing);
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('dirty form: system back opens dialog, cancel keeps form',
        (tester) async {
      await _pumpWithdrawScreen(tester);

      // Make the form dirty by typing in the destination phone.
      await tester.enterText(_phoneField(), '770000000');
      await tester.pump();

      await _systemBack(tester);

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byType(WithdrawAmountScreen), findsOneWidget);

      await _tapDialogAction(tester, 'Keep editing');

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(WithdrawAmountScreen), findsOneWidget);
      expect(find.text('root'), findsNothing);
    });

    testWidgets('dirty form: system back + discard pops back to root',
        (tester) async {
      await _pumpWithdrawScreen(tester);

      await tester.enterText(_phoneField(), '770000000');
      await tester.pump();

      await _systemBack(tester);

      expect(find.text('Discard changes?'), findsOneWidget);

      await _tapDialogAction(tester, 'Discard');
      // Drain the post-frame pop scheduled inside
      // DirtyFormScope.onPopInvokedWithResult.
      await tester.pumpAndSettle();

      expect(find.byType(WithdrawAmountScreen), findsNothing);
      expect(find.text('root'), findsOneWidget);
    });
  });
}
