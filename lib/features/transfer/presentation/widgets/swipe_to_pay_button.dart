import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// A horizontal "slide to confirm" control used on the payment confirm
/// screen.
///
/// The user drags the purple thumb (the [_Thumb]) from the left edge of
/// a white pill all the way to the right. Releases below
/// [completionThreshold] spring back to the start; releases at or above
/// the threshold lock to the end and call [onCompleted].
///
/// Hand-rolled rather than pulled from a package because:
/// * we want exact brand styling (purple thumb on white pill, purple
///   "Swipe to pay" text underneath);
/// * the entire screen lives over a brand gradient and our existing
///   theme tokens already cover the colors we need;
/// * the gesture logic is short — `onPanUpdate` to advance, `onPanEnd`
///   to spring back or settle.
///
/// Provides two haptics:
/// 1. `HapticFeedback.selectionClick` on drag start (feedback that the
///    thumb is "alive").
/// 2. `HapticFeedback.mediumImpact` when the swipe completes.
class SwipeToPayButton extends StatefulWidget {
  const SwipeToPayButton({
    required this.onCompleted,
    this.label = 'Swipe to pay',
    this.completionThreshold = 0.9,
    this.height = 64,
    this.width = double.infinity,
    super.key,
  });

  /// Called once the thumb crosses [completionThreshold] and the user
  /// releases. After firing, the thumb stays at the end position so the
  /// caller can show a loading / success state without the thumb
  /// snapping back.
  final VoidCallback onCompleted;

  /// Centered label on the pill. Faded out as the thumb advances so it
  /// doesn't compete visually with the thumb itself.
  final String label;

  /// Fraction of the track [0.0–1.0] that the thumb must reach for the
  /// swipe to be treated as confirmed on release.
  final double completionThreshold;

  /// Total pill height. Thumb diameter = [height] - 8 (4dp padding on
  /// each side).
  final double height;
  final double width;

  @override
  State<SwipeToPayButton> createState() => SwipeToPayButtonState();
}

class SwipeToPayButtonState extends State<SwipeToPayButton>
    with SingleTickerProviderStateMixin {
  /// Spring the thumb back to the start and clear the completed latch
  /// so the user can re-attempt the swipe (e.g. after step-up auth
  /// fails). Safe to call from outside via a `GlobalKey`.
  void reset() {
    if (!mounted) return;
    final from = _dragX;
    setState(() => _completed = false);
    if (from > 0) _springBackTo(from, 0);
  }

  /// Current thumb offset in logical pixels, from the left edge of the
  /// track to the left edge of the thumb.
  double _dragX = 0;

  /// Whether [SwipeToPayButton.onCompleted] has been fired. Prevents
  /// re-entry if the user keeps the finger pressed at the end.
  bool _completed = false;

  /// Spring-back animation controller. Eagerly created in
  /// [initState] (not `late final` lazy-init) because lazy
  /// initialization in [dispose] — i.e. the user navigates away
  /// without ever triggering a sub-threshold swipe — performs an
  /// inherited-widget lookup against a deactivated element through
  /// `SingleTickerProviderStateMixin.createTicker`'s `TickerMode.of`
  /// call, which throws "Looking up a deactivated widget's ancestor
  /// is unsafe" in debug and is undefined behavior in release.
  late final AnimationController _springController;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _springBackTo(double from, double to) {
    _springController.stop();
    _springController.value = 0;
    final tween = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic),
    );
    void listener() {
      setState(() => _dragX = tween.value);
    }

    tween.addListener(listener);
    _springController.forward().whenComplete(() {
      tween.removeListener(listener);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final thumbSize = widget.height - 8;
        final maxDrag = trackWidth - thumbSize - 8; // 4dp padding each side
        final progress = (maxDrag <= 0)
            ? 0.0
            : (_dragX / maxDrag).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            if (_completed) return;
            HapticFeedback.selectionClick();
          },
          onHorizontalDragUpdate: (details) {
            if (_completed) return;
            setState(() {
              _dragX = (_dragX + details.delta.dx).clamp(0.0, maxDrag);
            });
          },
          onHorizontalDragEnd: (_) {
            if (_completed) return;
            if (progress >= widget.completionThreshold) {
              // Lock at the end, fire the callback once.
              setState(() {
                _dragX = maxDrag;
                _completed = true;
              });
              HapticFeedback.mediumImpact();
              widget.onCompleted();
            } else {
              _springBackTo(_dragX, 0);
            }
          },
          child: Container(
            height: widget.height,
            width: widget.width,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(widget.height / 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Centered label, fades as the thumb advances.
                Opacity(
                  opacity: (1 - progress).clamp(0.0, 1.0),
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: AppColors.actionPurple,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Thumb, anchored to the left and translated by _dragX.
                Positioned(
                  left: 4 + _dragX,
                  top: 4,
                  child: _Thumb(size: thumbSize),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.actionPurple,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.arrow_forward_rounded,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}
