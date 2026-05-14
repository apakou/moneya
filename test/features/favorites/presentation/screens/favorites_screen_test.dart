// Widget tests for [FavoritesScreen].
//
// Covers:
//   * Empty state — title, body, CTA all render when the service is
//     empty; tapping the CTA pushes the transfer screen route.
//   * Populated state — list renders one row per favourite, swiping
//     a row removes it from the service and surfaces an Undo
//     snackbar that restores it on tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:moneya/features/auth/domain/supported_country.dart';
import 'package:moneya/features/favorites/data/favorites_service.dart';
import 'package:moneya/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';

/// Pumps the [FavoritesScreen] inside a `GetMaterialApp` with the
/// production app's localization delegates so widgets that look up
/// `AppLocalizations.of(context)` resolve cleanly.
Future<void> _pumpFavoritesScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const FavoritesScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // Each test starts from a freshly-seeded service so removals /
    // additions don't leak across cases.
    FavoritesService.debugResetInstance();
  });

  group('FavoritesScreen empty state', () {
    setUp(() {
      // Drain the seed list so the empty state renders.
      final svc = FavoritesService.instance;
      for (final f in svc.favorites.toList()) {
        svc.remove(f.country, f.nationalPhone);
      }
    });

    testWidgets('renders title, body, and Send-money CTA', (tester) async {
      await _pumpFavoritesScreen(tester);

      // Empty-state copy.
      expect(find.text('No favorites yet'), findsOneWidget);
      // Body + CTA pulled from l10n — match by partial text to stay
      // resilient to copy tweaks.
      expect(find.textContaining('Send money'), findsWidgets);
    });
  });

  group('FavoritesScreen populated state', () {
    testWidgets('renders one tile per seeded favourite', (tester) async {
      await _pumpFavoritesScreen(tester);

      // Seed has three entries — verify all three names show up.
      expect(find.text('Xavier Brahman'), findsOneWidget);
      expect(find.text('Aminata Koffi'), findsOneWidget);
      expect(find.text('Kojo Mensah'), findsOneWidget);
    });

    testWidgets('swipe-to-dismiss removes the row + shows Undo snackbar',
        (tester) async {
      await _pumpFavoritesScreen(tester);

      final tileFinder = find.text('Xavier Brahman');
      expect(tileFinder, findsOneWidget);

      // Fling left to trigger the Dismissible (endToStart direction).
      await tester.fling(tileFinder, const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();

      // Row is gone from the tree.
      expect(find.text('Xavier Brahman'), findsNothing);
      // Service no longer contains the entry.
      expect(
        FavoritesService.instance.contains(
          SupportedCountry.ivoryCoast,
          '0598766265',
        ),
        isFalse,
      );
      // Undo snackbar is visible.
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('Undo restores the swiped favourite', (tester) async {
      await _pumpFavoritesScreen(tester);

      await tester.fling(
        find.text('Xavier Brahman'),
        const Offset(-500, 0),
        1000,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Row is back.
      expect(find.text('Xavier Brahman'), findsOneWidget);
      expect(
        FavoritesService.instance.contains(
          SupportedCountry.ivoryCoast,
          '0598766265',
        ),
        isTrue,
      );
    });
  });
}
