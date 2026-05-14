// Widget tests for [DirtyFormScope].
//
// Verifies:
//  - Clean state pops without a dialog.
//  - Dirty state shows the discard dialog and suppresses the pop.
//  - Confirming discard pops the underlying route.
//  - Cancelling keeps the user on the form route.
//  - `confirmAndPopIfDirty` defers the actual pop to a post-frame
//    (mirrors the chevron path that originally crashed with the
//    deactivated-ancestor error).

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:moneya/core/widgets/dirty_form_scope.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';

/// Pumps [child] inside a `GetMaterialApp` (the production app uses
/// GetX for navigation, so `Get.back()` only works when the root
/// MaterialApp is GetX-aware) configured with the same localization
/// delegates the production app uses, then pushes a second route on
/// top so we can test back-pops without exiting the app itself
/// (Navigator can't pop the root route).
Future<void> _pumpFormRoute(
  WidgetTester tester,
  Widget child,
) async {
  await tester.pumpWidget(
    GetMaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (rootCtx) {
          // Push the form route once the root frame is laid out so we
          // have a non-empty Navigator stack to pop from.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(rootCtx).push(
              MaterialPageRoute<void>(builder: (_) => child),
            );
          });
          return const Scaffold(body: Text('root'));
        },
      ),
    ),
  );
  // Pump until the pushed route is fully on-screen.
  await tester.pumpAndSettle();
}

/// Taps the dialog action whose label matches [label].
///
/// On Android/test the action is a Material `TextButton`; on iOS
/// it would be a `CupertinoDialogAction`. We match either by
/// walking up from the label text to its nearest tappable ancestor.
Future<void> _tapDialogAction(WidgetTester tester, String label) async {
  // Try Material TextButton first (test default platform = Android).
  final material = find.widgetWithText(TextButton, label);
  if (material.evaluate().isNotEmpty) {
    await tester.tap(material);
    await tester.pumpAndSettle();
    return;
  }
  // iOS path.
  final cupertino = find.byWidgetPredicate(
    (w) =>
        w is CupertinoDialogAction &&
        w.child is Text &&
        (w.child as Text).data == label,
  );
  expect(cupertino, findsOneWidget,
      reason: 'Dialog action "$label" must be present');
  await tester.tap(cupertino);
  await tester.pumpAndSettle();
}

void main() {
  group('DirtyFormScope', () {
    testWidgets('clean state pops without showing a dialog',
        (tester) async {
      await _pumpFormRoute(
        tester,
        const DirtyFormScope(
          isDirty: false,
          child: Scaffold(body: Text('form')),
        ),
      );
      expect(find.text('form'), findsOneWidget);

      // System back gesture (simulated via NavigatorState.maybePop).
      final navState = tester.state<NavigatorState>(find.byType(Navigator));
      final popped = await navState.maybePop();
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(find.text('form'), findsNothing);
      expect(find.text('root'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('dirty state shows dialog and blocks pop until confirmed',
        (tester) async {
      await _pumpFormRoute(
        tester,
        const DirtyFormScope(
          isDirty: true,
          child: Scaffold(body: Text('form')),
        ),
      );

      final navState = tester.state<NavigatorState>(find.byType(Navigator));
      // PopScope with canPop:false rejects maybePop synchronously but
      // fires onPopInvokedWithResult, which opens the dialog.
      // ignore: unawaited_futures
      navState.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      // Underlying form is still mounted behind the dialog.
      expect(find.text('form'), findsOneWidget);
    });

    testWidgets('cancel keeps user on the form', (tester) async {
      await _pumpFormRoute(
        tester,
        const DirtyFormScope(
          isDirty: true,
          child: Scaffold(body: Text('form')),
        ),
      );

      final navState = tester.state<NavigatorState>(find.byType(Navigator));
      // ignore: unawaited_futures
      navState.maybePop();
      await tester.pumpAndSettle();

      await _tapDialogAction(tester, 'Keep editing');

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('form'), findsOneWidget);
      expect(find.text('root'), findsNothing);
    });

    testWidgets('discard pops the underlying route', (tester) async {
      await _pumpFormRoute(
        tester,
        const DirtyFormScope(
          isDirty: true,
          child: Scaffold(body: Text('form')),
        ),
      );

      final navState = tester.state<NavigatorState>(find.byType(Navigator));
      // ignore: unawaited_futures
      navState.maybePop();
      await tester.pumpAndSettle();

      await _tapDialogAction(tester, 'Discard');
      // confirmAndPopIfDirty defers the actual pop to a post-frame
      // callback (skill §6 + crash-fix rationale in
      // dirty_form_scope.dart). Drain that frame before asserting.
      await tester.pumpAndSettle();

      expect(find.text('form'), findsNothing);
      expect(find.text('root'), findsOneWidget);
    });
  });

  group('DirtyFormScope.confirmAndPopIfDirty', () {
    testWidgets('clean: pops on next frame, no dialog', (tester) async {
      // Build a tiny screen whose chevron calls the helper. This
      // mirrors the production chevron path.
      await _pumpFormRoute(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () =>
                    DirtyFormScope.confirmAndPopIfDirty(ctx, false),
                child: const Text('back'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('back'));
      // Need an extra pump to drain the addPostFrameCallback that
      // defers the actual Navigator.pop.
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('back'), findsNothing);
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('dirty + discard: shows dialog then pops', (tester) async {
      await _pumpFormRoute(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () =>
                    DirtyFormScope.confirmAndPopIfDirty(ctx, true),
                child: const Text('back'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      await _tapDialogAction(tester, 'Discard');
      // Drain the post-frame pop scheduled by confirmAndPopIfDirty.
      await tester.pumpAndSettle();

      expect(find.text('back'), findsNothing);
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('dirty + cancel: dialog dismisses, route stays',
        (tester) async {
      await _pumpFormRoute(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () =>
                    DirtyFormScope.confirmAndPopIfDirty(ctx, true),
                child: const Text('back'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();
      await _tapDialogAction(tester, 'Keep editing');

      expect(find.text('back'), findsOneWidget);
      expect(find.text('root'), findsNothing);
    });
  });
}
