// Smoke test: verify the app boots to a Scaffold.
//
// Replace with proper feature-level widget tests once Riverpod +
// freezed migration lands and we have testable view-models.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moneya/core/locale/locale_controller.dart';
import 'package:moneya/main.dart';

void main() {
  testWidgets('App boots to a Scaffold', (tester) async {
    // LocaleController is normally hydrated from SharedPreferences in
    // main(). The default constructor is sufficient for a smoke test
    // — no persisted locale read happens unless we call load().
    await tester.pumpWidget(
      MoneyaApp(localeController: LocaleController()),
    );
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
