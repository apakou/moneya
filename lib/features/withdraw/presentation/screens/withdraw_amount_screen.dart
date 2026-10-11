import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../../../core/format/money_format.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../core/widgets/dirty_form_scope.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/domain/supported_country.dart';
import '../../../home/domain/supported_currency.dart';
import '../../../load_money/domain/load_money_limits.dart';
import '../../../load_money/domain/momo_provider.dart';
import '../../../transfer/data/transaction_auth_service.dart';
import '../../../transfer/presentation/widgets/amount_keypad_sheet.dart';
import '../../../transfer/presentation/widgets/swipe_to_pay_button.dart';
import '../../../ramp/data/ramp_dtos.dart';
import '../../../ramp/data/ramp_quote_controller.dart';
import '../../../ramp/data/ramp_repository.dart';
import '../../../ramp/data/ramp_submitter.dart';
import '../../../ramp/domain/ramp_mapping.dart';
import '../../../ramp/presentation/ramp_error_text.dart';
import '../../../ramp/presentation/ramp_quote_card.dart';
import '../../../ramp/presentation/ramp_status_screen.dart';

/// Step 2/2 of the Withdraw flow — enter the amount to push from
/// the MoneyA balance out to the chosen mobile-money rail.
///
/// Mirrors [LoadAmountScreen] byte-for-byte in chrome and step-up
/// gating; the semantic deltas are:
///
/// * **Direction of funds** — this debit hits the MoneyA wallet,
///   not the user's external MoMo account. The "To" section labels
///   the *destination* (credit) wallet, and the phone field is the
///   recipient MoMo number to credit.
/// * **Balance constraint** — withdraw amount is capped by the
///   user's available balance ([balanceMinor]) on top of the KYC
///   tier ceiling. Insufficient balance blocks the swipe with an
///   inline error explaining how to recover.
/// * **Three outcomes** — unlike Load (where the only optimistic
///   state is "request sent / authorize on USSD"), withdraw maps to
///   the standard transfer trio: success (rail accepted, money in
///   flight), pending (provider returned 202), failed (4xx/5xx). All
///   three are private screens at the bottom of this file using the
///   shared [TransferOutcomeScaffold] so they stay visually pinned
///   to the Send flow's outcomes.
///
/// Provider catalog + KYC ceiling are reused from the load_money
/// feature — see `WithdrawProviderScreen` for the rationale. When the
/// backend ships, swap [LoadMoneyLimits.defaultFor] for the per-tier
/// payload from `/v1/me/limits`.
class WithdrawAmountScreen extends StatefulWidget {
  const WithdrawAmountScreen({
    required this.currency,
    required this.balanceMinor,
    required this.country,
    required this.provider,
    this.rampRepository,
    super.key,
  });

  /// Test seam.
  final RampRepository? rampRepository;

  final SupportedCurrency currency;

  /// Available wallet balance in [currency] major units. Source of
  /// truth lives on `_HomeScreenState`; threaded through both
  /// withdraw steps so the cap check has no Riverpod dependency yet.
  final num balanceMinor;

  final SupportedCountry country;
  final MomoProvider provider;

  static const String routePath = '/withdraw/amount';

  @override
  State<WithdrawAmountScreen> createState() => _WithdrawAmountScreenState();
}

class _WithdrawAmountScreenState extends State<WithdrawAmountScreen> {
  String _amount = '0';

  final _destinationPhoneController = TextEditingController();
  bool _destinationPhoneValid = false;

  late final LoadMoneyLimits _limits = LoadMoneyLimits.defaultFor(
    widget.currency,
  );

  final TransactionAuthService _authService = const TransactionAuthService();
  bool _authInFlight = false;

  // Price + submit rules (see features/ramp). Injectable for tests.
  late final RampRepository _ramp = widget.rampRepository ?? RampRepository();
  late final RampSubmitter _submitter = RampSubmitter(repository: _ramp);
  late final RampQuoteController _quotes = RampQuoteController(
    fetch: (amount) {
      final cur = RampMapping.wireCurrency(widget.currency);
      return _ramp.quoteOfframp(amount: amount, currency: cur, payoutCurrency: cur);
    },
  )..addListener(_onQuoteChanged);

