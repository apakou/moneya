import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Onboarding step 3 — "Between African francophone and anglophone countries".
///
/// Reuses [OnboardingHero] (rings + frosted disc), swaps the central icon for
/// a circular swap mark, and decorates the rings with four-point sparkles.
class CrossCorridorPage extends StatelessWidget {
  const CrossCorridorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final heroSide = mediaWidth * 0.82;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 3),
          Center(
            child: SizedBox(
              width: heroSide,
              height: heroSide,
              child: const _CrossCorridorHero(),
            ),
          ),
          const Spacer(flex: 3),
          const Text(
            'Between African francophone\nand anglophone countries',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onBrand,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const Spacer(flex: 6),
        ],
      ),
    );
  }
}

class _CrossCorridorHero extends StatelessWidget {
  const _CrossCorridorHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        final outer = side;
        final mid = outer * 0.72;
        final inner = outer * 0.50;
        final smallStar = side * 0.07;
        final mediumStar = side * 0.10;

        return SizedBox(
          width: outer,
          height: outer,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Concentric translucent rings (matching OnboardingHero style).
              _Ring(size: outer, opacity: 0.06),
              _Ring(size: mid, opacity: 0.10),
              // Frosted inner disc.
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
                child: SizedBox(
                  width: inner * 0.78,
                  height: inner * 0.78,
                  child: Image.asset(
                    'assets/images/swap.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),

              // Sparkles. Alignment values are fractions of the hero box (-1..1).
              _Sparkle(
                alignment: const Alignment(-0.30, -0.55),
                size: mediumStar,
              ),
              _Sparkle(
                alignment: const Alignment(0.78, 0.10),
                size: smallStar,
              ),
              _Sparkle(
                alignment: const Alignment(-0.05, 0.62),
                size: smallStar,
              ),
              _Sparkle(
                alignment: const Alignment(-0.78, 0.50),
                size: mediumStar,
              ),
            ],
          ),
        );
      },
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

/// Outlined circle containing a horizontal swap arrows mark.
class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.alignment, required this.size});

  final Alignment alignment;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/images/sparkle.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
