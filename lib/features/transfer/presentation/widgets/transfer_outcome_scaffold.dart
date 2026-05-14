import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Shared scaffold for the three terminal states of the Send Money
/// flow — success, pending, and failed.
///
/// Each state renders the same overall layout — brand gradient
/// background, centered ripple medallion, title + body, two stacked
/// CTAs at the bottom — and only differs in the medallion tint /
/// icon, the title + body copy, and the CTA pair. Pulling this into a
/// shared widget keeps the three screens visually consistent without
/// duplicating ~150 lines of boilerplate per file.
///
/// `body` is a `Widget` (not a `String`) so callers can use
/// `Text.rich` with inline-bold spans for amounts and recipient names
/// — matching the design mock.
class TransferOutcomeScaffold extends StatelessWidget {
  const TransferOutcomeScaffold({
    required this.glyphColor,
    required this.glyphIcon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.extras,
    super.key,
  });

  /// Fill color of the inner disc behind [glyphIcon] (e.g., green for
  /// success, amber for pending, red for failed). The two ripple rings
  /// stay neutral white-translucent regardless of state — only the
  /// disc carries the semantic color.
  final Color glyphColor;
  final IconData glyphIcon;

  final String title;
  final Widget body;

  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  /// Optional extras inserted between the body copy and the bottom
  /// CTA pair (e.g. the "Add to favourites" card on the success
  /// screen). Kept `Widget?` and slotted into the middle of the
  /// flexible space so the medallion + body and the CTAs keep their
  /// relative spacing on every screen size — when `null`, the layout
  /// matches the original three-screen mock exactly.
  final Widget? extras;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: DecoratedBox(
          // The brand gradient already fades into black on the lower
          // half — matching the mock without any extra overlays.
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  _OutcomeRipple(color: glyphColor, icon: glyphIcon),
                  const SizedBox(height: 36),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.sectionTitle,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: body,
                  ),
                  if (extras != null) ...[
                    const SizedBox(height: 24),
                    extras!,
                  ],
                  const Spacer(flex: 4),
                  _PrimaryCta(label: primaryLabel, onPressed: onPrimary),
                  const SizedBox(height: 12),
                  _SecondaryCta(label: secondaryLabel, onPressed: onSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Body copy with an inline-bold span — used by all three outcome
/// screens to call out the amount / recipient name in the middle of
/// otherwise-muted prose.
class TransferOutcomeBody extends StatelessWidget {
  const TransferOutcomeBody({required this.spans, super.key});

  /// Caller-supplied [TextSpan]s. Use [TransferOutcomeBody.bold] +
  /// [TransferOutcomeBody.muted] helpers to construct them with the
  /// shared base style.
  final List<InlineSpan> spans;

  /// Convenience: wrap [text] in the muted base style.
  static TextSpan muted(String text) => TextSpan(text: text);

  /// Convenience: wrap [text] in the bold-white inline style.
  static TextSpan bold(String text) => TextSpan(
    text: text,
    style: const TextStyle(
      color: AppColors.onBrand,
      fontWeight: FontWeight.w700,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: AppTextStyles.bodyMuted,
        children: spans,
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal subcomponents
// ---------------------------------------------------------------------------

/// Tinted disc + concentric ripple rings. Sized to match the design
/// mock: 88dp inner disc inside a 280dp outer ring.
class _OutcomeRipple extends StatelessWidget {
  const _OutcomeRipple({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _RippleRing(size: 280, alpha: 0.06),
          _RippleRing(size: 200, alpha: 0.10),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              icon,
              color: Colors.white,
              size: 44,
              weight: 700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RippleRing extends StatelessWidget {
  const _RippleRing({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: alpha),
          width: 1,
        ),
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: Colors.white,
        shape: const StadiumBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.pillLabel.copyWith(
                fontSize: 16,
                color: AppColors.actionPurple,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryCta extends StatelessWidget {
  const _SecondaryCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        // Dark translucent fill over the gradient — the lower half of
        // the screen is already black, so this reads as a near-black
        // pill with a faint white border, matching the mock.
        color: Colors.white.withValues(alpha: 0.06),
        shape: StadiumBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.18),
          ),
        ),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.listTitle,
            ),
          ),
        ),
      ),
    );
  }
}
