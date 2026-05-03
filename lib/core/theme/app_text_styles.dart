import 'package:flutter/material.dart';

import 'app_colors.dart';

/// MoneyA typography tokens.
///
/// All user-facing text should reference one of the named roles below.
/// This file is the single source of truth — do not re-declare
/// `TextStyle(fontSize:..., fontWeight:...)` in feature code.
///
/// ## Role hierarchy
///
/// ```
/// heroAmount      — 40–56sp w700, hero numerics (balance, signed amount)
/// hero            — 26–32sp w700, page-headline copy (auth titles)
/// screenTitle     — 17sp w600, the standard nav-header title
/// sectionTitle    — 22sp w700, in-page section headers
/// listTitle       — 16sp w600, list row titles & primary list copy
/// label           — 15sp w500, list rows / secondary labels
/// body            — 14sp w500, paragraph copy on dark surfaces
/// bodyMuted       — 14sp w500, supporting copy (uses onBrandSecondary)
/// caption         — 13sp w500, captions
/// captionMuted    — 13sp w500, captions on darker bg (onBrandSecondary)
/// micro           — 12sp w500, timestamps & micro-text
/// trackedLabel    — 12sp w600, uppercase letterSpaced section labels
/// ```
///
/// ## Why w500 instead of w400 on dark backgrounds
///
/// Per the readability skill, body text on the brand gradient bumps one
/// weight notch (w400 → w500) to compensate for the optical thinning that
/// occurs on dark backgrounds. The skill also requires explicit `height`
/// for line-height; defaults below are conservative and safe.
///
/// ## Numerics
///
/// Always use [numeric()] (or apply [tabular] yourself) on `Text` widgets
/// that display money, account numbers, phone numbers, percentages, or
/// dates. This prevents column shift while values change.
///
/// ## Hero amounts
///
/// Wrap hero amount widgets with [HeroTextScaleClamp] to cap Dynamic Type
/// at 1.3× — without this, very-large-text users will overflow the layout.
class AppTextStyles {
  const AppTextStyles._();

  // ---------------------------------------------------------------------------
  // FontFeature toggles
  // ---------------------------------------------------------------------------

  /// Tabular figures — apply to ALL numeric data (money, account numbers,
  /// phone numbers, percentages, dates). Prevents proportional digits from
  /// shifting columns as values change.
  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  // ---------------------------------------------------------------------------
  // Hero amounts (≥28sp numerics)
  // ---------------------------------------------------------------------------

  /// 56sp w700 — the keypad live amount (largest hero in the app).
  /// Used in [amount_keypad_sheet]. Wrap surrounding column with
  /// [HeroTextScaleClamp].
  static const TextStyle heroAmountKeypad = TextStyle(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    height: 1.0,
    color: AppColors.onBrand,
    fontFeatures: tabular,
  );

