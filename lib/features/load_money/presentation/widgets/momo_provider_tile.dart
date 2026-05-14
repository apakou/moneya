import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/momo_provider.dart';

/// Single-row picker tile for a [MomoProvider] on the Load Money
/// provider-selection screen.
///
/// Visually: white-translucent pill matching the existing `_CountryChip`
/// / `_ProviderChip` widgets in the transfer flow — round logo on the
/// left, label centered-left, chevron on the right. We re-implement
/// rather than import the transfer widgets because those are
/// `_PrivateClass` and tightly coupled to the picker sheet they live
/// in; pulling them up would balloon a 1200-line file's surface for
/// little gain.
///
/// When the provider has no [MomoProvider.iconAsset] yet (most do
/// today; assets land in a follow-up PR), we fall back to a colored
/// disc with the provider's first letter — same trick the contacts
/// list uses for empty avatars.
class MomoProviderTile extends StatelessWidget {
  const MomoProviderTile({
    required this.provider,
    required this.onTap,
    super.key,
  });

  final MomoProvider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconAsset = provider.iconAsset;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              _Logo(
                iconAsset: iconAsset,
                letter: provider.label.characters.first,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  provider.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.iconAsset, required this.letter});

  final String? iconAsset;
  final String letter;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    if (iconAsset != null) {
      return ClipOval(
        child: Image.asset(
          iconAsset!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Treat asset-loading failures as "no asset" rather than
          // throwing — keeps the picker usable while the design team
          // adds logos.
          errorBuilder: (_, _, _) => _FallbackInitial(letter: letter),
        ),
      );
    }
    return _FallbackInitial(letter: letter);
  }
}

class _FallbackInitial extends StatelessWidget {
  const _FallbackInitial({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.actionPurple.withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
