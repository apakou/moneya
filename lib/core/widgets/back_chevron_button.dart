import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

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
    required this.tooltip,
    this.onTap,
    this.icon = Icons.chevron_left_rounded,
    this.iconSize = 28,
    this.color = AppColors.onBrand,
    super.key,
  });

  /// Tap callback. When `null`, defaults to `Get.back()` so the
  /// chevron Just Works on any screen whose only back behaviour is
  /// "pop the route". GetX is the canonical navigator across the
  /// app (`Get.to`, `Get.off`, `Get.offAll`); using `Get.back()`
  /// here keeps GetX's internal route accounting in sync.
  /// `Get.back()` is a no-op when there's nothing to pop, so the
  /// chevron is safe to render even on the very first route of a
  /// cold-start deep-link.
  ///
  /// Pass a non-null callback when the screen needs to run extra
  /// logic before popping (e.g. unfocus the keyboard, prompt
  /// discard-changes via `DirtyFormScope`). See the
  /// `flutter-navigation` skill §6 for the rationale.
  final VoidCallback? onTap;

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
          // Defer the tap callback to the next frame.
          //
          // The `Tooltip` ancestor registers a post-tap timer that
          // performs an inherited-widget lookup (`Overlay.of(context)`)
          // to dismiss its long-press hint. When `onTap` synchronously
          // pops the route, that lookup runs against a deactivated
          // element and throws "Looking up a deactivated widget's
          // ancestor is unsafe".
          //
          // The `Semantics` and `GestureDetector` themselves don't
          // touch inherited widgets post-tap — only `Tooltip` does —
          // but every back chevron in the app is wrapped in this
          // tooltip for hover/long-press a11y, so the defer must live
          // here, not at the call sites. A single-frame delay is
          // visually indistinguishable from a synchronous pop.
          onTap: () => SchedulerBinding.instance.addPostFrameCallback((_) {
            final cb = onTap;
            if (cb != null) {
              cb();
            } else {
              // `Get.back()` is a no-op when nothing is poppable —
              // safe even on the first route of a cold-start deep
              // link. See [onTap] doc for why we don't use
              // `Navigator.of(context).pop()` here.
              Get.back<void>();
            }
          }),
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
