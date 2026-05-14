import 'package:flutter/material.dart';

/// Named layout breakpoints used throughout MoneyA.
///
/// The thresholds follow Material 3's window size class spec
/// (https://m3.material.io/foundations/layout/applying-layout/window-size-classes),
/// which is the same system Wise, Revolut, and N26 use internally.
/// Picking the same numbers as the industry standard means:
///
///   1. Any third-party Flutter widget that respects window size
///      classes (or any future Material widget that does) will
///      agree with our layout decisions.
///   2. When the user resizes the OS task-switcher panel on Android
///      or rotates a foldable, our breakpoint transitions happen at
///      the same width as the system chrome itself transitions —
///      no visible jank zone.
///
/// We deliberately do NOT define breakpoints in terms of device
/// classes ("phone", "tablet"). A modern Android phone in split-
/// screen mode can be 320dp wide; a Galaxy Z Fold unfolded is 884dp
/// — neither matches the "phone vs tablet" mental model. Always
/// branch on the breakpoint, never on `Platform.isAndroid` or
/// physical screen size.
class Breakpoints {
  Breakpoints._();

  /// Below this width the layout is compact: single column, dense
  /// padding, mobile-optimized. Most phones in portrait fall here.
  ///
  /// 600 is the M3 cutoff between "Compact" and "Medium". Below 600
  /// you have ~360 (Pixel 6a), ~390 (iPhone 14), ~414 (iPhone Plus),
  /// ~430 (iPhone Pro Max). The 360–430 range is what MoneyA's v1
  /// phone audience overwhelmingly uses.
  static const double compactMax = 600;

  /// 600–840: medium window. Phones in landscape, small tablets
  /// (iPad mini portrait ≈ 744), foldables half-unfolded. The
  /// "expanded but not full tablet" zone.
  static const double mediumMax = 840;

  /// 840–1200: expanded window. iPad portrait, most Android tablets,
  /// foldables fully unfolded. Where we'd introduce 2-pane layouts.
  static const double expandedMax = 1200;

  /// 1200+: large window. iPad Pro landscape, ChromeOS, desktop
  /// Flutter targets. Not in scope for MoneyA v1 but the class
  /// exists so we don't have to refactor when we get there.
}

/// Discrete window size class, derived from the current viewport
/// width. Cheaper to compare than raw doubles and immune to off-by-
/// one boundary bugs.
///
/// Compare with `==` against the enum values; do NOT compare ordinal
/// indices (`>` / `<`) — semantic ordering is intentional but
/// ordinal arithmetic is a code smell that will trip you up the day
/// we add a new size between two existing ones.
enum ScreenSize {
  /// `width < 600` — phones in portrait, narrow split-screen windows.
  compact,

  /// `600 <= width < 840` — phones in landscape, small tablets in
  /// portrait, foldables half-unfolded.
  medium,

  /// `840 <= width < 1200` — tablets in portrait, foldables fully
  /// unfolded. Two-pane layouts unlock here.
  expanded,

  /// `width >= 1200` — tablets in landscape, ChromeOS, desktop.
  large;

  /// Convenience: "is this size class smaller than [other]?".
  ///
  /// Reads better at call sites than comparing the enum ordinals
  /// directly (`ScreenSize.compact.index < ScreenSize.medium.index`)
  /// without losing the type-safety the enum gives us.
  bool isSmallerThan(ScreenSize other) => index < other.index;

  /// Convenience: "is this size class at least [other]?".
  bool isAtLeast(ScreenSize other) => index >= other.index;
}

/// Responsive helpers attached to [BuildContext] so screens can write
/// `context.screenSize` / `context.isTablet` without bringing in a
/// helper class import on every file.
///
/// All getters read [MediaQuery] via `MediaQuery.sizeOf` /
/// `MediaQuery.orientationOf` (the new partial-subscription APIs) so
/// the caller only rebuilds when the relevant axis changes —
/// rotating the device does NOT rebuild a widget that only reads
/// `context.screenSize` if the size class itself didn't cross a
/// breakpoint.
extension ResponsiveContext on BuildContext {
  /// Current viewport width in logical pixels. Equivalent to
  /// `MediaQuery.sizeOf(this).width` but more concise at call sites.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Current viewport height in logical pixels.
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Discrete window size class for the current viewport width.
  ///
  /// Prefer this over comparing `screenWidth` to magic numbers at
  /// the call site — it makes layout intent explicit and centralizes
  /// the thresholds so we can adjust them in one place.
  ScreenSize get screenSize {
    final w = screenWidth;
    if (w < Breakpoints.compactMax) return ScreenSize.compact;
    if (w < Breakpoints.mediumMax) return ScreenSize.medium;
    if (w < Breakpoints.expandedMax) return ScreenSize.expanded;
    return ScreenSize.large;
  }

  /// `true` when the viewport is at least [ScreenSize.expanded] —
  /// i.e. we're on a tablet, foldable, or desktop window large
  /// enough to host a two-pane layout.
  ///
  /// "Tablet" here is a UX intent, not a device-class assertion: a
  /// phone in landscape split-screen never crosses this threshold,
  /// which is the correct behavior. We use this getter to decide
  /// whether to show master-detail vs single-column UI.
  bool get isTablet => screenSize.isAtLeast(ScreenSize.expanded);

  /// `true` when the viewport is in landscape orientation. Reads
  /// `MediaQuery.orientationOf` so the widget only rebuilds on
  /// orientation flip, not on every resize.
  ///
  /// Note: at the app level we lock phones to portrait via
  /// [SystemChrome.setPreferredOrientations] in `main()`. This
  /// getter therefore only ever returns `true` on tablets/foldables
  /// — but the call site shouldn't assume that; rely on the value,
  /// not the policy.
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;
}
