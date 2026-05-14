import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../main.dart' show LocaleScope;
import '../../domain/transaction.dart';
import '../widgets/home_header.dart';
import '../widgets/notifications_sheet.dart';
import 'profile_screen.dart';
import 'transaction_detail_screen.dart';

/// Transactions tab — full history view reached from the bottom-nav
/// `Transactions` button on [HomeShell].
///
/// Layout (per design mock):
/// * Top row reuses the home-tab header: avatar + user name, with a
///   language pill and a notifications pill on the right. We don't
///   render a [Scaffold] here because [HomeShell] already provides
///   the bottom nav; the gradient + safe-area padding are owned by
///   this widget.
/// * Centered `Your Transactions` title with a small export pill on
///   the right (CSV download — stubbed for now).
/// * Filter row: status chips (`Sent`, `Received`, `Succeeded`,
///   `Pending`, `Failed`) wrapping over multiple lines. The chips
///   are **single-select** — tapping the active chip again clears
///   the filter.
/// * Scrollable list of transaction rows grouped by month-year, with
///   **sticky section headers** that pin to the top of the viewport
///   as the user scrolls past them (iOS Contacts behaviour). Header
///   format follows the user's locale: months in the current year
///   render as `June`; older months include the year, e.g. `June 2024`.
///
/// Data is currently a hardcoded list of [Transaction] items matching the
/// mock. Will move to a Riverpod provider backed by `GET /transfers`
/// once the backend lands. The grouping logic stays in the widget —
/// it's pure-derived state from a flat list.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  static const String _userName = 'John Doe';
  static const String _currencyCode = 'GHC';

  /// Currently selected filter; `null` means "All". Single-select on
  /// purpose — combining filters (e.g., Sent + Failed) gets ambiguous
  /// fast and the design doesn't suggest multi-select.
  _TxnFilter? _activeFilter;

  /// Scroll controller wired to the inner [CustomScrollView]. Used to
  /// detect which month-year group is currently leading the viewport
  /// so the static label above the list can update accordingly.
  late final ScrollController _scrollController;

  /// Cached groups for the current filter. Recomputed in [_rebuildGroups]
  /// (called from [initState] and after every filter toggle) rather
  /// than on every scroll tick — the latter would also rebuild the
  /// `GlobalKey`s and break the scroll-position lookup.
  List<_TxnGroup> _groups = const [];

  /// One [GlobalKey] per group, attached to that group's first row.
  /// We probe each key's `RenderObject` in [_onScroll] to figure out
  /// which group is currently the topmost in the viewport.
  ///
  /// Stored alongside [_groups] (not on `_TxnGroup` itself) so the
  /// data class stays plain.
  List<GlobalKey> _groupKeys = const [];

  /// Index into [_groups] of the month-year currently shown in the
  /// static label above the list. Defaults to `0` so the label is
  /// already correct before the user scrolls.
  int _currentGroupIndex = 0;

  // Hardcoded mock data spanning multiple months/years so the
  // section-header logic actually has something to group. Newest
  // first; the grouping pass below preserves order within each
  // group. Will be replaced by a Riverpod-backed provider hitting
  // `GET /transfers` once the backend lands.
  // Rotating counterparty pool. Each transaction picks a name by
  // index modulo this list so the demo data looks plausibly varied
  // without having to hand-author 35 unique relationships. Mixed
  // francophone / anglophone West-African names to match our
  // BCEAO-corridor target market.
  static const List<String> _counterparties = [
    'Axel Asamoa',
    'Maria Diop',
    'Kwame Nkrumah',
    'Aminata Traoré',
    'Chinedu Okafor',
    'Fatou Sow',
    'Yao Mensah',
    'Adjoa Boateng',
  ];

  // Phone numbers paired 1:1 with [_counterparties]. E.164 format,
  // mostly Ghanaian (+233) with a couple of Senegalese (+221) and
  // Ivorian (+225) entries to demo cross-corridor mocks.
  static const List<String> _counterpartyPhones = [
    '+233241234567',
    '+221771234567',
    '+233244987654',
    '+223761122334',
    '+2348012345678',
    '+221785551122',
    '+233246778899',
    '+233247223344',
  ];

  // Pool of payment-method labels we cycle through. The format
  // mirrors what we'll show on the confirm screen once the backend
  // returns method metadata: "<rail> • <provider>".
  static const List<String> _paymentMethods = [
    'Mobile Money • MTN MoMo',
    'Mobile Money • Vodafone Cash',
    'Mobile Money • Orange Money',
    'Mobile Money • Wave',
    'Bank Transfer • Ecobank',
    'Bank Transfer • GCB Bank',
    'Mobile Money • Moov Money',
    'Mobile Money • AirtelTigo Money',
  ];

  /// Builds a [Transaction] for index `i` of the mock dataset. Pairs
  /// the index with the counterparty / phone / method pools so each
  /// row has consistent metadata; the reference id is a deterministic
  /// 8-char slice (uppercase hex of `i`-padded), and the fee is a
  /// flat 0.5% with a `50` floor on `sent` rows, `0` on `received`.
  static Transaction _mock({
    required int i,
    required TxnKind kind,
    required DateTime when,
    required String amount,
    required TxnStatus status,
  }) {
    final amt = int.tryParse(amount) ?? 0;
    final fee = kind == TxnKind.received
        ? '0'
        : (amt * 5 ~/ 1000).clamp(50, 1 << 30).toString();
    final ref = 'TX${(i * 0x9E37 + 0x1A2B).toRadixString(16).toUpperCase().padLeft(6, '0').substring(0, 6)}';
    return Transaction(
      id: ref,
      kind: kind,
      when: when,
      amount: amount,
      fee: fee,
      status: status,
      counterparty: _counterparties[i % _counterparties.length],
      counterpartyPhone:
          _counterpartyPhones[i % _counterpartyPhones.length],
      paymentMethod: _paymentMethods[i % _paymentMethods.length],
    );
  }

  // Hardcoded mock data spanning multiple months/years so the
  // section-header logic actually has something to group. Newest
  // first; the grouping pass below preserves order within each
  // group. Will be replaced by a Riverpod-backed provider hitting
  // `GET /transfers` once the backend lands.
  static final List<Transaction> _all = [
    _mock(i: 0, kind: TxnKind.received, when: DateTime(2025, 6, 12, 10, 25), amount: '13000', status: TxnStatus.success),
    _mock(i: 1, kind: TxnKind.sent, when: DateTime(2025, 6, 12, 10, 25), amount: '2500', status: TxnStatus.failed),
    _mock(i: 2, kind: TxnKind.received, when: DateTime(2025, 6, 11, 21, 14), amount: '56300', status: TxnStatus.success),
    _mock(i: 3, kind: TxnKind.sent, when: DateTime(2025, 6, 11, 18, 02), amount: '4000', status: TxnStatus.pending),
    _mock(i: 4, kind: TxnKind.received, when: DateTime(2025, 5, 28, 14, 41), amount: '8000', status: TxnStatus.success),
    _mock(i: 5, kind: TxnKind.sent, when: DateTime(2025, 5, 22, 09, 03), amount: '15000', status: TxnStatus.success),
    _mock(i: 6, kind: TxnKind.received, when: DateTime(2024, 12, 30, 19, 50), amount: '20000', status: TxnStatus.success),
    _mock(i: 7, kind: TxnKind.sent, when: DateTime(2024, 12, 11, 11, 22), amount: '6500', status: TxnStatus.failed),
    _mock(i: 8, kind: TxnKind.sent, when: DateTime(2025, 6, 10, 16, 47), amount: '1200', status: TxnStatus.success),
    _mock(i: 9, kind: TxnKind.received, when: DateTime(2025, 6, 7, 08, 12), amount: '34500', status: TxnStatus.pending),
    _mock(i: 10, kind: TxnKind.sent, when: DateTime(2025, 6, 3, 22, 38), amount: '950', status: TxnStatus.success),
    _mock(i: 11, kind: TxnKind.received, when: DateTime(2025, 5, 18, 12, 04), amount: '7800', status: TxnStatus.success),
    _mock(i: 12, kind: TxnKind.sent, when: DateTime(2025, 5, 9, 17, 26), amount: '24000', status: TxnStatus.failed),
    _mock(i: 13, kind: TxnKind.received, when: DateTime(2025, 5, 2, 06, 51), amount: '11200', status: TxnStatus.success),
    _mock(i: 14, kind: TxnKind.sent, when: DateTime(2025, 4, 27, 13, 33), amount: '5000', status: TxnStatus.pending),
    _mock(i: 15, kind: TxnKind.received, when: DateTime(2025, 4, 19, 20, 09), amount: '9300', status: TxnStatus.success),
    _mock(i: 16, kind: TxnKind.sent, when: DateTime(2025, 4, 14, 11, 55), amount: '3200', status: TxnStatus.success),
    _mock(i: 17, kind: TxnKind.received, when: DateTime(2025, 4, 5, 09, 18), amount: '47500', status: TxnStatus.success),
    _mock(i: 18, kind: TxnKind.sent, when: DateTime(2025, 3, 24, 19, 02), amount: '1850', status: TxnStatus.failed),
    _mock(i: 19, kind: TxnKind.received, when: DateTime(2025, 3, 11, 15, 41), amount: '6700', status: TxnStatus.success),
    _mock(i: 20, kind: TxnKind.sent, when: DateTime(2025, 3, 4, 08, 27), amount: '12500', status: TxnStatus.success),
    _mock(i: 21, kind: TxnKind.received, when: DateTime(2025, 2, 21, 17, 13), amount: '3400', status: TxnStatus.pending),
    _mock(i: 22, kind: TxnKind.sent, when: DateTime(2025, 2, 13, 10, 06), amount: '8800', status: TxnStatus.success),
    _mock(i: 23, kind: TxnKind.received, when: DateTime(2025, 1, 29, 21, 44), amount: '15600', status: TxnStatus.success),
    _mock(i: 24, kind: TxnKind.sent, when: DateTime(2025, 1, 17, 14, 29), amount: '4200', status: TxnStatus.failed),
    _mock(i: 25, kind: TxnKind.received, when: DateTime(2025, 1, 6, 07, 35), amount: '29000', status: TxnStatus.success),
    _mock(i: 26, kind: TxnKind.sent, when: DateTime(2024, 11, 26, 18, 50), amount: '7100', status: TxnStatus.success),
    _mock(i: 27, kind: TxnKind.received, when: DateTime(2024, 11, 14, 12, 22), amount: '52800', status: TxnStatus.success),
    _mock(i: 28, kind: TxnKind.sent, when: DateTime(2024, 11, 3, 09, 47), amount: '2300', status: TxnStatus.pending),
    _mock(i: 29, kind: TxnKind.received, when: DateTime(2024, 10, 22, 16, 11), amount: '18400', status: TxnStatus.success),
    _mock(i: 30, kind: TxnKind.sent, when: DateTime(2024, 10, 8, 20, 03), amount: '6900', status: TxnStatus.failed),
    _mock(i: 31, kind: TxnKind.received, when: DateTime(2024, 9, 30, 11, 38), amount: '4100', status: TxnStatus.success),
    _mock(i: 32, kind: TxnKind.sent, when: DateTime(2024, 9, 12, 15, 24), amount: '13700', status: TxnStatus.success),
    _mock(i: 33, kind: TxnKind.received, when: DateTime(2024, 8, 19, 19, 09), amount: '8500', status: TxnStatus.success),
    _mock(i: 34, kind: TxnKind.sent, when: DateTime(2024, 7, 7, 13, 52), amount: '21000', status: TxnStatus.success),
    _mock(i: 35, kind: TxnKind.received, when: DateTime(2023, 12, 28, 22, 16), amount: '36200', status: TxnStatus.success),
    _mock(i: 36, kind: TxnKind.sent, when: DateTime(2023, 11, 15, 10, 41), amount: '5400', status: TxnStatus.failed),
    _mock(i: 37, kind: TxnKind.received, when: DateTime(2023, 8, 4, 17, 08), amount: '14800', status: TxnStatus.success),
  ];

  List<Transaction> get _filtered {
    final f = _activeFilter;
    if (f == null) return _all;
    return _all.where((t) {
      switch (f) {
        case _TxnFilter.sent:
          return t.kind == TxnKind.sent;
        case _TxnFilter.received:
          return t.kind == TxnKind.received;
        case _TxnFilter.succeeded:
          return t.status == TxnStatus.success;
        case _TxnFilter.pending:
          return t.status == TxnStatus.pending;
        case _TxnFilter.failed:
          return t.status == TxnStatus.failed;
      }
    }).toList();
  }

  /// Group [_filtered] into ordered `(year, month)` buckets, newest
  /// first. We rely on [_all] already being sorted descending by
  /// timestamp; if that ever changes, this helper would need an
  /// explicit sort first.
  ///
  /// Mutates [_groups] + [_groupKeys] together so they always have
  /// matching length and stable identity across scroll ticks. Keys
  /// are *recreated* whenever the filter changes — that's fine
  /// because the `CustomScrollView` is also rebuilt with the new
  /// keys in the same frame.
  void _rebuildGroups() {
    final groups = <_TxnGroup>[];
    for (final t in _filtered) {
      final y = t.when.year;
      final m = t.when.month;
      if (groups.isNotEmpty &&
          groups.last.year == y &&
          groups.last.month == m) {
        groups.last.items.add(t);
      } else {
        groups.add(_TxnGroup(year: y, month: m, items: [t]));
      }
    }
    _groups = groups;
    _groupKeys = List.generate(groups.length, (_) => GlobalKey());
    _currentGroupIndex = 0;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _rebuildGroups();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Walks [_groupKeys] and finds the *last* group whose first row
  /// has scrolled to or past the top of the viewport. That group's
  /// month-year is what the static label above the list should show.
  ///
  /// Why "last and not first": a single group can span many rows, so
  /// the same group remains leading for a long stretch of scrolling.
  /// We pick the deepest matching index so transitioning into a new
  /// group flips the label the moment its first row reaches the top.
  ///
  /// Why we tolerate `currentContext == null`: rows below the
  /// viewport in a `SliverList` are unbuilt by design, so their keys
  /// have no context. Treat null as "not yet at top" and continue —
  /// don't break, because a *later* off-screen group is also not
  /// leading and we just want to skip it.
  ///
  /// O(groups) per scroll tick. With ~15-25 month buckets this is
  /// trivial; if the dataset ever explodes we can switch to a binary
  /// search since group offsets are monotonically increasing.
  void _onScroll() {
    if (_groups.isEmpty) return;
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    int leading = 0;
    for (var i = 0; i < _groupKeys.length; i++) {
      final ctx = _groupKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final viewport = RenderAbstractViewport.of(box);
      final reveal = viewport.getOffsetToReveal(box, 0).offset;
      // 1px slack so we're not at the mercy of rounding when the row
      // is exactly aligned with the viewport top.
      if (reveal <= offset + 1) {
        leading = i;
      } else {
        // Groups are ordered top-to-bottom; once one is below the
        // top, every later one is too.
        break;
      }
    }

    if (leading != _currentGroupIndex) {
      setState(() => _currentGroupIndex = leading);
    }
  }

  void _toggleFilter(_TxnFilter f) {
    setState(() {
      _activeFilter = _activeFilter == f ? null : f;
      _rebuildGroups();
    });
    // Jump back to the top so the new first group's label matches
    // what the user actually sees. `hasClients` guard because the
    // controller may not be attached on the very first build frame
    // when filters can't yet be toggled anyway, but cheap insurance.
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    // Re-evaluate the leading group after the new tree has laid out.
    // `jumpTo(0)` won't fire the listener if offset was already 0,
    // and even when it does fire the new GlobalKeys haven't attached
    // their RenderBoxes yet on this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  void _onProfileTap() {
    Get.to<void>(() => const ProfileScreen());
  }
  void _onLanguageTap() {
    // Flip app-wide locale; the InheritedNotifier surfaces the
    // change to every screen that reads from LocaleScope. Fire-and-
    // forget — persistence happens inside the controller.
    LocaleScope.of(context, listen: false).toggle();
  }
  void _onNotificationsTap() => showNotificationsSheet(context);
  void _onExportTap() => AppLogger.i('transactions.export.tap', const {});
  void _onTxnTap(Transaction t) {
    Get.to<void>(
      () => TransactionDetailScreen(
        txn: t,
        currencyCode: _currencyCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Active locale tag drives `intl`'s month-name table (en/fr).
    // Reading via LocaleScope ensures the screen rebuilds on toggle.
    final localeTag = LocaleScope.of(context).current.tag;
    final groups = _groups;
    final currentYear = DateTime.now().year;
    final hasGroups = groups.isNotEmpty;
    // Clamp the index in case a filter change reduced the group count
    // before _onScroll has had a chance to run.
    final safeIndex = hasGroups
        ? _currentGroupIndex.clamp(0, groups.length - 1)
        : 0;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: SafeArea(
        // Don't reserve the bottom safe-area here — we want the list
        // to extend behind the bottom nav (Scaffold has
        // `extendBody: true`). The last row's clearance is handled
        // by a SliverPadding at the tail of the slivers below.
        bottom: false,
        child: Padding(
          // Horizontal-only outer padding. Vertical bottom padding
          // would clip the list above the nav and defeat the
          // "scrolls behind" effect.
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeHeader(
                userName: _userName,
                // Mirror the app-wide locale so the flag pill matches
                // the home tab without each tab keeping its own copy
                // of the language state.
                language: LocaleScope.of(context).current == AppLocale.fr
                    ? UiLanguage.fr
                    : UiLanguage.en,
                onProfileTap: _onProfileTap,
                onLanguageTap: _onLanguageTap,
                onNotificationsTap: _onNotificationsTap,
              ),
              const SizedBox(height: 24),
              _TitleRow(onExportTap: _onExportTap),
              const SizedBox(height: 20),
              _FilterRow(
                active: _activeFilter,
                onToggle: _toggleFilter,
              ),
              // Static month-year label sitting between the filter
              // chips and the scrollable list. It mirrors whichever
              // group is currently leading the viewport — replaced
              // (not stacked) as the user scrolls. Hidden when there
              // are no groups (empty filter result).
              if (hasGroups) ...[
                const SizedBox(height: 16),
                _CurrentMonthLabel(
                  // Animated swap so the label change reads as a
                  // single-source-of-truth update rather than a
                  // jarring text replacement.
                  label: _formatHeader(
                    groups[safeIndex].year,
                    groups[safeIndex].month,
                    currentYear,
                    localeTag,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: !hasGroups
                    ? const _EmptyState()
                    : CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          for (var gi = 0; gi < groups.length; gi++)
                            SliverList.separated(
                              itemCount: groups[gi].items.length,
                              separatorBuilder: (_, _) => Divider(
                                color: Colors.white.withValues(alpha: 0.06),
                                height: 1,
                              ),
                              itemBuilder: (_, i) => _TransactionTile(
                                // First row of each group carries
                                // the group's GlobalKey so we can
                                // probe its position in `_onScroll`.
                                key: i == 0 ? _groupKeys[gi] : null,
                                txn: groups[gi].items[i],
                                currencyCode: _currencyCode,
                                onTap: () => _onTxnTap(groups[gi].items[i]),
                              ),
                            ),
                          // Tail spacer that clears the bottom nav
                          // *and* the floating voice FAB.
                          //
                          // Geometry: bottom nav is 64dp tall, the
                          // voice FAB halo is 100dp centered on the
                          // nav, so it overhangs the nav top by ~50dp.
                          // The Scaffold has `extendBody: true`, so
                          // intermediate rows scroll *behind* the
                          // nav by design — but the *last* row needs
                          // to settle high enough to clear the FAB
                          // halo, otherwise it sits permanently
                          // covered. Add a small breathing margin
                          // so the row isn't kissing the halo edge.
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height:
                                  64 + // nav height
                                  50 + // FAB halo overhang above nav
                                  MediaQuery.viewPaddingOf(context).bottom +
                                  16, // breathing room
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

// ---------------------------------------------------------------------------
// Header label formatting
// ---------------------------------------------------------------------------

/// `June` for months in [currentYear], `June 2024` for older months —
/// localised via `intl`'s `DateFormat`. The [localeTag] ('en', 'fr',
/// …) is threaded down from the active app locale so French UI shows
/// `juin` / `juin 2024`, English shows `June` / `June 2024`.
///
/// Lives at the top level (not in `_TransactionsScreenState`) so the
/// `SliverPersistentHeader` delegate can build labels without needing
/// a back-reference to the state object.
String _formatHeader(int year, int month, int currentYear, String localeTag) {
  // Use day=1 because the day-of-month doesn't matter for a month
  // header; only the month + year segments are read.
  final date = DateTime(year, month);
  if (year == currentYear) {
    // 'LLLL' = stand-alone full month name (correct nominative case
    // in languages that distinguish — e.g. Russian; harmless in
    // English/French where it matches 'MMMM').
    return DateFormat.MMMM(localeTag).format(date);
  }
  return DateFormat.yMMMM(localeTag).format(date);
}

// ---------------------------------------------------------------------------
// Header — _TopRow + _SquareIconButton previously lived here. Both
// were lifted into widgets/home_header.dart (HomeHeader +
// HomeIconButton) so the transactions and home tabs share the same
// chrome. Only the title row stays screen-local because the export
// pill it carries is specific to this screen.
// ---------------------------------------------------------------------------

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.onExportTap});

  final VoidCallback onExportTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          l10n.transactionsTitle,
          style: AppTextStyles.sectionTitle,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: HomeIconButton(
            tooltip: l10n.transactionsExportTooltip,
            onTap: onExportTap,
            child: const Icon(
              Icons.file_download_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter row
// ---------------------------------------------------------------------------

enum _TxnFilter { sent, received, succeeded, pending, failed }

/// Localised label for a [_TxnFilter] chip.
///
/// Implemented as a free function (not an extension getter) because
/// it needs the [AppLocalizations] handle and extensions can't accept
/// a `BuildContext`. Callers pass the resolved `l10n` object so we
/// only do the lookup once per build.
String _txnFilterLabel(_TxnFilter f, AppLocalizations l10n) {
  switch (f) {
    case _TxnFilter.sent:
      return l10n.txnFilterSent;
    case _TxnFilter.received:
      return l10n.txnFilterReceived;
    case _TxnFilter.succeeded:
      return l10n.txnFilterSucceeded;
    case _TxnFilter.pending:
      return l10n.txnFilterPending;
    case _TxnFilter.failed:
      return l10n.txnFilterFailed;
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.active, required this.onToggle});

  final _TxnFilter? active;
  final ValueChanged<_TxnFilter> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final f in _TxnFilter.values)
          _FilterChip(
            label: _txnFilterLabel(f, l10n),
            selected: active == f,
            onTap: () => onToggle(f),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.06);
    final borderColor = selected
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.12);
    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: borderColor)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Static "current month-year" label
// ---------------------------------------------------------------------------

/// Single non-scrolling month-year label that sits between the filter
/// chips and the scrollable list. Driven by
/// `_TransactionsScreenState._currentGroupIndex`, which is updated as
/// the user scrolls and detects which group is currently leading the
/// viewport.
///
/// Animated swap (cross-fade + brief vertical slide) so the change
/// reads as the same label updating rather than two separate labels
/// flashing in and out.
class _CurrentMonthLabel extends StatelessWidget {
  const _CurrentMonthLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) {
          // Slide up + fade in for the new label, slide up + fade out
          // for the old one. The shared parent SizedBox keeps the
          // surrounding layout from jumping during the swap.
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: Align(
          // ValueKey on the label means AnimatedSwitcher actually
          // sees it as a "new" widget when the text changes.
          key: ValueKey(label),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction list
// ---------------------------------------------------------------------------

/// One month-year bucket of transactions. `items` keep the order of
/// the source list (i.e., newest-first within the bucket).
class _TxnGroup {
  _TxnGroup({required this.year, required this.month, required this.items});

  final int year;
  final int month;
  final List<Transaction> items;
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    super.key,
    required this.txn,
    required this.currencyCode,
    required this.onTap,
  });

  final Transaction txn;
  final String currencyCode;
  final VoidCallback onTap;

  ({IconData icon, Color color}) get _glyph {
    switch (txn.kind) {
      case TxnKind.received:
        return (
          icon: Icons.south_west_rounded,
          color: const Color(0xFF22C55E),
        );
      case TxnKind.sent:
        return (
          icon: Icons.north_east_rounded,
          color: const Color(0xFFF97316),
        );
    }
  }

  ({Color color, String label}) _statusBadge(AppLocalizations l10n) {
    switch (txn.status) {
      case TxnStatus.success:
        return (
          color: const Color(0xFF22C55E),
          label: l10n.txnStatusSuccess,
        );
      case TxnStatus.pending:
        return (
          color: const Color(0xFFF5A524),
          label: l10n.txnStatusPending,
        );
      case TxnStatus.failed:
        return (
          color: const Color(0xFFEF4444),
          label: l10n.txnStatusFailed,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final g = _glyph;
    final s = _statusBadge(l10n);
    // Direction label is resolved from the kind enum at render time
    // (rather than reading `txn.directionLabel` from the model) so
    // the tile follows the active locale. The model getter is still
    // used by debug logs and the detail screen until that is migrated.
    final directionLabel = switch (txn.kind) {
      TxnKind.sent => l10n.txnLabelSent,
      TxnKind.received => l10n.txnLabelReceived,
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
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
                    directionLabel,
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
                  s.label,
                  style: TextStyle(
                    color: s.color,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l10n.transactionsEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
