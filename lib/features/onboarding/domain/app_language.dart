/// Languages offered on the onboarding language-selection step.
///
/// Codes follow ISO 639-1 where available; local languages use best-match codes.
enum AppLanguage {
  english('en', 'English'),
  french('fr', 'Français');

  const AppLanguage(this.code, this.displayName);

  final String code;
  final String displayName;
}
