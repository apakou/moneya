import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/responsive/responsive_scale.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../widgets/onboarding_hero.dart';

/// Onboarding step 2 — "Send money faster and cheaper".
///
/// Reuses [OnboardingHero] as the frosted base and decorates it with coin
/// sprites positioned on / around the rings.
class SendMoneyPage extends StatelessWidget {
  const SendMoneyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Hero is 82% of the viewport width on phones (matches the
    // original design feel) but capped at 440dp so it stops growing
    // once we cross into tablet territory. Also capped at 38% of
    // viewport height so on short 640dp phones (Tecno, Itel — explicit
    // MoneyA target market) the hero never crowds the headline. FR
    // headlines wrap to 3 lines and need the breathing room.
    final heroSide = ResponsiveScale.clampSquare(
      context: context,
      minWidth: 360,
      maxWidth: 600,
      minValue: 360 * 0.82,
      maxValue: 440,
      maxHeightFraction: 0.38,
    );

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
              child: const _SendMoneyHero(
                walletAsset: 'assets/images/Coin Wallet.png',
                goldCoinAsset: 'assets/images/Coin.png',
              ),
            ),
          ),
          const Spacer(flex: 3),
          Text(
            l10n.onboardingSendMoneyHeadline,
            textAlign: TextAlign.center,
            style: AppTextStyles.heroOnboarding,
          ),
          const Spacer(flex: 6),
        ],
      ),
    );
  }
}

/// Composition: the base ringed hero with a central wallet icon, plus coins
/// scattered on the outer and middle rings.
class _SendMoneyHero extends StatelessWidget {
  const _SendMoneyHero({
    required this.walletAsset,
    required this.goldCoinAsset,
  });

  final String walletAsset;
  final String goldCoinAsset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        // Coin sizes relative to hero side for consistent scaling.
        final smallCoin = side * 0.11;
        final mediumCoin = side * 0.14;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Base hero (rings + frosted disc + central wallet icon).
            OnboardingHero(iconAsset: walletAsset, iconSize: side * 0.3),

            // Orbit coins. Alignment values are fractions of the hero box
            // (-1..1). Gold coins sit on the outer ring (radius ≈ 0.82 in
            // Alignment units, since OnboardingHero's outer ring has diameter
            // side * 0.82).
            // Top-left gold (on outer ring).
            _OrbitCoin(
              alignment: const Alignment(-0.60, -0.75),
              size: mediumCoin,
              asset: goldCoinAsset,
            ),
            // Upper-inner coin (small, on outer ring).
            _OrbitCoin(
              alignment: const Alignment(0.22, -0.62),
              size: smallCoin,
              asset: goldCoinAsset,
            ),
            // Right gold (on outer ring).
            _OrbitCoin(
              alignment: const Alignment(0.92, -0.07),
              size: mediumCoin,
              asset: goldCoinAsset,
            ),
            // Left-inner coin (small, on inner ring).
            _OrbitCoin(
              alignment: const Alignment(-0.72, 0.10),
              size: smallCoin,
              asset: goldCoinAsset,
            ),
            // Lower-right coin (medium, on outer ring).
            _OrbitCoin(
              alignment: const Alignment(0.52, 0.46),
              size: mediumCoin,
              asset: goldCoinAsset,
            ),
            // Bottom gold (on outer ring, slightly left of center).
            _OrbitCoin(
              alignment: const Alignment(-0.17, 0.93),
              size: mediumCoin,
              asset: goldCoinAsset,
            ),
          ],
        );
      },
    );
  }
}

class _OrbitCoin extends StatelessWidget {
  const _OrbitCoin({
    required this.alignment,
    required this.size,
    required this.asset,
  });

  final Alignment alignment;
  final double size;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: size,
        height: size,
        child: _CoinImage(asset: asset),
      ),
    );
  }
}

/// Loads either an SVG or a raster coin sprite depending on file extension.
class _CoinImage extends StatelessWidget {
  const _CoinImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    final isSvg = asset.toLowerCase().endsWith('.svg');
    if (isSvg) {
      return SvgPicture.asset(asset, fit: BoxFit.contain);
    }
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
