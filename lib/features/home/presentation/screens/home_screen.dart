import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

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

  // Hardcoded mock data. ---------------------------------------------------
  static const String _userName = 'John Doe';
  static const String _currency = 'GHC';
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
      amount: 'GHC 13000',
      success: true,
    ),
    _Txn(
      kind: _TxnKind.sent,
      label: 'Sent',
      timestamp: 'Jun 12, 2025 - 10:25 AM',
      amount: 'GHC 2500',
      success: false,
    ),
    _Txn(
      kind: _TxnKind.payed,
      label: 'Payed',
      timestamp: 'Jun 12, 2025 - 10:25 AM',
      amount: 'GHC 56300',
      success: true,
    ),
    _Txn(
      kind: _TxnKind.received,
      label: 'Received',
      timestamp: 'Jun 12, 2025 - 10:25 AM',
      amount: 'GHC 56300',
      success: true,
    ),
  ];

  // Tap handlers (all stubs). ---------------------------------------------
  void _onProfileTap() => debugPrint('Profile tapped');
  void _onLanguageTap() => debugPrint('Language tapped');
  void _onNotificationsTap() => debugPrint('Notifications tapped');
  void _onCurrencyTap() => debugPrint('Currency selector tapped');
  void _toggleBalance() =>
      setState(() => _balanceVisible = !_balanceVisible);
  void _onSend() => debugPrint('Send tapped');
  void _onReceive() => debugPrint('Receive tapped');
  void _onSmartRate() => debugPrint('Smart Rate tapped');
  void _onTrustScore() => debugPrint('Trust Score tapped');
  void _onFavoritesViewAll() => debugPrint('Favorites view all tapped');
  void _onFavoriteTap(String name) => debugPrint('Favorite tapped: $name');
  void _onTransactionsViewAll() =>
      debugPrint('Recent transactions view all tapped');
  void _onTransactionTap(_Txn t) =>
      debugPrint('Transaction tapped: ${t.label} ${t.amount}');

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          children: [
            _TopRow(
              userName: _userName,
              onProfileTap: _onProfileTap,
              onLanguageTap: _onLanguageTap,
              onNotificationsTap: _onNotificationsTap,
            ),
            const SizedBox(height: 28),
            Center(
              child: _CurrencyPill(
                currency: _currency,
                onTap: _onCurrencyTap,
              ),
            ),
            const SizedBox(height: 28),
            _Balance(
              currency: _currency,
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
              onSmartRate: _onSmartRate,
              onTrustScore: _onTrustScore,
            ),
            const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.groups_rounded,
              title: 'Your Favorites',
              trailing: _ViewAllButton(onTap: _onFavoritesViewAll),
            ),
            const SizedBox(height: 16),
            _FavoritesStrip(
              favorites: _favorites,
              onTap: _onFavoriteTap,
            ),
            const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.description_outlined,
              title: 'Recent transactions',
              trailing: _ViewAllButton(onTap: _onTransactionsViewAll),
            ),
            const SizedBox(height: 8),
            for (final t in _transactions)
              _TransactionTile(
                txn: t,
                onTap: () => _onTransactionTap(t),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top row
// ---------------------------------------------------------------------------

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.userName,
    required this.onProfileTap,
    required this.onLanguageTap,
    required this.onNotificationsTap,
  });

  final String userName;
  final VoidCallback onProfileTap;
  final VoidCallback onLanguageTap;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkResponse(
          onTap: onProfileTap,
          radius: 32,
          child: const CircleAvatar(
            radius: 26,
            backgroundColor: Color(0xFF3D2817),
            child: Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            userName,
            style: const TextStyle(
              color: AppColors.onBrand,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _SquareIconButton(
          tooltip: 'Language',
          onTap: onLanguageTap,
          // Plain "EN" badge stand-in for the UK flag in the mock; swapping
          // in `country_flags` round flag is a one-liner once we wire i18n.
          child: const Text(
            'EN',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SquareIconButton(
          tooltip: 'Notifications',
          onTap: onNotificationsTap,
          child: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.actionPurple,
            size: 22,
          ),
        ),
      ],
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

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
                Icons.keyboard_arrow_down_rounded,
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
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
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
            Text(
              visible ? amount : '••••••',
              style: const TextStyle(
                color: AppColors.onBrand,
                fontSize: 48,
                fontWeight: FontWeight.w700,
                height: 1.0,
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
            icon: Icons.arrow_upward_rounded,
            background: Colors.white,
            foreground: AppColors.actionPurple,
            onTap: onSend,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _PrimaryActionButton(
            label: 'Receive',
            icon: Icons.arrow_downward_rounded,
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
          style: const TextStyle(
            color: AppColors.onBrand,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
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
              Icons.chevron_right_rounded,
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

/// Horizontally-scrolling strip of AI insight cards. All cards share the
/// same height (driven by the `SizedBox` height) so the row stays visually
/// balanced regardless of body length.
class _InsightsStrip extends StatelessWidget {
  const _InsightsStrip({
    required this.onSmartRate,
    required this.onTrustScore,
  });

  final VoidCallback onSmartRate;
  final VoidCallback onTrustScore;

  static const double _cardWidth = 240;
  static const double _stripHeight = 140;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _InsightCard(
        title: 'Smart Rate',
        titleTrailing: const Icon(
          Icons.north_east_rounded,
          color: Color(0xFF22C55E),
          size: 18,
        ),
        body: 'Save GHC 10 on your next transfer.',
        onTap: onSmartRate,
      ),
      _InsightCard(
        title: 'Trust Score',
        body: 'Your Trust Score: 750. Unlock micro-loans.',
        showArrow: true,
        onTap: onTrustScore,
      ),
    ];

    return SizedBox(
      height: _stripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // No internal padding — the parent ListView already supplies the
        // 24dp horizontal gutter, so the first card aligns with the
        // section header above.
        padding: EdgeInsets.zero,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(width: _cardWidth, child: cards[i]),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.body,
    required this.onTap,
    this.titleTrailing,
    this.showArrow = false,
  });

  final String title;
  final String body;
  final VoidCallback onTap;
  final Widget? titleTrailing;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (titleTrailing != null) ...[
                    const SizedBox(width: 6),
                    titleTrailing!,
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.onBrandMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                  ),
                ),
              ),
              // Reserve a consistent slot for the trailing arrow so cards
              // with and without one share the same body height.
              SizedBox(
                height: 18,
                child: showArrow
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.onBrand,
                          size: 18,
                        ),
                      )
                    : null,
              ),
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
  const _TransactionTile({required this.txn, required this.onTap});

  final _Txn txn;
  final VoidCallback onTap;

  ({IconData icon, Color color}) get _glyph {
    switch (txn.kind) {
      case _TxnKind.received:
        return (
          icon: Icons.arrow_downward_rounded,
          color: const Color(0xFF22C55E),
        );
      case _TxnKind.sent:
        return (
          icon: Icons.arrow_upward_rounded,
          color: const Color(0xFFF97316),
        );
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
    final statusColor =
        txn.success ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
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
                    style: const TextStyle(
                      color: AppColors.onBrand,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    txn.timestamp,
                    style: const TextStyle(
                      color: AppColors.onBrandMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  txn.amount,
                  style: const TextStyle(
                    color: AppColors.onBrand,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
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
