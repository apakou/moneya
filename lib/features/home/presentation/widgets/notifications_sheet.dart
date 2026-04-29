import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/app_notification.dart';

/// Entry point — opens the notifications bottom-sheet.
///
/// The sheet renders the user's notification feed grouped into Today /
/// Yesterday / Earlier this week / Older buckets. Read state is tracked
/// in-memory only; once we land Riverpod the in-memory list moves into
/// `notificationsProvider` and persistence becomes a backend concern.
Future<void> showNotificationsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    useSafeArea: false,
    builder: (_) => const _NotificationsSheet(),
  );
}

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet();

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  late List<AppNotification> _items;

  @override
  void initState() {
    super.initState();
    _items = _seed();
  }

  /// Mock feed — replace with `GET /notifications` once the backend lands.
  List<AppNotification> _seed() {
    final now = DateTime.now();
    DateTime ago(int hours) => now.subtract(Duration(hours: hours));

    return <AppNotification>[
      AppNotification(
        id: 'nf-001',
        kind: AppNotificationKind.moneyReceived,
        title: 'Money received',
        body: 'You received GHC 250 from Maria Diop.',
        when: ago(1),
        read: false,
      ),
      AppNotification(
        id: 'nf-002',
        kind: AppNotificationKind.transferSent,
        title: 'Transfer sent',
        body: 'GHC 80 sent to Kwame Nkrumah.',
        when: ago(4),
        read: false,
      ),
      AppNotification(
        id: 'nf-003',
        kind: AppNotificationKind.securityAlert,
        title: 'New device login',
        body: 'A new sign-in to your account from Pixel 8 in Accra.',
        when: ago(9),
        read: false,
      ),
      AppNotification(
        id: 'nf-004',
        kind: AppNotificationKind.transferFailed,
        title: 'Transfer failed',
        body:
            'GHC 120 to Aminata Traoré could not be processed. Tap to retry.',
        when: ago(28),
        read: true,
      ),
      AppNotification(
        id: 'nf-005',
        kind: AppNotificationKind.kycApproved,
        title: 'KYC approved',
        body: 'Your Ghana Card has been verified. You now have full access.',
        when: ago(50),
        read: true,
      ),
      AppNotification(
        id: 'nf-006',
        kind: AppNotificationKind.promo,
        title: 'Refer and earn GHC 20',
        body:
            'Invite a friend to MoneyA. You both get GHC 20 after their first '
            'transfer.',
        when: ago(96),
        read: true,
      ),
      AppNotification(
        id: 'nf-007',
        kind: AppNotificationKind.moneyReceived,
        title: 'Money received',
        body: 'You received GHC 1,250 from Chinedu Okafor.',
        when: ago(180),
        read: true,
      ),
    ];
  }

  void _markAllRead() {
    if (_items.every((n) => n.read)) return;
    setState(() {
      _items = _items.map((n) => n.copyWith(read: true)).toList();
    });
  }

  void _onTileTap(AppNotification n) {
    if (!n.read) {
      setState(() {
        _items = _items
            .map((x) => x.id == n.id ? x.copyWith(read: true) : x)
            .toList();
      });
    }
    // TODO: route per kind — moneyReceived/transferSent/transferFailed →
    // TransactionDetailScreen, securityAlert → SettingsScreen,
    // kycApproved → ProfileScreen, promo → refer flow.
    debugPrint('Notification tapped: ${n.id} (${n.kind.name})');
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _items.where((n) => !n.read).length;
    final groups = _group(_items);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              // Same brand-gradient → black palette as the rest of
              // the app surfaces.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.6, 1.0],
                colors: [
                  Color(0xFF2B0033),
                  Color(0xFF14001A),
                  AppColors.black,
                ],
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                _DragHandle(),
                const SizedBox(height: 6),
                _Header(
                  unreadCount: unreadCount,
                  onMarkAllRead: _markAllRead,
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: groups.length,
                    itemBuilder: (_, gi) {
                      final g = groups[gi];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (gi > 0) const SizedBox(height: 18),
                          _GroupLabel(g.label),
                          const SizedBox(height: 10),
                          ...g.items.map(
                            (n) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _NotificationTile(
                                notification: n,
                                onTap: () => _onTileTap(n),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Buckets the feed into Today / Yesterday / Earlier this week / Older.
  ///
  /// The "earlier this week" boundary is 7 days, not the calendar
  /// week-start, because that's what users intuitively expect from a
  /// notification feed and it sidesteps locale-specific week-start
  /// rules.
  List<_Group> _group(List<AppNotification> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayItems = <AppNotification>[];
    final yesterdayItems = <AppNotification>[];
    final earlierWeek = <AppNotification>[];
    final older = <AppNotification>[];

    for (final n in items) {
      final d = DateTime(n.when.year, n.when.month, n.when.day);
      if (d == today) {
        todayItems.add(n);
      } else if (d == yesterday) {
        yesterdayItems.add(n);
      } else if (d.isAfter(weekAgo)) {
        earlierWeek.add(n);
      } else {
        older.add(n);
      }
    }

    return <_Group>[
      if (todayItems.isNotEmpty) _Group('Today', todayItems),
      if (yesterdayItems.isNotEmpty) _Group('Yesterday', yesterdayItems),
      if (earlierWeek.isNotEmpty) _Group('Earlier this week', earlierWeek),
      if (older.isNotEmpty) _Group('Older', older),
    ];
  }
}

class _Group {
  const _Group(this.label, this.items);
  final String label;
  final List<AppNotification> items;
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.unreadCount, required this.onMarkAllRead});

  final int unreadCount;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(
        children: [
          const Text(
            'Notifications',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppColors.actionPurple,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Spacer(),
          TextButton(
            onPressed: unreadCount == 0 ? null : onMarkAllRead,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.actionPurple,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.30),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text(
              'Mark all as read',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  static const _green = Color(0xFF16A34A);
  static const _red = Color(0xFFDC2626);
  static const _amber = Color(0xFFD97706);

  ({IconData icon, Color tint}) get _decor {
    switch (notification.kind) {
      case AppNotificationKind.moneyReceived:
        return (icon: Icons.south_west_rounded, tint: _green);
      case AppNotificationKind.transferSent:
        return (
          icon: Icons.north_east_rounded,
          tint: AppColors.actionPurple,
        );
      case AppNotificationKind.transferFailed:
        return (icon: Icons.error_outline_rounded, tint: _red);
      case AppNotificationKind.kycApproved:
        return (icon: Icons.verified_user_rounded, tint: _green);
      case AppNotificationKind.promo:
        return (
          icon: Icons.card_giftcard_rounded,
          tint: AppColors.actionPurple,
        );
      case AppNotificationKind.securityAlert:
        return (icon: Icons.shield_outlined, tint: _amber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _decor;
    final unread = !notification.read;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            // Unread rows get a subtle bg tint so the eye picks them
            // out without needing to scan the dot.
            color: Colors.white.withValues(alpha: unread ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: unread ? 0.10 : 0.06),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: d.tint.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(d.icon, color: d.tint, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTime(notification.when),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 8,
                child: unread
                    ? Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.actionPurple,
                          shape: BoxShape.circle,
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

  /// Compact relative timestamp ("2m", "3h", "Yesterday", "Apr 18").
  /// Once `intl` is on the project we should swap this for proper i18n.
  static String _relativeTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final daysAgo = today.difference(d).inDays;
    if (daysAgo == 1) return 'Yesterday';
    if (daysAgo < 7) return '${daysAgo}d';
    const months = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month]} ${t.day}';
  }
}
