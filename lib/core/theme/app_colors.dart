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
  static const Color onBrand = Color(0xFFF2ECEC); // logo stroke / text on brand
  static const Color onBrandMuted = Color(0xB3FFFFFF); // 70% white

  /// Top → bottom gradient used on the splash and other brand surfaces.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.55, 1.0],
    colors: [brandPurple, brandPurpleDeep, black],
  );
}