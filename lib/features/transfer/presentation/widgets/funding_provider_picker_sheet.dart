import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/funding_provider.dart';

/// Bottom sheet that lets the user pick which rail funds the transfer
/// (Moov Africa, Orange Money, MoneyA Wallet, …).
///
/// Today the list is hardcoded; later it will be filtered server-side
/// by KYC tier + corridor and provided via Riverpod.
Future<FundingProvider?> showFundingProviderPickerSheet({
  required BuildContext context,
  required FundingProvider selected,
}) {
  return showModalBottomSheet<FundingProvider>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => _FundingProviderPickerSheet(selected: selected),
  );
}

class _FundingProviderPickerSheet extends StatelessWidget {
  const _FundingProviderPickerSheet({required this.selected});

  final FundingProvider selected;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A0220),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select funding source',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: FundingProvider.values.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (ctx, i) {
                    final p = FundingProvider.values[i];
                    return _ProviderRow(
                      provider: p,
                      selected: p == selected,
                      onTap: () => Navigator.of(ctx).pop(p),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final FundingProvider provider;
  final bool selected;
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
              _ProviderGlyph(provider: provider),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  provider.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
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

/// 32×32 logo or, when no asset is bundled yet, a colored initial
/// square fallback so the row still has a visual anchor.
class _ProviderGlyph extends StatelessWidget {
  const _ProviderGlyph({required this.provider});

  final FundingProvider provider;

  @override
  Widget build(BuildContext context) {
    final asset = provider.iconAsset;
    if (asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          asset,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _InitialBadge(label: provider.label),
        ),
      );
    }
    return _InitialBadge(label: provider.label);
  }
}

class _InitialBadge extends StatelessWidget {
  const _InitialBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.actionPurple.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
