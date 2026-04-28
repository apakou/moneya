import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The floating voice mic button that lives between the bottom-bar tabs.
///
/// This is the primary action of the app — users tap it and speak a
/// transfer intent (e.g., "send 5000 CFA to Maman by Wave"). For now it
/// is wired to a stub callback.
class VoiceFab extends StatelessWidget {
  const VoiceFab({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Material(
        color: AppColors.actionPurple,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: AppColors.actionPurple.withValues(alpha: 0.55),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: const Center(
            child: Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
