import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Dark translucent pill dropdown styled for the onboarding gradient.
class OnboardingDropdown<T> extends StatelessWidget {
  const OnboardingDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A0020),
          borderRadius: BorderRadius.circular(16),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.onBrand,
            size: 28,
          ),
          style: const TextStyle(
            color: AppColors.onBrand,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
