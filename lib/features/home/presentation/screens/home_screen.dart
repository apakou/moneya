import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../transfer/presentation/screens/transfer_money_screen.dart';
import '../../../receive/presentation/screens/receive_screen.dart';
import '../../domain/supported_currency.dart';
import '../widgets/currency_picker_sheet.dart';
import '../widgets/home_header.dart';
import '../widgets/notifications_sheet.dart';
import 'home_shell.dart';
import 'profile_screen.dart';

/// Post-onboarding home / dashboard.
///
/// Mock-faithful: profile + greeting / language pill + bell on the top
/// row, currency selector pill, total balance, Send/Receive primary
/// actions, AI Insights pair, Your Favorites strip, and Recent
/// transactions list. All values are hardcoded; data wiring will land
/// later via Riverpod providers.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _balanceVisible = true;
  UiLanguage _currentLanguage = UiLanguage.en;
  // Default to Ghanaian Cedi to match the mock; the picker lets the
  // user switch to any of the SupportedCurrency entries.
  SupportedCurrency _currency = SupportedCurrency.ghs;

  // Hardcoded mock data. ---------------------------------------------------
  static const String _userName = 'John Doe';
  static const String _balance = '13,000';

  static const List<_Favorite> _favorites = [
    _Favorite('Rodrigue Gomez', Color(0xFFE0A872)),
    _Favorite('Celia Koffi', Color(0xFF8B5A3C)),
    _Favorite('John Doe', Color(0xFF3D2817)),
  ];

  static const List<_Txn> _transactions = [
    _Txn(
      kind: _TxnKind.received,
      label: 'Received',
      timestamp: 'Jun 12, 2025 - 10:25 AM',
      amount: '13000',
      success: true,
    ),
    _Txn(
      kind: _TxnKind.sent,
      label: 'Sent',
      timestamp: 'Jun 12, 2025 - 10:25 AM',
      amount: '2500',
      success: false,
    ),
    _Txn(
      kind: _TxnKind.payed,
      label: 'Payed',
      timestamp: 'Jun 12, 2025 - 10:25 AM',
      amount: '56300',
      success: true,
    ),
    _Txn(
      kind: _TxnKind.received,
      label: 'Received',
      timestamp: 'Jun 12, 2025 - 10:25 AM',
      amount: '56300',
      success: true,
    ),
  ];

  // Tap handlers (all stubs). ---------------------------------------------
  void _onProfileTap() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }
  void _onLanguageTap() {
    // Visible toggle for now; real i18n wiring lands later.
    setState(() {
      _currentLanguage = _currentLanguage == UiLanguage.en
          ? UiLanguage.fr
          : UiLanguage.en;
    });
    debugPrint('Language tapped → ${_currentLanguage.name}');
  }

  void _onNotificationsTap() => showNotificationsSheet(context);
  Future<void> _onCurrencyTap() async {
    final picked = await showCurrencyPickerSheet(
      context: context,
      selected: _currency,
    );
    if (picked == null || picked == _currency) return;
    setState(() => _currency = picked);
    debugPrint('Currency switched to ${_currency.code}');
    // TODO: re-fetch the displayed balance in the new currency once we
    // have an FX/balance backend. The hardcoded "13,000" stays for now.
  }

  void _toggleBalance() => setState(() => _balanceVisible = !_balanceVisible);
  void _onSend() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransferMoneyScreen(currency: _currency),
      ),
    );
  }

  void _onReceive() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiveScreen(currency: _currency),
      ),
    );
  }
  void _onSmartRate() => debugPrint('Smart Rate tapped');
  void _onTrustScore() => debugPrint('Trust Score tapped');
  void _onFavoritesViewAll() => debugPrint('Favorites view all tapped');
  void _onFavoriteTap(String name) => debugPrint('Favorite tapped: $name');
  void _onTransactionsViewAll() {
    // Switch the parent HomeShell to the Transactions tab (index 1)
    // rather than pushing a new route — keeps the bottom-nav state
    // selection in sync with what's on screen.
    HomeShell.of(context)?.selectTab(1);
  }
  void _onTransactionTap(_Txn t) => debugPrint(
    'Transaction tapped: ${t.label} ${_currency.code} ${t.amount}',
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          children: [
            HomeHeader(
              userName: _userName,
              language: _currentLanguage,
              onProfileTap: _onProfileTap,
              onLanguageTap: _onLanguageTap,
              onNotificationsTap: _onNotificationsTap,
            ),
            const SizedBox(height: 28),
            Center(
              child: _CurrencyPill(
                currency: _currency.code,
                onTap: _onCurrencyTap,
              ),
            ),
            const SizedBox(height: 28),
            _Balance(
              currency: _currency.code,
              amount: _balance,
              visible: _balanceVisible,
              onToggle: _toggleBalance,
            ),
            const SizedBox(height: 36),
            _PrimaryActions(onSend: _onSend, onReceive: _onReceive),
            const SizedBox(height: 36),
            _SectionHeader(
              icon: Icons.auto_awesome_rounded,
              title: 'AI Insights',
            ),
            const SizedBox(height: 12),
            _InsightsStrip(
              currencyCode: _currency.code,
              onSmartRate: _onSmartRate,
              onTrustScore: _onTrustScore,
            ),
            const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.favorite_rounded,
              title: 'Your Favorites',
              trailing: _ViewAllButton(onTap: _onFavoritesViewAll),
            ),
            const SizedBox(height: 16),
            _FavoritesStrip(favorites: _favorites, onTap: _onFavoriteTap),
            const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.history_rounded,
              title: 'Recent transactions',
              trailing: _ViewAllButton(onTap: _onTransactionsViewAll),
            ),
            const SizedBox(height: 8),
            for (final t in _transactions)
              _TransactionTile(
                txn: t,
                currencyCode: _currency.code,
                onTap: () => _onTransactionTap(t),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top row — moved to widgets/home_header.dart and shared with the
// transactions tab; the previous private _TopRow / _UiLanguage /
// _SquareIconButton trio lived here. See HomeHeader for the
// canonical implementation.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Currency pill
// ---------------------------------------------------------------------------

class _CurrencyPill extends StatelessWidget {
  const _CurrencyPill({required this.currency, required this.onTap});

  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currency,
                style: const TextStyle(
                  color: AppColors.onBrand,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.expand_more_rounded,
                color: AppColors.onBrand,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balance
// ---------------------------------------------------------------------------

class _Balance extends StatelessWidget {
  const _Balance({
    required this.currency,
    required this.amount,
    required this.visible,
    required this.onToggle,
  });

  final String currency;
  final String amount;
  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Total Balance',
              style: TextStyle(
                color: AppColors.onBrandMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            InkResponse(
              onTap: onToggle,
              radius: 20,
              child: Icon(
                visible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: AppColors.onBrandMuted,
                size: 20,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                currency,
                style: const TextStyle(
                  color: AppColors.onBrandMuted,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            HeroTextScaleClamp(
              child: Text(
                visible ? amount : '•••',
                style: AppTextStyles.heroAmount,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Primary actions (Send / Receive)
// ---------------------------------------------------------------------------

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({required this.onSend, required this.onReceive});

  final VoidCallback onSend;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PrimaryActionButton(
            label: 'Send',
            icon: Icons.north_east_rounded,
            background: Colors.white,
            foreground: AppColors.actionPurple,
            onTap: onSend,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _PrimaryActionButton(
            label: 'Receive',
            icon: Icons.south_west_rounded,
            background: AppColors.actionPurple,
            foreground: Colors.white,
            onTap: onReceive,
          ),
        ),
      ],
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: foreground, width: 1.5),
                ),
                child: Icon(icon, color: foreground, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header + view all
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.onBrand, size: 22),
        const SizedBox(width: 10),
        Text(
          title,
          style: AppTextStyles.subsectionTitle,
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'View all',
              style: TextStyle(
                color: AppColors.onBrandMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.onBrandMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Insights cards
// ---------------------------------------------------------------------------

/// One insight datum. Held inline at the top of the strip so the strip's
/// `build()` stays focused on layout.
class _Insight {
  const _Insight({
    required this.title,
    required this.body,
    required this.metric,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  /// Card heading, e.g. "Smart Rate".
  final String title;

  /// Supporting copy under the title.
  final String body;

  /// Headline value pinned to the bottom-left of the card. Kept short
  /// (~12 chars) so it fits next to the chevron at 240dp width.
  final String metric;

  /// Icon shown in the top-left badge.
  final IconData icon;

  /// Accent color used for the icon badge tint, the metric chip, and the
  /// soft glow on the right edge of the card.
  final Color accent;

  final VoidCallback onTap;
}

/// Horizontally-scrolling strip of AI insight cards.
///
/// Sizing rules:
///   * Card width is derived from the viewport so ~1.4 cards are visible
///     at any phone size, clamped to a sensible min/max so we never get
///     absurdly skinny or wall-sized cards on tablets.
///   * Card height is driven by `MediaQuery.textScaler` so users with
///     bumped-up accessibility text don't get clipped body copy or
///     overlapping metric chips.
///   * The parent `ListView`'s 24dp horizontal gutter wraps this strip,
///     so the first card's left edge aligns with the section header.
class _InsightsStrip extends StatelessWidget {
  const _InsightsStrip({
    required this.currencyCode,
    required this.onSmartRate,
    required this.onTrustScore,
  });

  final String currencyCode;
  final VoidCallback onSmartRate;
  final VoidCallback onTrustScore;

  // Card width is a fraction of the available viewport width, clamped.
  static const double _cardWidthFraction = 0.72; // ~1.4 cards visible
  static const double _minCardWidth = 220;
  static const double _maxCardWidth = 320;

  // Base card height at 1.0 text scale. Scales up with the user's text
  // scale factor so body + metric never collide.
  static const double _baseCardHeight = 156;
  static const double _minCardHeight = 156;
  static const double _maxCardHeight = 220;

  // Accent palette. Kept here (not in AppColors) until we have more than
  // a handful of insight types — promote to design tokens when needed.
  static const Color _greenAccent = Color(0xFF22C55E);
  static const Color _amberAccent = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final insights = <_Insight>[
      _Insight(
        title: 'Smart Rate',
        body: 'Save on your next cross-border transfer.',
        metric: '+ $currencyCode 10',
        icon: Icons.trending_up_rounded,
        accent: _greenAccent,
        onTap: onSmartRate,
      ),
      _Insight(
        title: 'Trust Score',
        body: 'Unlock micro-loans up to $currencyCode 5,000.',
        metric: '750',
        icon: Icons.verified_user_rounded,
        accent: AppColors.actionPurple,
        onTap: onTrustScore,
      ),
      // Sample third card so the horizontal scroll affordance is real.
      // Replace with backend-driven insights when wired.
      _Insight(
        title: 'Spending pulse',
        body: 'You spent 18% less than last week.',
        metric: '-18%',
        icon: Icons.insights_rounded,
        accent: _amberAccent,
        onTap: () => debugPrint('Spending pulse tapped'),
      ),
    ];

    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 1.6);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth * _cardWidthFraction)
            .clamp(_minCardWidth, _maxCardWidth)
            .toDouble();
        final cardHeight = (_baseCardHeight * textScale)
            .clamp(_minCardHeight, _maxCardHeight)
            .toDouble();

        return SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            // Defer to platform-default physics (bouncy on iOS, clamping
            // on Android). Hard-coding bouncy felt off on Android.
            itemCount: insights.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: cardWidth,
              child: _InsightCard(insight: insights[i]),
            ),
          ),
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final _Insight insight;

  @override
  Widget build(BuildContext context) {
    final accent = insight.accent;
    return DecoratedBox(
      // Glass surface: faint accent-tinted gradient layered over the
      // translucent dark base, plus a soft 1px white inner border.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.20),
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(8, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: insight.onTap,
          splashColor: accent.withValues(alpha: 0.12),
          highlightColor: accent.withValues(alpha: 0.06),
          child: Stack(
            children: [
              // Decorative accent glow blob in the top-right corner.
              Positioned(
                top: -32,
                right: -32,
                child: _AccentGlow(color: accent),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _IconBadge(icon: insight.icon, color: accent),
                        const Spacer(),
                        Flexible(
                          child: _MetricChip(
                            label: insight.metric,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      insight.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        insight.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.onBrand.withValues(alpha: 0.72),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 36dp rounded-square icon badge tinted with the card's accent color.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// Pill displaying the card's headline metric.
class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Soft circular glow drawn behind the card content for depth.
class _AccentGlow extends StatelessWidget {
  const _AccentGlow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.35),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites strip
// ---------------------------------------------------------------------------

class _Favorite {
  const _Favorite(this.name, this.color);
  final String name;
  final Color color;
}

class _FavoritesStrip extends StatelessWidget {
  const _FavoritesStrip({required this.favorites, required this.onTap});

  final List<_Favorite> favorites;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, i) {
          final f = favorites[i];
          return _FavoriteAvatar(favorite: f, onTap: () => onTap(f.name));
        },
      ),
    );
  }
}

class _FavoriteAvatar extends StatelessWidget {
  const _FavoriteAvatar({required this.favorite, required this.onTap});

  final _Favorite favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(36),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: favorite.color,
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              favorite.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.onBrand,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent transactions
// ---------------------------------------------------------------------------

enum _TxnKind { received, sent, payed }

class _Txn {
  const _Txn({
    required this.kind,
    required this.label,
    required this.timestamp,
    required this.amount,
    required this.success,
  });

  final _TxnKind kind;
  final String label;
  final String timestamp;
  final String amount;
  final bool success;
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.txn,
    required this.currencyCode,
    required this.onTap,
  });

  final _Txn txn;
  final String currencyCode;
  final VoidCallback onTap;

  ({IconData icon, Color color}) get _glyph {
    switch (txn.kind) {
      case _TxnKind.received:
        return (icon: Icons.south_west_rounded, color: const Color(0xFF22C55E));
      case _TxnKind.sent:
        return (icon: Icons.north_east_rounded, color: const Color(0xFFF97316));
      case _TxnKind.payed:
        return (
          icon: Icons.credit_card_rounded,
          color: const Color(0xFF3B82F6),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _glyph;
    final statusColor = txn.success
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
    final statusLabel = txn.success ? 'Success' : 'Failed';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: g.color.withValues(alpha: 0.12),
                border: Border.all(
                  color: g.color.withValues(alpha: 0.6),
                  width: 1.2,
                ),
              ),
              child: Icon(g.icon, color: g.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.label,
                    style: AppTextStyles.listTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    txn.timestamp,
                    style: AppTextStyles.microNumeric,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currencyCode ${txn.amount}',
                  style: AppTextStyles.numeric(AppTextStyles.listTitle),
                ),
                const SizedBox(height: 2),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
