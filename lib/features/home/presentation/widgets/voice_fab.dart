import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The floating voice mic button that lives between the bottom-bar tabs.
///
/// This is the primary action of the app — users tap it and speak a
/// transfer intent (e.g., "send 5000 CFA to Maman by Wave"). It is
/// deliberately oversized and surrounded by a soft halo so that voice
/// is unmistakably the headline interaction. Wired to a stub callback
/// for now; the real implementation opens the voice intent capture
/// sheet (see voice-intent-parsing skill).
class VoiceFab extends StatelessWidget {
  const VoiceFab({required this.onPressed, super.key});

  final VoidCallback onPressed;

  // Outer halo size = button + breathing room so the dock notch reads
  // as an intentional pedestal rather than a clipped circle.
  static const double _buttonSize = 84;
  static const double _haloSize = 100;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _haloSize,
      height: _haloSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft outer halo — subtle white ring that lifts the button
          // away from the black bottom bar in any lighting.
          Container(
            width: _haloSize,
            height: _haloSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1,
              ),
              gradient: RadialGradient(
                colors: [
                  AppColors.actionPurple.withValues(alpha: 0.35),
                  AppColors.actionPurple.withValues(alpha: 0.0),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
          // The actual button.
          SizedBox(
            width: _buttonSize,
            height: _buttonSize,
            child: Material(
              color: AppColors.actionPurple,
              shape: const CircleBorder(),
              elevation: 12,
              shadowColor: AppColors.actionPurple.withValues(alpha: 0.75),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Slight top-light gradient so the button looks
                  // dimensional under the dark shell.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 2,
                  ),
                ),
                child: InkWell(
                  onTap: onPressed,
                  customBorder: const CircleBorder(),
                  splashColor: Colors.white.withValues(alpha: 0.20),
                  highlightColor: Colors.white.withValues(alpha: 0.08),
                  child: const Center(
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
