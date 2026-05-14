import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../home/domain/supported_currency.dart';
import '../../../transfer/domain/transfer_recipient_prefill.dart';
import '../../../transfer/presentation/screens/transfer_money_screen.dart';
import '../../data/favorites_service.dart';
import '../../domain/favorite.dart';

/// Full Favourites list — entered from Profile > Actions and from
/// the "View all" affordance on the home screen's favourites strip.
///
/// Visual chrome: brand-gradient background with the standard
/// left-aligned back chevron + title, matching `ProfileScreen` /
/// `TransactionsScreen` / `SettingsScreen`.
///
/// ## Behaviour
///
/// * **Empty state.** Friendly explanation + a "Send money" CTA
///   that pushes [TransferMoneyScreen]. We do this rather than
///   hiding the screen entirely because favourites can be purged
///   to zero via swipe-delete, and the user should always have a
///   clear path to refill the list.
///
/// * **Populated list.** Each row is a [Dismissible] keyed on the
///   favourite's [Favorite.identityKey]. Swipe left to remove —
///   the entry is removed from [FavoritesService] immediately, and
///   a snackbar with an **Undo** action lets the user reverse the
///   swipe via [FavoritesService.restore], which re-inserts the
///   favourite at its original chronological position.
///
/// * **Tap to send.** Tapping a row pushes [TransferMoneyScreen]
///   with a [TransferRecipientPrefill] derived from the favourite,
///   so the user lands on the amount keypad with the recipient
///   already locked in (same code path as the home strip).
///
/// ## Currency
///
/// Favourites are recipient-only — they don't pin a currency. The
/// screen therefore defaults the outbound transfer to GHS (the
/// app's default on a cold start). When called from a context that
/// already knows the active currency (e.g. the home screen), pass
/// it via [currency] so the transfer screen lands on the right
/// keypad.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    this.currency = SupportedCurrency.ghs,
    this.service,
    super.key,
  });

  static const String routePath = '/favorites';

  /// Currency to seed the transfer screen with when the user taps a
  /// favourite. Defaults to GHS to match the home-screen default.
  final SupportedCurrency currency;

  /// Override for tests. When `null`, defers to
  /// `FavoritesService.instance` at build time.
  final FavoritesService? service;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  FavoritesService get _service =>
      widget.service ?? FavoritesService.instance;

  void _onTapFavorite(Favorite f) {
    Get.to<void>(
      () => TransferMoneyScreen(
        currency: widget.currency,
        prefill: TransferRecipientPrefill(
          country: f.country,
          nationalPhone: f.nationalPhone,
          displayName: f.displayName,
        ),
      ),
    );
  }

  void _onDismissed(Favorite f) {
    final l10n = AppLocalizations.of(context);
    _service.remove(f.country, f.nationalPhone);
    // Use the framework messenger directly (not Get.snackbar) so the
    // snackbar floats above the bottom nav and matches the look of
    // the rest of the app's transient feedback.
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.black,
        content: Text(
          l10n.favoritesRemoved(f.displayName),
          style: AppTextStyles.body,
        ),
        action: SnackBarAction(
          label: l10n.favoritesUndo,
          textColor: AppColors.onBrand,
          onPressed: () {
            // Restore inserts at the correct chronological index,
            // so the row reappears in its original slot.
            _service.restore(f);
          },
        ),
      ),
    );
  }

  void _onEmptyCta() {
    Get.to<void>(() => TransferMoneyScreen(currency: widget.currency));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.black,
      extendBodyBehindAppBar: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: l10n.favoritesTitle, onBack: Get.back),
              const SizedBox(height: 12),
              Expanded(
                child: ListenableBuilder(
                  listenable: _service,
                  builder: (context, _) {
                    final items = _service.favorites;
                    if (items.isEmpty) {
                      return _EmptyState(onSendMoney: _onEmptyCta);
                    }
                    return _PopulatedList(
                      items: items,
                      onTap: _onTapFavorite,
                      onDismissed: _onDismissed,
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

// ---------------------------------------------------------------------------
// Header — matches the project's standard left-aligned chevron + title.
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
      child: Row(
        children: [
          BackChevronButton(onTap: onBack, tooltip: l10n.commonBack),
          Text(title, style: AppTextStyles.screenTitle),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Populated list
// ---------------------------------------------------------------------------

class _PopulatedList extends StatelessWidget {
  const _PopulatedList({
    required this.items,
    required this.onTap,
    required this.onDismissed,
  });

  final List<Favorite> items;
  final ValueChanged<Favorite> onTap;
  final ValueChanged<Favorite> onDismissed;

  /// Same palette + derivation as `home_screen.dart` so a contact's
  /// avatar tint stays identical between the home strip and this
  /// screen.
  static const List<Color> _palette = [
    Color(0xFFE0A872),
    Color(0xFF8B5A3C),
    Color(0xFF3D2817),
    Color(0xFF6B4423),
    Color(0xFFB07D5C),
    Color(0xFF4A2E1A),
  ];

  Color _colorFor(Favorite f) =>
      _palette[f.identityKey.hashCode.abs() % _palette.length];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Text(
            l10n.favoritesSwipeHint,
            style: AppTextStyles.captionMuted,
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final f = items[i];
              return Dismissible(
                key: ValueKey('fav:${f.identityKey}'),
                direction: DismissDirection.endToStart,
                background: _DismissBackground(),
                onDismissed: (_) => onDismissed(f),
                child: _FavoriteTile(
                  favorite: f,
                  color: _colorFor(f),
                  onTap: () => onTap(f),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0x33FF4D2E), // 20% danger
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.delete_outline_rounded,
        color: Color(0xFFFF4D2E),
        size: 24,
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.favorite,
    required this.color,
    required this.onTap,
  });

  final Favorite favorite;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color,
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favorite.displayName,
                      style: AppTextStyles.listTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      favorite.e164,
                      style: AppTextStyles.captionMuted,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white54,
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
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSendMoney});

  final VoidCallback onSendMoney;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Column(
        children: [
          const Spacer(flex: 3),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              color: AppColors.onBrand,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.favoritesEmptyTitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.favoritesEmptyBody,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted,
          ),
          const Spacer(flex: 4),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: Material(
              color: Colors.white,
              shape: const StadiumBorder(),
              elevation: 0,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onSendMoney,
                child: Center(
                  child: Text(
                    l10n.favoritesEmptyCta,
                    style: AppTextStyles.pillLabel.copyWith(
                      fontSize: 16,
                      color: AppColors.actionPurple,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
