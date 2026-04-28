import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/supported_currency.dart';

/// Modal bottom sheet listing the currencies the user can switch to on
/// the home dashboard.
///
/// Returns the chosen [SupportedCurrency] via `Navigator.pop`, or `null`
/// if the user dismisses the sheet without making a selection.
///
/// Usage:
///   ```dart
///   final picked = await showCurrencyPickerSheet(
///     context: context,
///     selected: _currency,
///   );
///   ```
Future<SupportedCurrency?> showCurrencyPickerSheet({
  required BuildContext context,
  required SupportedCurrency selected,
}) {
  return showModalBottomSheet<SupportedCurrency>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _CurrencyPickerSheet(selected: selected),
  );
}

class _CurrencyPickerSheet extends StatelessWidget {
  const _CurrencyPickerSheet({required this.selected});

  final SupportedCurrency selected;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SafeArea(
      top: false,
      // Constrain height so on small phones the sheet doesn't try to
      // grow past the available space; on tall phones we cap it at 70%.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.70),
        child: Container(
          decoration: const BoxDecoration(
            // Slightly lighter than pure black so the sheet reads as a
            // distinct surface against the brand-gradient background.
            color: Color(0xFF1A0220),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: Color(0x33FFFFFF), width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // Drag handle.
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select currency',
                    style: TextStyle(
                      color: AppColors.onBrand,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: SupportedCurrency.values.length,
                  itemBuilder: (context, i) {
                    final c = SupportedCurrency.values[i];
                    return _CurrencyRow(
                      currency: c,
                      isSelected: c == selected,
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.currency,
    required this.isSelected,
    required this.onTap,
  });

  final SupportedCurrency currency;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Symbol glyph in a tinted square.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.actionPurple.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.actionPurple.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  currency.symbol,
                  style: const TextStyle(
                    color: AppColors.onBrand,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Code + name stacked.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currency.code,
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currency.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onBrand.withValues(alpha: 0.65),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // Checkmark for the active currency.
              if (isSelected)
                const Icon(
                  Icons.check_rounded,
                  color: AppColors.actionPurple,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