  /// 48sp w700 — home-balance and transfer-review hero amount.
  static const TextStyle heroAmount = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.0,
    color: AppColors.onBrand,
    fontFeatures: tabular,
  );

  /// 40sp w800 — receipt signed amount.
  static const TextStyle heroAmountReceipt = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -0.5,
    fontFeatures: tabular,
  );

  /// 32sp w700 — payment-confirm amount.
  static const TextStyle heroAmountConfirm = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.05,
    color: AppColors.onBrand,
    fontFeatures: tabular,
  );

  // ---------------------------------------------------------------------------
  // Hero (non-numeric headlines)
  // ---------------------------------------------------------------------------

  /// 28sp w700 — auth-flow page titles.
  static const TextStyle heroAuth = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.onBrand,
  );

  /// 26sp w700 — onboarding & KYC page titles.
  static const TextStyle heroOnboarding = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: AppColors.onBrand,
  );

  // ---------------------------------------------------------------------------
  // Section / Title roles
  // ---------------------------------------------------------------------------

  /// 22sp w700 — in-page section headers (page heading on tabs, outcome titles).
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.onBrand,
  );

  /// 18sp w600 — section sub-titles ("Quick send", "Recent transactions").
  static const TextStyle subsectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: AppColors.onBrand,
  );

  /// 17sp w600 — the standard nav-header title pattern.
  static const TextStyle screenTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
    color: AppColors.onBrand,
  );

  /// 16sp w600 — list row titles, primary list copy.
  static const TextStyle listTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.onBrand,
  );

  /// 16sp w700 — emphasized inline value (a name in a list row).
  static const TextStyle listTitleStrong = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.onBrand,
  );

  // ---------------------------------------------------------------------------
  // Sub-hero numerics (20–26sp) — between sectionTitle and hero
  // ---------------------------------------------------------------------------

  /// 26sp w700 tabular — large account-number / phone-number displays.
  /// Used on the Receive Account card. Below the 28sp hero floor so does
  /// NOT need [HeroTextScaleClamp]; but already wrapped in a local clamp
  /// at its call site to be safe.
  static const TextStyle subHeroNumeric = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: 1.2,
    color: AppColors.onBrand,
    fontFeatures: tabular,
  );

  /// 24sp w700 tabular — amount input field (Request tab) and similar
  /// sub-hero numeric inputs. Sized to remain readable while leaving room
  /// for a currency pill alongside it.
  static const TextStyle subHeroAmount = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: AppColors.onBrand,
    fontFeatures: tabular,
  );

  /// 20sp w700 — page-identity name (the user's full name on the Receive
  /// account card). Sits between subsectionTitle (18) and sectionTitle (22).
  static const TextStyle identityName = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.1,
    color: AppColors.onBrand,
  );

  // ---------------------------------------------------------------------------
  // Body / label roles
  // ---------------------------------------------------------------------------

  /// 15sp w500 — list row labels, secondary list copy.
  static const TextStyle label = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.onBrand,
  );

  /// 15sp w500 / 90% white — secondary list labels.
  static const TextStyle labelMuted = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.onBrandSecondary,
  );

  /// 14sp w500 — body copy on dark surfaces.
  ///
  /// Bumped from w400 (the spec) to w500 to compensate for optical
  /// thinning on the brand gradient — see skill §2 (weight ladder).
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.onBrand,
  );

  /// 14sp w500 / 90% white — supporting paragraph copy.
  static const TextStyle bodyMuted = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: AppColors.onBrandSecondary,
  );

  /// 14sp w600 — interactive link / inline action ("Resend code").
  static const TextStyle bodyLink = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.onBrand,
  );

  /// 14sp w700 — small action / pill label.
  static const TextStyle pillLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.onBrand,
    letterSpacing: 0.2,
  );

  /// 15sp w600 — pill CTA / action-row label (e.g. share, save, copy).
  /// Sits between [label] (w500) and [listTitle] (16sp w600).
  static const TextStyle actionLabel = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.2,
    color: AppColors.onBrand,
  );

  // ---------------------------------------------------------------------------
  // Caption / micro roles
  // ---------------------------------------------------------------------------

  /// 13sp w500 — captions, sub-row text, helper copy.
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.onBrand,
  );

  /// 13sp w500 / 90% white — muted caption.
  static const TextStyle captionMuted = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.onBrandSecondary,
  );

  /// 13sp w600 — emphasized caption (e.g. recipient-found row text,
  /// inline strong status copy).
  static const TextStyle captionStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.onBrand,
  );

  /// 14sp w500 / 55% white — group / section captions on dark surfaces
  /// ("Personal Informations", "Actions", "Security & Privacy").
  /// Lower-emphasis than [bodyMuted] (90%); use for section dividers.
  static const TextStyle sectionCaption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.35,
    letterSpacing: 0.2,
    color: AppColors.onBrandTertiary,
  );

  /// 14sp w400 / 75% white — read-only field values (Profile info-row),
  /// dialog body paragraphs. Lighter weight signals "data, not action".
  /// Apply [tabular] explicitly on numeric content.
  static const TextStyle dataValue = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.onBrandSecondary,
  );

  /// 14sp w400 / 70% white — onboarding & auth subtitle copy under the
  /// hero title ("We sent a 4-digit code to…", "Just enter your phone
  /// number to get started.", "Already have an account?"). Distinct from
  /// [bodyMuted] (w500 / 90%) — the lower weight + lower contrast keep
  /// it visually subordinate to the hero on a calmer pre-home surface.
  /// Still meets WCAG 2.2 AA at 14sp on the brand gradient.
  static const TextStyle bodyOnboardingMuted = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.onBrandMuted,
  );

  /// 16sp w400 / 70% white — auth-landing tagline / large marketing
  /// subtitle copy. One step up in size from [bodyOnboardingMuted].
  static const TextStyle taglineMuted = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0.2,
    color: AppColors.onBrandMuted,
  );

  /// 16sp w500 / onBrand — text-field input copy on the brand gradient.
  /// Use as the `style:` of `TextField`s; pair the `InputDecoration.hintStyle`
  /// with [bodyOnboardingMuted].copyWith(fontSize: 16) or [taglineMuted].
  static const TextStyle inputText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.onBrand,
  );

  /// 12sp w500 — timestamps and micro-text. Always paired with [tabular]
  /// when rendering numeric content.
  static const TextStyle micro = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.onBrandSecondary,
  );

  /// 12sp w500, tabular — timestamps with embedded digits.
  static const TextStyle microNumeric = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.onBrandSecondary,
    fontFeatures: tabular,
  );

  /// 12sp w600, uppercase tracked — section labels (FROM, AMOUNT,
  /// NOTE (OPTIONAL)).
  static const TextStyle trackedLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.8,
    color: AppColors.onBrandSecondary,
  );

  /// 11sp w700, uppercase tracked — micro-tag (e.g. transaction
  /// direction badge on the receipt).
  static const TextStyle microTag = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 1.4,
  );

  // ---------------------------------------------------------------------------
  // Convenience helpers
  // ---------------------------------------------------------------------------

  /// Apply tabular figures to any TextStyle.
  ///
  /// Use this when you need a one-off numeric variant of an existing role:
  ///
  /// ```dart
  /// AppTextStyles.numeric(AppTextStyles.listTitle)
  /// ```
  static TextStyle numeric(TextStyle base) =>
      base.copyWith(fontFeatures: tabular);
}

/// Wraps a hero amount widget so Dynamic Type cannot scale it past 1.3×.
///
/// Without this, users with the system text-size slider near max can
/// overflow hero amount layouts (the home balance, the keypad, the
/// payment-confirm amount). 1.3× preserves the readability win for
/// large-text users without breaking layout.
///
/// Apply ONLY to hero numerics — body text should NOT clamp.
///
/// ```dart
/// HeroTextScaleClamp(
///   child: Text(amount, style: AppTextStyles.heroAmount),
/// )
/// ```
class HeroTextScaleClamp extends StatelessWidget {
  const HeroTextScaleClamp({
    super.key,
    required this.child,
    this.maxScaleFactor = 1.3,
  });

  final Widget child;
  final double maxScaleFactor;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: maxScaleFactor),
      ),
      child: child,
    );
  }
}
