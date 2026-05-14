import 'package:flutter/foundation.dart';

import '../../auth/domain/supported_country.dart';
import '../domain/favorite.dart';

/// In-memory store of saved recipients.
///
/// ## Why a singleton with no DI framework
///
/// The rest of MoneyA instantiates per-screen services
/// (`TransactionAuthService()`, `RecipientLookupService()`) because
/// they're stateless. Favourites are stateful (a mutable list)
/// shared across the Home strip, the Profile > Favourites screen,
/// and the Send-Money success prompt, so per-screen instances would
/// each get their own copy and never see writes from another
/// screen. Until we adopt Riverpod / GetX bindings properly, the
/// pragmatic solution is a process-wide singleton exposed through
/// [FavoritesService.instance]. Override [debugInstance] in tests
/// for isolation — see `favorites_service_test.dart`.
///
/// ## Reactivity
///
/// Extends [ChangeNotifier] so widgets can rebuild via
/// [ListenableBuilder]. The current snapshot is read through
/// [favorites] (returns a defensive unmodifiable view). Writes
/// always go through [add] / [remove] / [removeAt] so the notifier
/// fires exactly once per mutation.
///
/// ## Persistence (deliberate non-goal for v1)
///
/// The list lives in memory only. Cold-launching the app resets
/// it to [_seed]. When we land local persistence
/// (`SharedPreferences` or a small `Hive` box), swap the `_items`
/// field's initializer for an async load + populate. Public API
/// shouldn't change.
class FavoritesService extends ChangeNotifier {
  FavoritesService._() {
    _items.addAll(_seed);
  }

  /// Process-wide instance. Lazy so tests can override before the
  /// first read via [debugSetInstance].
  static FavoritesService _instance = FavoritesService._();

  /// Shared instance. Production code paths (Home, Profile,
  /// PaymentSuccess) read this; tests can swap it via
  /// [debugSetInstance].
  static FavoritesService get instance => _instance;

  /// Test-only seam. Replaces the singleton with a fresh service
  /// so each test starts from a known state. Call this in
  /// `setUp`; pair with [debugResetInstance] in `tearDown` if
  /// you want production data back.
  @visibleForTesting
  static void debugSetInstance(FavoritesService service) {
    _instance = service;
  }

  /// Test-only seam. Rebuilds the singleton from scratch, reseeded
  /// from [_seed]. Use in `tearDown` to undo a [debugSetInstance].
  @visibleForTesting
  static void debugResetInstance() {
    _instance = FavoritesService._();
  }

  /// Mutable backing list. Order is preserved: most-recently-added
  /// first (we [insert] at index 0 in [add]). Never expose this
  /// directly — callers read through [favorites] to prevent
  /// accidental writes that bypass the notifier.
  final List<Favorite> _items = <Favorite>[];

  /// Defensive read-only view of the current list. Order: newest
  /// first. Safe to use as a ListView source.
  List<Favorite> get favorites => List<Favorite>.unmodifiable(_items);

  /// True if `(country, nationalPhone)` is already a saved
  /// favourite, regardless of stored display name. Use from the
  /// success-screen prompt to decide whether to offer "Add to
  /// favourites" at all.
  bool contains(SupportedCountry country, String nationalPhone) {
    final key = '${country.isoCode}|$nationalPhone';
    return _items.any((f) => f.identityKey == key);
  }

  /// Add `recipient` as a favourite. Idempotent on identity: if
  /// `(country, nationalPhone)` is already present, the existing
  /// entry's [Favorite.displayName] is overwritten with the new
  /// `displayName` (so re-favouriting after a name correction in
  /// the directory lookup picks up the canonical name) but
  /// [Favorite.addedAt] is preserved so ordering stays stable.
  ///
  /// Returns the resulting [Favorite] — useful for tests and for
  /// surfacing "Added [name] to favourites" in a snackbar.
  Favorite add({
    required SupportedCountry country,
    required String nationalPhone,
    required String displayName,
    DateTime? now,
  }) {
    final addedAt = now ?? DateTime.now();
    final key = '${country.isoCode}|$nationalPhone';
    final existingIdx = _items.indexWhere((f) => f.identityKey == key);
    if (existingIdx != -1) {
      final existing = _items[existingIdx];
      final updated = existing.copyWith(displayName: displayName);
      _items[existingIdx] = updated;
      notifyListeners();
      return updated;
    }
    final fresh = Favorite(
      country: country,
      nationalPhone: nationalPhone,
      displayName: displayName,
      addedAt: addedAt,
    );
    _items.insert(0, fresh); // newest-first
    notifyListeners();
    return fresh;
  }

  /// Remove the favourite matching `(country, nationalPhone)`.
  /// Returns the removed [Favorite] (so callers can offer an Undo
  /// snackbar that re-inserts) or `null` if no match existed.
  Favorite? remove(SupportedCountry country, String nationalPhone) {
    final key = '${country.isoCode}|$nationalPhone';
    final idx = _items.indexWhere((f) => f.identityKey == key);
    if (idx == -1) return null;
    final removed = _items.removeAt(idx);
    notifyListeners();
    return removed;
  }

  /// Re-insert `favorite` at its original chronological position
  /// (sorted by [Favorite.addedAt] desc). Used by the Undo
  /// snackbar on the Favourites screen so a mistaken swipe-delete
  /// can be reversed without losing the favourite's original
  /// ordering relative to its neighbours.
  void restore(Favorite favorite) {
    // Insert at the first index whose addedAt is older than ours.
    final insertIdx = _items.indexWhere(
      (f) => f.addedAt.isBefore(favorite.addedAt),
    );
    if (insertIdx == -1) {
      _items.add(favorite);
    } else {
      _items.insert(insertIdx, favorite);
    }
    notifyListeners();
  }

  /// Seed favourites for v1. Matches the three mocks that were
  /// hardcoded in `home_screen.dart` before the favourites
  /// feature existed, so existing users see the same strip until
  /// they add their own. Phone numbers are intentionally chosen
  /// from the `RecipientLookupService` stub directory so tapping
  /// a seed favourite results in an immediate "Found" badge in
  /// the transfer screen.
  ///
  /// Once a real backend lands, drop this seed and load the
  /// user's saved recipients via the data layer.
  static List<Favorite> get _seed {
    // Fixed timestamps so seed ordering is deterministic on every
    // cold launch (newest-first within the seed group, then any
    // user-added favourites land in front of them).
    final base = DateTime(2024, 1, 1);
    return [
      Favorite(
        country: SupportedCountry.ivoryCoast,
        nationalPhone: '0598766265',
        displayName: 'Xavier Brahman',
        addedAt: base,
      ),
      Favorite(
        country: SupportedCountry.ivoryCoast,
        nationalPhone: '0598001234',
        displayName: 'Aminata Koffi',
        addedAt: base.subtract(const Duration(days: 1)),
      ),
      Favorite(
        country: SupportedCountry.ghana,
        nationalPhone: '0244112233',
        displayName: 'Kojo Mensah',
        addedAt: base.subtract(const Duration(days: 2)),
      ),
    ];
  }
}
