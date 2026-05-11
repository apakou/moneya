import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A tap-to-pop back affordance that does **not** crash with the
/// "Looking up a deactivated widget's ancestor is unsafe" error when
/// it pops the current route synchronously.
///
/// ## Why this exists (don't remove without reading)
///
/// `IconButton` wraps its tap target in an [InkResponse] which
/// schedules a ripple animation on every press. When the `onPressed`
/// callback synchronously calls `Navigator.pop()` /
/// `Navigator.maybePop()`, the route's element tree is **deactivated
/// before the ripple finishes**. The ripple's animation tick then
/// performs an inherited-widget lookup against `Material.of(context)`
/// on the deactivated element, which throws.
///
/// Reproduction: every header chevron / back button on every screen
/// that pops a route fires this on tap → previously affected the
/// Receive screen + the edit-pencil on the payment-confirm screen.
///
/// ## What this widget does instead
///
/// Replaces the `IconButton` + `InkResponse` chain with a plain
/// [GestureDetector] (no ripple, no post-tap inherited lookups),
/// wrapped in [Tooltip] (long-press hint for sighted users) and
/// [Semantics] (`button: true` + label so screen readers announce
/// "Go back, button"). The hit-test target stays at 48×48 to keep the
/// WCAG 2.2 motor-accessibility tap-target floor.
///
/// Use this for **every** back chevron / back arrow in the app.
class BackChevronButton extends StatelessWidget {
  const BackChevronButton({
    required this.onTap,
    required this.tooltip,
    this.icon = Icons.chevron_left_rounded,
    this.iconSize = 28,
    this.color = AppColors.onBrand,
    super.key,
  });

  /// Tap callback — typically `() => Navigator.of(context).maybePop()`
  /// or a passed-in `onBack`.
  final VoidCallback onTap;

  /// Tooltip + screen-reader label. Should be the localized "Back"
  /// string (e.g. `l10n.commonBack`).
  final String tooltip;

  /// Defaults to [Icons.chevron_left_rounded] (used by Home, Transfer,
  /// PaymentConfirm, TransactionDetail, Profile, Settings, Receive).
  /// Pass [Icons.arrow_back_ios_new_rounded] for the auth/KYC chain.
  final IconData icon;

  /// Visual icon size. Tap target is always 48×48 regardless of this
  /// value; only the rendered glyph scales.
  final double iconSize;

  /// Glyph color. Defaults to [AppColors.onBrand] so the button reads
  /// against the brand-gradient header.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
      ),
    );
  }
}
