import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';

/// Concentric translucent circles with a centered SVG icon.
///
/// Reused across all onboarding pages; only the icon changes.
class OnboardingHero extends StatelessWidget {
  const OnboardingHero({
    super.key,
    required this.iconAsset,
    this.iconSize = 96,
  });

  /// Path to an SVG inside the bundled assets (white mark on transparent bg).
  final String iconAsset;

  /// Size in logical pixels of the inner icon.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Size relative to available width so it scales on small phones.
        final maxSide = constraints.maxWidth;
        final outer = maxSide * 0.82;
        final mid = outer * 0.72;
        final inner = outer * 0.50;

        return SizedBox(
          width: outer,
          height: outer,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _Ring(size: outer, opacity: 0.06),
              _Ring(size: mid, opacity: 0.10),
              // Filled inner disc holding the icon.
              Container(
                width: inner,
                height: inner,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: _HeroIcon(asset: iconAsset, size: iconSize),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Loads either an SVG or a raster image based on the asset extension,
/// so callers can point at `.svg`, `.png`, `.jpg`, `.webp` transparently.
class _HeroIcon extends StatelessWidget {
  const _HeroIcon({required this.asset, required this.size});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isSvg = asset.toLowerCase().endsWith('.svg');
    if (isSvg) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: opacity),
          width: 1,
        ),
      ),
    );
  }
}