  void _onQuoteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _quotes
      ..removeListener(_onQuoteChanged)
      ..dispose();
    _destinationPhoneController.dispose();
    super.dispose();
  }

  /// The keypad can leave a trailing dot ("15000."); the API wants a clean decimal.
  String get _wireAmount => _amount.endsWith('.') ? _amount.substring(0, _amount.length - 1) : _amount;

  void _refreshQuote() => _quotes.setAmount(
        _wireAmount,
        valid: _isWithinLimit && !_insufficientBalance,
      );

  // -- Validation -------------------------------------------------------------

  num get _numericAmount {
    final raw = _amount.trim();
    if (raw.isEmpty) return 0;
    return num.tryParse(raw) ?? 0;
  }

  bool get _isWithinLimit => _limits.isWithinLimit(_numericAmount);

  bool get _exceedsLimit =>
      _numericAmount > 0 && _numericAmount > _limits.maxPerTransaction;

  /// Insufficient-balance check. Order matters: we only surface this
  /// error once the user has typed *something* positive — showing
  /// "you only have X" against a 0 amount on first paint reads as
  /// scolding. The KYC cap takes precedence in display: if both fail,
  /// the over-limit error wins because hitting the tier ceiling is
  /// the actionable one (upgrade KYC).
  bool get _insufficientBalance =>
      _numericAmount > 0 && _numericAmount > widget.balanceMinor;

  bool get _canConfirm =>
      _isWithinLimit &&
      !_insufficientBalance &&
      _destinationPhoneValid &&
      _quotes.quote != null &&
      !_quotes.loading;

  /// Dirty if the user has typed *anything* — either bumped the
  /// amount off the initial `'0'` placeholder or entered a digit in
  /// the destination phone field. Used by [DirtyFormScope] to gate
  /// back-navigation behind a discard-changes confirmation.
  bool get _isDirty =>
      _amount != '0' || _destinationPhoneController.text.isNotEmpty;

  bool _validatePhone(String national) {
    if (national.isEmpty) return false;
    try {
      final iso = IsoCode.values.firstWhere(
        (c) => c.name.toUpperCase() == widget.country.isoCode,
      );
      final parsed = PhoneNumber.parse(national, callerCountry: iso);
      return parsed.isValid();
    } catch (_) {
      return false;
    }
  }

  String _formatBalance(num value) {
    // Hand-rolled thousands separator — mirrors `_balanceDisplay` on
    // `_HomeScreenState` so the strings shown across home / withdraw
    // never disagree. Drop in favour of `MoneyFormat` once we land
    // the locale-aware decimal handling everywhere.
    final s = value.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // -- Handlers ---------------------------------------------------------------

  Future<void> _onBack() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    // See LoadAmountScreen._onBack for the deactivated-ancestor
    // rationale. `confirmAndPopIfDirty` captures the navigator
    // before the dialog await and defers the pop to a post-frame.
    await DirtyFormScope.confirmAndPopIfDirty(context, _isDirty);
  }

  Future<void> _onAmountTap() async {
    final picked = await showAmountKeypadSheet(
      context: context,
      currencyCode: widget.currency.code,
      initialAmount: _amount,
    );
    if (picked == null) return;
    setState(() => _amount = picked.isEmpty ? '0' : picked);
    _refreshQuote();
  }

  void _onDestinationPhoneChanged(String value) {
    setState(() {
      _destinationPhoneValid = _validatePhone(value);
    });
  }

  /// `+233201234567` for the typed national number.
  String? _payeeE164() {
    try {
      final iso = IsoCode.values.firstWhere((c) => c.name.toUpperCase() == widget.country.isoCode);
      final parsed = PhoneNumber.parse(_destinationPhoneController.text, callerCountry: iso);
      return parsed.isValid() ? parsed.international : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onConfirm() async {
    final quote = _quotes.quote;
    if (_authInFlight || quote == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final method = RampMapping.paymentMethod(widget.provider);
    final phone = _payeeE164();
    void say(String text) => messenger.showSnackBar(
          SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
        );
    if (method == null) return say(l10n.rampErrorProviderNotSupported);
    if (phone == null) return;

    _authInFlight = true;
    try {
      final result = await _submitter.submitOfframp(
        quote: quote,
        requote: _quotes.requote,
        payoutMethod: method,
        payeeMsisdn: phone,
        // Step-up auth — a single 6-digit passcode entry against the server step-up endpoint.
        stepUp: () => _authService.authenticate(context),
      );
      if (!mounted) return;
      switch (result) {
        case RampPlaced(:final order):
          Get.off<void>(() => RampStatusScreen(order: order, phone: phone));
        case RampRequoted(:final fresh):
          // The price changed: show it and let the user decide. Never swapped in silently.
          // Compare with the price the USER saw (`quote`), not with the controller's current
          // value: re-quoting has already stored the fresh one there.
          _quotes.adopt(fresh);
          if (!quote.differsFrom(fresh)) {
            // Same numbers under a new quote id: nothing new to confirm. Continue (the passcode
            // is asked again: the previous single-use token was spent on the rejected attempt).
            _authInFlight = false;
            await _onConfirm();
            return;
          }
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.rampRequoteTitle),
              content: Text(l10n.rampRequoteBodyPayout(
                '${MoneyFormat.fromString(fresh.toAmount)} ${RampMapping.displayCurrency(fresh.toCurrency)}',
                '${MoneyFormat.fromString(fresh.fee)} ${RampMapping.displayCurrency(fresh.fromCurrency)}',
              )),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.commonCancel)),
                TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.rampRequoteContinue)),
              ],
            ),
          );
          if (go == true && mounted) {
            _authInFlight = false;
            await _onConfirm();
          }
        case RampCancelled():
          break; // the user dismissed the passcode sheet: silent reset
        case RampBlocked(:final message):
          say(message);
        case RampFailed(:final error):
          say(rampErrorText(l10n, error));
      }
    } finally {
      _authInFlight = false;
    }
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      // Guard back against losing typed amount / destination phone.
      // The chevron's `_onBack` and the system back gesture share the
      // same dialog so the user sees identical UX on either path.
      // See flutter-navigation skill §3 & §7.
      child: DirtyFormScope(
        isDirty: _isDirty,
        child: Scaffold(
          backgroundColor: AppColors.black,
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
                    child: Row(
                      children: [
                        BackChevronButton(
                          onTap: _onBack,
                          tooltip: l10n.commonBack,
                        ),
                        Text(
                          l10n.withdrawAmountHeaderTitle,
                          style: AppTextStyles.screenTitle,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Text(
                              l10n.withdrawAmountTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _AmountCard(
                            currencyCode: widget.currency.code,
                            amount: _amount,
                            onTap: _onAmountTap,
                          ),
                          // Error precedence: over-limit before
                          // insufficient-balance. Both can't render at
                          // once because hitting the tier cap implies a
                          // ridiculously high amount that the balance
                          // will always be under anyway.
                          if (_exceedsLimit) ...[
                            const SizedBox(height: 12),
                            _LimitError(
                              message: l10n.withdrawAmountOverLimit(
                                widget.currency.code,
                                _limits.maxPerTransaction.toString(),
                                _limits.tierLabel,
                              ),
                            ),
                          ] else if (_insufficientBalance) ...[
                            const SizedBox(height: 12),
                            _LimitError(
                              message: l10n.withdrawAmountInsufficientBalance(
                                widget.currency.code,
                                _formatBalance(widget.balanceMinor),
                              ),
                            ),
                          ],
                          if (_isWithinLimit && !_insufficientBalance) ...[
                            const SizedBox(height: 16),
                            RampQuoteCard(
                              direction: RampDirection.offramp,
                              quote: _quotes.quote,
                              loading: _quotes.loading,
                              failed: _quotes.failed,
                              onRefresh: _quotes.requote,
                            ),
                          ],
                          const SizedBox(height: 28),

                          // To section -----------------------------------------
                          Text(
                            l10n.withdrawAmountToLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ProviderSummary(
                            country: widget.country,
                            provider: widget.provider,
                          ),
                          const SizedBox(height: 12),
                          _PhoneInput(
                            country: widget.country,
                            controller: _destinationPhoneController,
                            hint: l10n.withdrawAmountDestinationPhoneHint,
                            onChanged: _onDestinationPhoneChanged,
                          ),
                          const SizedBox(height: 28),

                          Text(
                            l10n.withdrawAmountLimitHint(
                              widget.currency.code,
                              _formatBalance(widget.balanceMinor),
                            ),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Opacity(
                      opacity: _canConfirm ? 1.0 : 0.45,
                      child: IgnorePointer(
                        ignoring: !_canConfirm,
                        child: SwipeToPayButton(
                          label: l10n.withdrawAmountSwipeLabel,
                          completionThreshold: 0.7,
                          onCompleted: _onConfirm,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subcomponents — identical to LoadAmountScreen's locals. Duplicated
// rather than promoted to keep the two flows independently editable
// while the surface is still in flux; promote to a shared
// `lib/features/momo/presentation/widgets/` module once a third
// caller (e.g. bill-pay) lands.
// ---------------------------------------------------------------------------

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.currencyCode,
    required this.amount,
    required this.onTap,
  });

  final String currencyCode;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currencyCode,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  amount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderSummary extends StatelessWidget {
  const _ProviderSummary({required this.country, required this.provider});

  final SupportedCountry country;
  final MomoProvider provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          ClipOval(
            child: CountryFlag.fromCountryCode(
              country.isoCode,
              theme: const ImageTheme(width: 28, height: 28, shape: Circle()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneInput extends StatelessWidget {
  const _PhoneInput({
    required this.country,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final SupportedCountry country;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Text(
            '+${country.dialCode}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500,
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitError extends StatelessWidget {
  const _LimitError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D2E).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF4D2E).withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFFB199),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFB199),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Outcomes — three private screens reusing TransferOutcomeScaffold.
//
// All three are terminal: `PopScope(canPop: false)` forces the user
// to exit via a CTA so they can't navigate back into the (replaced)
// amount form and accidentally double-submit. Primary CTA pops to
// home via `Get.until((r) => r.isFirst)` to preserve the outcome →
// home animation (Get.offAllNamed would rebuild the shell from
// scratch).
//
// The Failed screen's "Try again" pops the outcome itself; the
// underlying amount form is still alive because we used `Get.off`
// (replacement) only when leaving the form, not the wizard. The user
// lands back on the form with state intact — including the same
// idempotency key in the auth service — so retries are safe.
// ---------------------------------------------------------------------------
