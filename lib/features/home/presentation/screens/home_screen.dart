import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../main.dart' show LocaleScope;
import '../../../auth/domain/supported_country.dart';
import '../../../favorites/data/favorites_service.dart';
import '../../../favorites/domain/favorite.dart';
import '../../../favorites/presentation/screens/favorites_screen.dart';
import '../../../load_money/presentation/screens/load_provider_screen.dart';
import '../../../transfer/domain/transfer_recipient_prefill.dart';
import '../../../transfer/presentation/screens/transfer_money_screen.dart';
import '../../../receive/presentation/screens/receive_screen.dart';
import '../../../withdraw/presentation/screens/withdraw_provider_screen.dart';
import '../../domain/supported_currency.dart';
import '../../domain/transaction.dart';
import '../widgets/currency_picker_sheet.dart';
import '../widgets/home_header.dart';
import '../widgets/notifications_sheet.dart';
import 'home_shell.dart';
import 'profile_screen.dart';
import 'transaction_detail_screen.dart';

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
  // Default to Ghanaian Cedi to match the mock; the picker lets the
  // user switch to any of the SupportedCurrency entries.
  SupportedCurrency _currency = SupportedCurrency.ghs;

  // Hardcoded mock data. ---------------------------------------------------
  static const String _userName = 'John Doe';

  // Mock balance — single source of truth for the displayed amount
  // AND the withdraw flow's insufficient-balance guard. Stored as
  // `num` (major units of the active currency) so callers can do
  // arithmetic without re-parsing a localized string. Display formats
  // with `NumberFormat.decimalPattern()` via the `,` grouping in
  // `_balanceDisplay`. When the backend lands this becomes a Riverpod
  // provider; until then mutating this in `setState` is good enough.
  num _balanceMinor = 13000;

  /// Display string for the balance card (e.g. `'13,000'`).
  ///
  /// Uses a thousands-grouped int representation. We deliberately do
  /// NOT convert across currencies on switch — the mock-faithful
  /// behaviour is to relabel the unit and keep the digit untouched.
  String get _balanceDisplay {
    final n = _balanceMinor.toInt();
    final s = n.toString();
    // Insert thousands separators without pulling in intl just for
    // this one helper.
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static const List<_Favorite> _favoritesFallback = [
    // Seed fallback shown only if the FavoritesService is somehow
    // empty (e.g. after a forced wipe in tests). The service ships
    // pre-populated with the same three entries so production users
    // always render from live data — these are kept as a belt-and-
    // braces guarantee that the strip never collapses to zero height.
    //
    // Phone numbers below are intentionally chosen from the
    // RecipientLookupService stub directory so tapping a favorite
    // results in an immediate "Found" badge in the transfer screen.
    // Replace once the directory endpoint lands.
    _Favorite(
      name: 'Xavier Brahman',
      color: Color(0xFFE0A872),
      country: SupportedCountry.ivoryCoast,
      nationalPhone: '0598766265',
    ),
    _Favorite(
      name: 'Aminata Koffi',
      color: Color(0xFF8B5A3C),
      country: SupportedCountry.ivoryCoast,
      nationalPhone: '0598001234',
    ),
    _Favorite(
      name: 'Kojo Mensah',
      color: Color(0xFF3D2817),
      country: SupportedCountry.ghana,
      nationalPhone: '0244112233',
    ),
  ];

  /// Avatar colours used to skin the home favourites strip. Picked
  /// deterministically per favourite (by `identityKey` hash) so a
  /// given contact always keeps the same colour across rebuilds and
  /// across the cold-start ordering of [FavoritesService].
  static const List<Color> _favoritePalette = [
    Color(0xFFE0A872),
    Color(0xFF8B5A3C),
    Color(0xFF3D2817),
    Color(0xFF6B4423),
    Color(0xFFB07D5C),
    Color(0xFF4A2E1A),
  ];

  /// Adapt a live [Favorite] (domain model) to the local view-model
  /// the home strip already knows how to render. Deterministic colour
  /// derivation keeps the avatar visually stable as the list is
  /// reordered (e.g. when a re-favouriting bumps the entry to the top).
  _Favorite _toFavoriteVM(Favorite f) {
    final idx = f.identityKey.hashCode.abs() % _favoritePalette.length;
    return _Favorite(
      name: f.displayName,
      color: _favoritePalette[idx],
      country: f.country,
      nationalPhone: f.nationalPhone,
    );
  }

  // Recent-transactions seed for the home dashboard.
  //
  // Now uses the public [Transaction] model (same shape as the
  // dedicated Transactions tab + detail screen) so taps can push
  // straight into [TransactionDetailScreen] without an intermediate
  // adapter. Once the backend lands this becomes a Riverpod provider
  // backed by `GET /transfers?limit=4`.
  //
  // Mock identifiers (`TX…`), counterparty names, phones, and
  // payment-method labels are intentionally aligned with the
  // patterns used in `transactions_screen.dart` so the detail
  // screen feels populated regardless of which list the user
  // tapped through from. `when` uses a fixed timestamp on a
  // `static const`-incompatible field, so the list is built lazily
  // in [_recentTransactions] (`DateTime` literals aren't `const`).
  static final List<Transaction> _transactions = [
    Transaction(
      id: 'TX10A2B3',
      kind: TxnKind.received,
      when: DateTime(2025, 6, 12, 10, 25),
      amount: '13000',
      fee: '0',
      status: TxnStatus.success,
      counterparty: 'Axel Asamoa',
      counterpartyPhone: '+233241234567',
      paymentMethod: 'Mobile Money • MTN MoMo',
    ),
    Transaction(
      id: 'TX20C4D5',
      kind: TxnKind.sent,
      when: DateTime(2025, 6, 12, 10, 25),
      amount: '2500',
      fee: '50',
      status: TxnStatus.failed,
      counterparty: 'Maria Diop',
      counterpartyPhone: '+221771234567',
      paymentMethod: 'Mobile Money • Wave',
    ),
    Transaction(
      id: 'TX30E6F7',
      kind: TxnKind.sent,
      when: DateTime(2025, 6, 12, 10, 25),
      amount: '56300',
      fee: '281',
      status: TxnStatus.success,
      counterparty: 'Kwame Nkrumah',
      counterpartyPhone: '+233244987654',
      paymentMethod: 'Bank Transfer • Ecobank',
    ),
    Transaction(
      id: 'TX40A8B9',
      kind: TxnKind.received,
      when: DateTime(2025, 6, 12, 10, 25),
      amount: '56300',
      fee: '0',
      status: TxnStatus.success,
      counterparty: 'Aminata Traoré',
      counterpartyPhone: '+223761122334',
      paymentMethod: 'Mobile Money • Orange Money',
    ),
  ];

  // Tap handlers (all stubs). ---------------------------------------------
  void _onProfileTap() {
    Get.to<void>(() => const ProfileScreen());
  }
  Future<void> _onLanguageTap() async {
    // Flip the app-wide locale via the InheritedNotifier handle. Every
    // descendant of MaterialApp that reads AppLocalizations.of(context)
    // re-builds in the new language; the choice is persisted to
    // SharedPreferences so it survives a cold start.
    await LocaleScope.of(context, listen: false).toggle();
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
    Get.to<void>(() => TransferMoneyScreen(currency: _currency));
  }

  void _onReceive() {
    Get.to<void>(() => ReceiveScreen(currency: _currency));
  }

  // Onramp action — adds fiat or stablecoin into the user's MoneyA
  // balance. Pushes the Load Money flow (provider → amount). The
  // backend onramp wiring (Yellow Card / Fonbnk) lands in M2 per
  // docs/backend/backlog.md; until then the flow ends on a stubbed
  // success outcome screen.
  void _onLoad() {
    Get.to<void>(() => LoadProviderScreen(currency: _currency));
  }

  // Offramp action — moves fiat out of MoneyA into the user's mobile
  // money wallet or bank account. Pushes the Withdraw flow
  // (provider → amount). Carries the live numeric balance so step 2
  // can enforce the insufficient-balance block at swipe-time.
  void _onWithdraw() {
    Get.to<void>(
      () => WithdrawProviderScreen(
        currency: _currency,
        balanceMinor: _balanceMinor,
      ),
    );
  }
  void _onSmartRate() => debugPrint('Smart Rate tapped');
  void _onTrustScore() => debugPrint('Trust Score tapped');
  void _onFavoritesViewAll() {
    Get.to<void>(() => FavoritesScreen(currency: _currency));
  }

  /// Open the transfer flow with the favorite already selected as the
  /// recipient. The directory lookup runs on mount so the "Found"
  /// badge resolves immediately and the canonical name overwrites the
  /// favorite's locally-stored name.
  void _onFavoriteTap(_Favorite favorite) {
    Get.to<void>(
      () => TransferMoneyScreen(
        currency: _currency,
        prefill: TransferRecipientPrefill(
          country: favorite.country,
          nationalPhone: favorite.nationalPhone,
          displayName: favorite.name,
        ),
      ),
    );
  }
  void _onTransactionsViewAll() {
    // Switch the parent HomeShell to the Transactions tab (index 1)
    // rather than pushing a new route — keeps the bottom-nav state
    // selection in sync with what's on screen.
    HomeShell.of(context)?.selectTab(1);
  }
  void _onTransactionTap(Transaction t) {
    // Push the shared detail screen with the same currency context
    // the home dashboard is currently displaying. The Transactions
    // tab routes through the same widget; both call sites stay in
    // sync because they share the [Transaction] model.
    Get.to<void>(
      () => TransactionDetailScreen(
        txn: t,
        currencyCode: _currency.code,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The language pill flag mirrors the app-wide active locale.
    // Reading the LocaleScope here (listen: true via context.dependOn…)
    // means HomeScreen rebuilds whenever the locale flips, which keeps
    // the flag glyph in sync without a per-screen state copy.
    final activeLocale = LocaleScope.of(context).current;
    final pillLanguage = activeLocale == AppLocale.fr
        ? UiLanguage.fr
        : UiLanguage.en;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          children: [
            HomeHeader(
              userName: _userName,
              language: pillLanguage,
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
              amount: _balanceDisplay,
              visible: _balanceVisible,
              onToggle: _toggleBalance,
            ),
            const SizedBox(height: 36),
            _PrimaryActions(
              onSend: _onSend,
              onReceive: _onReceive,
              onLoad: _onLoad,
              onWithdraw: _onWithdraw,
            ),
            const SizedBox(height: 36),
            _SectionHeader(
              icon: Icons.auto_awesome_rounded,
              title: l10n.homeSectionAiInsights,
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
              title: l10n.homeSectionFavorites,
              trailing: _ViewAllButton(onTap: _onFavoritesViewAll),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              // Strip rebuilds whenever the in-memory FavoritesService
              // mutates — covers add-from-success-screen, remove +
              // undo from FavoritesScreen, and tests overriding the
              // singleton via `debugSetInstance`. Capped to the 6
              // newest entries to keep the horizontal scroll short on
              // a phone; FavoritesScreen shows the full list.
              listenable: FavoritesService.instance,
              builder: (context, _) {
                final live = FavoritesService.instance.favorites;
                final source = live.isEmpty ? _favoritesFallback :
                    live.take(6).map(_toFavoriteVM).toList(growable: false);
                return _FavoritesStrip(
                  favorites: source,
                  onTap: _onFavoriteTap,
                );
              },
            ),
            const SizedBox(height: 28),
            _SectionHeader(
              icon: Icons.history_rounded,
              title: l10n.homeSectionRecentTransactions,
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
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.homeTotalBalance,
              style: const TextStyle(
                color: AppColors.onBrandMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            InkResponse(
              onTap: onToggle,
              radius: 20,
              // Tooltip / a11y label flips with state — when the
              // balance is currently visible the eye-with-slash hides
              // it, and vice-versa.
              child: Tooltip(
                message: visible ? l10n.homeBalanceHide : l10n.homeBalanceShow,
                child: Icon(
                  visible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.onBrandMuted,
                  size: 20,
                ),
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
// Primary actions — Send / Receive / Load Money / Withdraw
// ---------------------------------------------------------------------------
//
// Four equal-weight money-movement actions rendered as a single row
// of round icon buttons with the label set below each. This is the
// canonical pattern used by Cash App, Wise, Revolut, and most modern
// fintech apps — it reads as a quick-action launcher rather than a
// CTA hierarchy, which matches the reality that the user opens the
// home screen specifically to perform one of these four operations.
//
// Sizing rationale:
//   - 56dp circle diameter: well above the 44dp WCAG 2.2 motor-
//     accessibility floor, and matches the existing 56dp button
//     height used elsewhere so visual rhythm is preserved.
//   - 8dp gap between circle + label keeps the pair perceived as a
//     single tappable unit.
//   - `MainAxisAlignment.spaceBetween` distributes the 4 tiles
//     edge-to-edge so the layout breathes without needing fixed
//     inter-tile spacers.
//   - Whole tile (circle + label) is wrapped in one InkWell so the
//     label region is also a hit target — important for users who
//     read first and tap second.

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({
    required this.onSend,
    required this.onReceive,
    required this.onLoad,
    required this.onWithdraw,
  });

  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onLoad;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Color-pairing rationale:
    //   - Send + Load Money → white circles with purple icons
    //     ("money out / money in" \u2014 the direction-driven pair)
    //   - Receive + Withdraw → purple circles with white icons
    //     (the rail-touching counterpart pair)
    // This 2-and-2 split breaks the row into visually balanced
    // halves without imposing a hierarchy; all four remain
    // equal-weight quick actions.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundActionButton(
          label: l10n.homeActionSend,
          icon: Icons.north_east_rounded,
          background: Colors.white,
          foreground: AppColors.actionPurple,
          onTap: onSend,
        ),
        _RoundActionButton(
          label: l10n.homeActionReceive,
          icon: Icons.south_west_rounded,
          background: AppColors.actionPurple,
          foreground: Colors.white,
          onTap: onReceive,
        ),
        _RoundActionButton(
          label: l10n.homeActionLoad,
          icon: Icons.add_rounded,
          background: Colors.white,
          foreground: AppColors.actionPurple,
          onTap: onLoad,
        ),
        _RoundActionButton(
          label: l10n.homeActionWithdraw,
          icon: Icons.account_balance_wallet_rounded,
          background: AppColors.actionPurple,
          foreground: Colors.white,
          onTap: onWithdraw,
        ),
      ],
    );
  }
}

/// Round icon button + label, used for the home dashboard's primary
/// money-movement quick actions.
///
/// Visual spec:
///   - 56dp circle filled with [background]
///   - 24sp [foreground]-tinted rounded icon, centered
///   - 8dp gap below the circle
///   - 12sp w500 [AppColors.onBrand] label, single line, centered
///   - Whole stack is one [InkWell] so the label is part of the
///     affordance (improves a11y + matches user expectations from
///     Cash App / Wise / Revolut)
///
/// The label color stays [AppColors.onBrand] (light) regardless of
/// the circle fill because the label sits on the dark brand-gradient
/// home background, not on the circle.
class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;

  /// Fill color of the 56dp circle.
  final Color background;

  /// Icon tint inside the circle.
  final Color foreground;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // Pull the splash radius in so the highlight tracks the circle
      // rather than spilling over onto the label. Using a square
      // bounding box (the InkWell's natural shape) with a rounded
      // corner gives a soft splash without escaping the button area.
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: foreground,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.homeViewAll,
              style: const TextStyle(
                color: AppColors.onBrandMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
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
    final l10n = AppLocalizations.of(context);
    final insights = <_Insight>[
      _Insight(
        title: l10n.insightSmartRateTitle,
        body: l10n.insightSmartRateBody,
        metric: '+ $currencyCode 10',
        icon: Icons.trending_up_rounded,
        accent: _greenAccent,
        onTap: onSmartRate,
      ),
      _Insight(
        // Trust-score body is ICU-templated so the currency code and
        // limit slot in via gen_l10n placeholders rather than string
        // interpolation — keeps French word order natural.
        title: l10n.insightTrustScoreTitle,
        body: l10n.insightTrustScoreBody(currencyCode, '5,000'),
        metric: '750',
        icon: Icons.verified_user_rounded,
        accent: AppColors.actionPurple,
        onTap: onTrustScore,
      ),
      // Sample third card so the horizontal scroll affordance is real.
      // Replace with backend-driven insights when wired.
      _Insight(
        title: l10n.insightSpendingPulseTitle,
        body: l10n.insightSpendingPulseBody,
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
  const _Favorite({
    required this.name,
    required this.color,
    required this.country,
    required this.nationalPhone,
  });

  final String name;
  final Color color;
  final SupportedCountry country;

  /// National-significant digits only. Leading `0` is preserved (it's
  /// stripped by `phone_numbers_parser` when the country is set), no
  /// dial code, no spaces.
  final String nationalPhone;
}

class _FavoritesStrip extends StatelessWidget {
  const _FavoritesStrip({required this.favorites, required this.onTap});

  final List<_Favorite> favorites;
  final ValueChanged<_Favorite> onTap;

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
          return _FavoriteAvatar(favorite: f, onTap: () => onTap(f));
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
//
// The home dashboard now consumes the public [Transaction] model
// from `domain/transaction.dart` (same model the dedicated
// Transactions tab + detail screen use), so the previous
// home-private `_Txn` + `_TxnKind` types have been retired. Tile
// rendering lives in [_TransactionTile] below.

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.txn,
    required this.currencyCode,
    required this.onTap,
  });

  final Transaction txn;
  final String currencyCode;
  final VoidCallback onTap;

  /// Direction-specific tile glyph + tint. Mirrors the diagonal-arrow
  /// language used on the dedicated Transactions tab so users see the
  /// same visual whichever surface they're on.
  ({IconData icon, Color color}) get _glyph {
    switch (txn.kind) {
      case TxnKind.received:
        return (icon: Icons.south_west_rounded, color: const Color(0xFF22C55E));
      case TxnKind.sent:
        return (icon: Icons.north_east_rounded, color: const Color(0xFFF97316));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final g = _glyph;

    // Map the 3-state [TxnStatus] to a tile color + label. `pending`
    // is rendered amber to distinguish it from success/failed at a
    // glance — this matches the chip palette used on the
    // Transactions tab + detail screen so the design language stays
    // consistent across all three surfaces.
    final (statusColor, statusLabel) = switch (txn.status) {
      TxnStatus.success => (
          const Color(0xFF22C55E),
          l10n.txnStatusSuccess,
        ),
      TxnStatus.pending => (
          const Color(0xFFD97706),
          l10n.txnDetailStatusPending,
        ),
      TxnStatus.failed => (
          const Color(0xFFEF4444),
          l10n.txnStatusFailed,
        ),
    };

    // Tile-row label is derived from the kind enum so the active
    // locale wins; the model itself no longer carries a string label.
    final kindLabel = switch (txn.kind) {
      TxnKind.received => l10n.txnLabelReceived,
      TxnKind.sent => l10n.txnLabelSent,
    };

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
                    kindLabel,
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
