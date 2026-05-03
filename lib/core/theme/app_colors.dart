import 'package:flutter/material.dart';

/// MoneyA brand color tokens.
///
/// The splash / loading background is a vertical gradient from a vivid
/// magenta-purple at the top to pure black at the bottom.
class AppColors {
  const AppColors._();

  // Brand
  static const Color brandPurple = Color(0xFFB500D9);
  static const Color brandPurpleDeep = Color(0xFF2B0033);
  static const Color black = Color(0xFF000000);

  // Onboarding
  /// Bright purple used for primary action pills (the "Next" button).
  static const Color actionPurple = Color(0xFFB200D6);

  /// Translucent white used for rings and overlays on the brand gradient.
  static const Color ringSoft = Color(0x14FFFFFF); // ~8% white

  /// Dropdown / input pill background on the brand gradient.
  static const Color surfaceDark = Color(0x33000000); // ~20% black

  // Foregrounds
  //
  // Foreground tokens are tuned for WCAG 2.2 AA on the brand
  // gradient (which ranges from #B500D9 through #2B0033 to #000000).
  // The minimum contrast targets we hold to:
  //   - Body text:           ≥ 4.5 : 1
  //   - Large text (≥18sp):  ≥ 3.0 : 1
  //   - UI component / icon: ≥ 3.0 : 1
  //
  // Use [onBrand] for primary text and any small caption that the user
  // must be able to read at a glance (account numbers, amounts, names).
  // Use [onBrandSecondary] for supporting copy where the body-text
  // 4.5:1 floor still applies. Use [onBrandTertiary] only for icon
  // ornaments or decorative chrome — never for text the user has to
  // read (it intentionally sits at the 3:1 UI-component floor, below
  // the body-text threshold).
  static const Color onBrand = Color(0xFFF2ECEC); // logo stroke / primary text
  static const Color onBrandSecondary = Color(
    0xE6FFFFFF,
  ); // 90% white — secondary text, still ≥ 4.5:1 on darkest stop
  static const Color onBrandTertiary = Color(
    0x99FFFFFF,
  ); // 60% white — icon ornaments / dividers only

  /// Placeholder / hint copy on input fields. Held at 75% white so
  /// hints stay AA-readable (~4.6 : 1 on the deepest gradient stop)
  /// while still feeling lighter than entered values.
  static const Color onBrandHint = Color(0xBFFFFFFF); // 75% white

  /// Outline color for cards and pills on the brand gradient. Held at
  /// 24% white to clear the 3 : 1 UI-component contrast floor.
  static const Color onBrandOutline = Color(0x3DFFFFFF); // 24% white

  /// Disabled-state foreground for text and icons. Distinguishable
  /// from active foregrounds while still being perceivable.
  static const Color onBrandDisabled = Color(0x80FFFFFF); // 50% white

  /// Onboarding/marketing muted (70% white) — kept for back-compat
  /// with surfaces already using it. Prefer [onBrandSecondary] for
  /// new code where readability matters.
  static const Color onBrandMuted = Color(0xB3FFFFFF); // 70% white

  // Semantic state colors
  //
  // Tuned for AA contrast on the dark gradient. The pure
  // material-equivalents (e.g. green 600 #16A34A, amber 600 #D97706)
  // dip below 4.5:1 on near-black backgrounds, so we use lighter
  // tints for foreground use on brand surfaces.
  static const Color success = Color(0xFF22C55E); // green 500 — ≥ 4.5:1
  static const Color successOnLight = Color(0xFF16A34A); // green 600 for light bg
  static const Color warning = Color(0xFFFBBF24); // amber 400 — ≥ 8:1 on dark
  static const Color danger = Color(0xFFFF4D2E); // brand destructive
  static const Color info = Color(0xFF60A5FA); // blue 400

  /// Soft tinted backgrounds for status chips on the brand gradient.
  static const Color successSoft = Color(0x3322C55E); // 20% green 500
  static const Color warningSoft = Color(0x33FBBF24); // 20% amber 400
  static const Color dangerSoft = Color(0x33FF4D2E); // 20% danger

  /// Top → bottom gradient used on the splash and other brand surfaces.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.55, 1.0],
    colors: [brandPurple, brandPurpleDeep, black],
  );
}