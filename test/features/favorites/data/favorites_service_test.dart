// Pure unit tests for [FavoritesService] — no widgets involved.
//
// Each test calls `debugResetInstance` in `setUp` to start from a
// fresh seeded singleton, so test ordering doesn't matter.

import 'package:flutter_test/flutter_test.dart';

import 'package:moneya/features/auth/domain/supported_country.dart';
import 'package:moneya/features/favorites/data/favorites_service.dart';

void main() {
  group('FavoritesService', () {
    setUp(() {
      FavoritesService.debugResetInstance();
    });

    test('starts from the 3-entry seed', () {
      expect(FavoritesService.instance.favorites.length, 3);
    });

    test('add inserts newest-first and bumps notifier', () {
      final svc = FavoritesService.instance;
      var notifyCount = 0;
      svc.addListener(() => notifyCount++);

      final added = svc.add(
        country: SupportedCountry.senegal,
        nationalPhone: '770000001',
        displayName: 'Ada Lovelace',
      );

      expect(svc.favorites.first, added);
      expect(svc.favorites.length, 4);
      expect(notifyCount, 1);
    });

    test('contains matches identity, ignores displayName', () {
      final svc = FavoritesService.instance;
      svc.add(
        country: SupportedCountry.senegal,
        nationalPhone: '770000001',
        displayName: 'Original Name',
      );
      expect(
        svc.contains(SupportedCountry.senegal, '770000001'),
        isTrue,
      );
      expect(
        svc.contains(SupportedCountry.senegal, '770000002'),
        isFalse,
      );
    });

    test('add is idempotent on identity and preserves addedAt', () {
      final svc = FavoritesService.instance;
      final ts = DateTime(2025, 1, 1, 9);
      svc.add(
        country: SupportedCountry.senegal,
        nationalPhone: '770000001',
        displayName: 'First Name',
        now: ts,
      );
      // Re-adding the same identity with a different name must
      // overwrite displayName but keep addedAt — so ordering doesn't
      // shuffle just because the user re-favourited a contact.
      final reAdded = svc.add(
        country: SupportedCountry.senegal,
        nationalPhone: '770000001',
        displayName: 'Canonical Name',
        now: DateTime(2025, 6, 1),
      );

      expect(svc.favorites.length, 4); // 3 seed + 1 (no dup)
      expect(reAdded.displayName, 'Canonical Name');
      expect(reAdded.addedAt, ts);
    });

    test('remove deletes and returns the favourite; nop returns null', () {
      final svc = FavoritesService.instance;
      svc.add(
        country: SupportedCountry.senegal,
        nationalPhone: '770000001',
        displayName: 'Ada',
      );
      final removed = svc.remove(SupportedCountry.senegal, '770000001');
      expect(removed, isNotNull);
      expect(removed!.displayName, 'Ada');
      expect(svc.contains(SupportedCountry.senegal, '770000001'), isFalse);

      // Removing the same identity again should be a no-op returning null.
      final twice = svc.remove(SupportedCountry.senegal, '770000001');
      expect(twice, isNull);
    });

    test('restore re-inserts at the original chronological slot', () {
      final svc = FavoritesService.instance;
      // The 3 seed entries have addedAt 2024-01-01, 2023-12-31,
      // 2023-12-30 (descending). Insert "Middle" with a timestamp
      // that falls between seed[0] and seed[1], then remove and
      // restore — it should land at index 1.
      final middle = svc.add(
        country: SupportedCountry.senegal,
        nationalPhone: '770000001',
        displayName: 'Middle',
        now: DateTime(2023, 12, 31, 12),
      );
      // add() always inserts at the head regardless of timestamp —
      // that's the spec for "newest user action shows first".
      expect(svc.favorites.first, middle);

      final removed = svc.remove(middle.country, middle.nationalPhone);
      expect(removed, isNotNull);

      svc.restore(removed!);
      // restore() respects chronology and slots into the correct
      // historical position.
      expect(svc.favorites[1].identityKey, removed.identityKey);
    });
  });
}
