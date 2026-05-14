import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Width-driven value interpolation utilities.
///
/// The single most common responsive bug in a Flutter codebase is
/// writing `MediaQuery.sizeOf(context).width * 0.82` for a hero
/// graphic that "looks right on my phone": on a 360dp Tecno that's
/// 295dp, on a 430dp iPhone Pro Max it's 353dp, and on an 884dp
/// unfolded Galaxy Z Fold it's 725dp — which paints a logo that
/// occupies most of the screen. Pure-percentage sizing has no
/// concept of "this should never be bigger than X" or "this should
/// stop growing past size class Y".
///
/// [ResponsiveScale] solves this by interpolating a value between
/// **two anchor widths**, with optional hard clamps on either end.
/// You declare the design intent ("this hero is 100dp on a 360dp
/// phone, 160dp on a 600dp tablet — and never larger than 200dp no
/// matter what") and the helper handles the arithmetic.
///
/// Why not just use [LayoutBuilder]?
///   [LayoutBuilder] gives you the parent constraint, not the
///   viewport width. For elements that should scale with the
///   **device** (hero graphics, page padding, font sizes) the
///   viewport is the right reference. Use [LayoutBuilder] for
///   elements that should scale with their **container**
///   (responsive cards inside a grid, list cells inside a pane).
class ResponsiveScale {
  ResponsiveScale._();

  /// Linearly interpolate a value between [minValue] (at
  /// [minWidth]) and [maxValue] (at [maxWidth]), clamped to
  /// `[minValue, maxValue]` outside that range.
  ///
  /// Example: a 100→160dp hero that scales between phones and
  /// small tablets, clamped at both ends so a foldable doesn't
  /// blow it up:
  ///
  /// ```dart
  /// final heroSize = ResponsiveScale.lerp(
  ///   context: context,
  ///   minWidth: 360,
  ///   maxWidth: 600,
  ///   minValue: 100,
  ///   maxValue: 160,
  /// );
  /// ```
  ///
  /// The clamp is intentional and non-optional: unbounded scaling
  /// is the source of the "looks fine on phone, ridiculous on
  /// tablet" bug class. If you genuinely want unbounded scaling
  /// (rare; usually wrong) just pass extreme anchor widths.
  static double lerp({
    required BuildContext context,
    required double minWidth,
    required double maxWidth,
    required double minValue,
    required double maxValue,
  }) {
    assert(
      minWidth < maxWidth,
      'minWidth ($minWidth) must be < maxWidth ($maxWidth)',
    );
    final w = MediaQuery.sizeOf(context).width;
    if (w <= minWidth) return minValue;
    if (w >= maxWidth) return maxValue;
    final t = (w - minWidth) / (maxWidth - minWidth);
    return minValue + (maxValue - minValue) * t;
  }

  /// Pick a value by discrete [ScreenSize]. Use when the value
  /// should jump (not interpolate) at breakpoints — e.g. number
  /// of columns in a grid, gutter padding that should be a clean
  /// integer, font sizes from the design system.
  ///
  /// [compact] is required (it's the base case for phones, which
  /// is what every screen has to support). The other size classes
  /// fall through to the next-smaller value if not specified, so
  /// you only declare the sizes that actually differ:
  ///
  /// ```dart
  /// // 24dp gutter on phones, 32dp on tablets+
  /// final gutter = ResponsiveScale.pick(
  ///   context: context,
  ///   compact: 24,
  ///   expanded: 32,
  /// );
  /// ```
  ///
  /// The fallthrough rule ("medium uses compact if omitted, large
  /// uses expanded if omitted") matches Material's own size-class
  /// behavior and means call sites stay terse.
  static T pick<T>({
    required BuildContext context,
    required T compact,
    T? medium,
    T? expanded,
    T? large,
  }) {
    switch (MediaQuery.sizeOf(context).width) {
      case final w when w < Breakpoints.compactMax:
        return compact;
      case final w when w < Breakpoints.mediumMax:
        return medium ?? compact;
      case final w when w < Breakpoints.expandedMax:
        return expanded ?? medium ?? compact;
      default:
        return large ?? expanded ?? medium ?? compact;
    }
  }

  /// Compute a horizontal gutter (page edge padding) appropriate
  /// for the current viewport. Returns the canonical MoneyA
  /// gutter: 24dp on phones, 32dp on tablets, 48dp on desktop.
  ///
  /// Centralizing this means every screen says
  /// `padding: EdgeInsets.symmetric(horizontal: context.gutter)`
  /// instead of hardcoding `24` everywhere, and we can adjust the
  /// whole app's breathing room in one place.
  static double gutter(BuildContext context) => pick<double>(
        context: context,
        compact: 24,
        expanded: 32,
        large: 48,
      );

  /// Compute a square side length for a hero/illustration that
  /// must fit in both axes — scales with viewport width (via the
  /// same [lerp] contract) but is additionally capped at a
  /// fraction of the viewport **height**, so the hero never
  /// pushes its sibling text off the bottom of a short screen.
  ///
  /// This is the canonical sizing pattern for an onboarding /
  /// empty-state / outcome-screen illustration: the design is
  /// drawn for a 360×800 phone, but on a 360×640 device (Tecno,
  /// Itel, older Samsung A-series — explicit MoneyA target market)
  /// a purely width-driven hero would crowd the headline.
  ///
  /// Example: a 295→440dp hero that scales with width but never
  /// occupies more than 38% of viewport height:
  ///
  /// ```dart
  /// final heroSide = ResponsiveScale.clampSquare(
  ///   context: context,
  ///   minWidth: 360,
  ///   maxWidth: 600,
  ///   minValue: 295,
  ///   maxValue: 440,
  ///   maxHeightFraction: 0.38,
  /// );
  /// ```
  ///
  /// [maxHeightFraction] defaults to 0.40 — chosen as the cutoff
  /// below which a sibling headline + page chrome reliably fit
  /// on a 640dp viewport with FR text (which wraps to 3 lines).
  static double clampSquare({
    required BuildContext context,
    required double minWidth,
    required double maxWidth,
    required double minValue,
    required double maxValue,
    double maxHeightFraction = 0.40,
  }) {
    assert(
      maxHeightFraction > 0 && maxHeightFraction <= 1,
      'maxHeightFraction must be in (0, 1]',
    );
    final widthDriven = lerp(
      context: context,
      minWidth: minWidth,
      maxWidth: maxWidth,
      minValue: minValue,
      maxValue: maxValue,
    );
    final heightCap = MediaQuery.sizeOf(context).height * maxHeightFraction;
    return math.min(widthDriven, heightCap);
  }
}

/// Tap-target floors per WCAG 2.2 / Material / iOS HIG. Centralized
/// so we never accidentally drop below them in custom controls.
///
/// These are minimums; design tokens may sit above them (MoneyA
/// home action buttons are 56dp, not 44dp). The constants exist
/// for **defensive `assert`s** in custom widgets, not for general
/// sizing.
class TapTargets {
  TapTargets._();

  /// WCAG 2.2 SC 2.5.8 minimum — the absolute floor. Below this
  /// the app fails accessibility audits and motor-impaired users
  /// struggle to land on the target.
  static const double wcagMinimum = 24;

  /// iOS HIG recommended minimum — the "accessible" floor most
  /// fintech apps use as their design constraint.
  static const double iosRecommended = 44;

  /// Material 3 / Android recommended minimum.
  static const double androidRecommended = 48;
}
