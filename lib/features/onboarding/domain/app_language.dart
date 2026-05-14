import '../../../core/locale/locale_controller.dart';

/// Languages offered on the onboarding language-selection step.
///
/// Codes follow ISO 639-1 where available; local languages use best-match codes.
///
/// Note: language **display names** (endonyms) for the picker UI live
/// in the localization catalog (`languageEnglish` / `languageFrench`
/// keys in the ARB files), not on this enum. That lets translators
/// adjust spelling/punctuation without a code change while still
/// guaranteeing every speaker sees their own language in its own name.
enum AppLanguage {
  english('en'),
  french('fr');

  const AppLanguage(this.code);

  /// BCP-47 language subtag used for mapping to [AppLocale] and for
  /// any future analytics/server payloads.
  final String code;

  /// The app-wide [AppLocale] this language corresponds to. Used by
  /// the onboarding step 1 picker to actually switch the UI locale
  /// when the user makes a selection.
  AppLocale get appLocale {
    switch (this) {
      case AppLanguage.english:
        return AppLocale.en;
      case AppLanguage.french:
        return AppLocale.fr;
    }
  }

  /// Inverse of [appLocale] — used to seed the onboarding picker
  /// from the currently active app locale so the dropdown reflects
  /// reality on entry (e.g. user previously chose French → comes
  /// back through onboarding via dev-bypass → picker shows Français).
  static AppLanguage fromAppLocale(AppLocale locale) {
    switch (locale) {
      case AppLocale.en:
        return AppLanguage.english;
      case AppLocale.fr:
        return AppLanguage.french;
    }
  }
}
