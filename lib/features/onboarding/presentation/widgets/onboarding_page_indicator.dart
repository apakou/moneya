import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Four-step page indicator for the onboarding PageView.
///
/// The active dot is rendered as a wider pill; the rest as small dots.
class OnboardingPageIndicator extends StatelessWidget {
  const OnboardingPageIndicator({
    super.key,
    required this.currentIndex,
    required this.count,
  });

  final int currentIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 6,
          width: isActive ? 28 : 6,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.onBrand
                : AppColors.onBrand.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
