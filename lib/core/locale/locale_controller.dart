import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';

/// Locales the app currently ships translations for.
///
/// Order matters for the language picker UI (English first because the
/// brand surface is English-leaning today; French is the only other
/// fully-translated locale at v1 launch). Adding a new locale = add an
/// `app_<code>.arb` file under `lib/l10n/` and a new entry here.
enum AppLocale {
  en(Locale('en')),
  fr(Locale('fr'));

  const AppLocale(this.locale);

  /// Flutter [Locale] used by `MaterialApp.locale` and the i18n
  /// delegate machinery.
  final Locale locale;

  /// BCP-47 language tag persisted to disk.
  String get tag => locale.toLanguageTag();

  static AppLocale fromTag(String? tag) {
    return AppLocale.values.firstWhere(
      (l) => l.tag == tag,
      // Default to English when no preference has been persisted yet,
      // when the persisted value points at a locale we no longer
      // ship, or when the device locale is not one we translate.
      orElse: () => AppLocale.en,
    );
  }
}

/// App-wide active locale, lifted out of any single screen so every
/// `MaterialApp.locale`-bound widget relocalizes when the user toggles.
///
/// Persists to `SharedPreferences` under [_prefsKey] so the choice
/// survives a cold start. Reads on construction are async — call
/// [load] from `main()` before `runApp` to avoid a one-frame
/// English flash on launch.
class LocaleController extends ChangeNotifier {
  LocaleController({AppLocale initial = AppLocale.en}) : _current = initial;

  static const String _prefsKey = 'moneya.locale.tag';

  AppLocale _current;
  AppLocale get current => _current;

  /// Hydrate from `SharedPreferences`. Safe to call multiple times;
  /// only emits a notification if the persisted locale differs from
  /// the current in-memory value.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tag = prefs.getString(_prefsKey);
      final next = AppLocale.fromTag(tag);
      if (next != _current) {
        _current = next;
        notifyListeners();
      }
    } catch (e, st) {
      // Storage failure must not crash startup — fall back silently.
      AppLogger.w('locale.load.failed', const {}, e, st);
    }
  }

  /// Switch the active locale and persist the choice. Safe to call on
  /// the same value (no-op + no notification).
  Future<void> setLocale(AppLocale next) async {
    if (next == _current) return;
    _current = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.tag);
    } catch (e, st) {
      // Persistence failure is non-fatal — the in-memory switch
      // already happened and the user sees the new language. We just
      // won't remember it on next launch.
      AppLogger.w('locale.persist.failed', {'tag': next.tag}, e, st);
    }
  }

  /// Convenience toggle — flips between the two shipped locales.
  /// Replace with a real picker once we ship more than two languages.
  Future<void> toggle() async {
    final next = _current == AppLocale.en ? AppLocale.fr : AppLocale.en;
    await setLocale(next);
  }
}
