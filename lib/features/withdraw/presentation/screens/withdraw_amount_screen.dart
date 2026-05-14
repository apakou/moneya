import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../../../core/logging/app_logger.dart';
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
import '../../../transfer/presentation/widgets/transfer_outcome_scaffold.dart';

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
    super.key,
  });

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

  final TransactionAuthService _authService = TransactionAuthService();
  bool _authInFlight = false;

  @override
  void dispose() {
    _destinationPhoneController.dispose();
    super.dispose();
  }

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
      _isWithinLimit && !_insufficientBalance && _destinationPhoneValid;

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
  }

  void _onDestinationPhoneChanged(String value) {
    setState(() {
      _destinationPhoneValid = _validatePhone(value);
    });
  }

  Future<void> _onConfirm() async {
    if (_authInFlight) return;
    _authInFlight = true;
    try {
      final result = await _authService.authenticate(context);
      if (!mounted) return;
      switch (result) {
        case TransactionAuthResult.success:
          // TODO(withdraw): call `POST /v1/withdrawals` with the
          // Idempotency-Key + X-Txn-Token from the auth service.
          // Map response → success / pending / failed outcome. The
          // stub below goes straight to success so the happy path is
          // demo-able; flip the constant locally to exercise the
          // other two outcomes when designing copy.
          AppLogger.i('withdraw.submit.stub', {
            'currency': widget.currency.code,
            'amount': _amount,
            'provider': widget.provider.id,
            'country': widget.country.isoCode,
          });
          Get.off<void>(
            () => _WithdrawSuccessScreen(
              amount: _amount,
              currency: widget.currency,
              provider: widget.provider,
            ),
          );
          return;
        case TransactionAuthResult.cancelled:
        case TransactionAuthResult.failed:
          break;
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

class _WithdrawSuccessScreen extends StatelessWidget {
  const _WithdrawSuccessScreen({
    required this.amount,
    required this.currency,
    required this.provider,
  });

  final String amount;
  final SupportedCurrency currency;
  final MomoProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: TransferOutcomeScaffold(
        glyphColor: const Color(0xFF2BC46A),
        glyphIcon: Icons.check_rounded,
        title: l10n.withdrawSuccessTitle,
        body: TransferOutcomeBody(
          spans: [
            TransferOutcomeBody.muted(l10n.withdrawSuccessBodyPrefix),
            TransferOutcomeBody.bold('${currency.code} $amount'),
            TransferOutcomeBody.muted(
              l10n.withdrawSuccessBodySuffix(provider.label),
            ),
          ],
        ),
        primaryLabel: l10n.withdrawSuccessPrimaryCta,
        onPrimary: () => Get.until((r) => r.isFirst),
        secondaryLabel: l10n.withdrawSuccessSecondaryCta,
        onSecondary: () => Get.until((r) => r.isFirst),
      ),
    );
  }
}

// ignore: unused_element
class _WithdrawPendingScreen extends StatelessWidget {
  const _WithdrawPendingScreen({
    required this.amount,
    required this.currency,
    required this.provider,
  });

  final String amount;
  final SupportedCurrency currency;
  final MomoProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: TransferOutcomeScaffold(
        glyphColor: const Color(0xFFFFC93D),
        glyphIcon: Icons.schedule_rounded,
        title: l10n.withdrawPendingTitle,
        body: TransferOutcomeBody(
          spans: [
            TransferOutcomeBody.muted(l10n.withdrawPendingBodyPrefix),
            TransferOutcomeBody.bold('${currency.code} $amount'),
            TransferOutcomeBody.muted(
              l10n.withdrawPendingBodySuffix(provider.label),
            ),
          ],
        ),
        primaryLabel: l10n.withdrawPendingPrimaryCta,
        onPrimary: () => Get.until((r) => r.isFirst),
        secondaryLabel: l10n.withdrawPendingSecondaryCta,
        // TODO(withdraw): wire to transaction-detail route once the
        // backend assigns us a txn id from `/v1/withdrawals` 202.
        onSecondary: () => Get.until((r) => r.isFirst),
      ),
    );
  }
}

// ignore: unused_element
class _WithdrawFailedScreen extends StatelessWidget {
  const _WithdrawFailedScreen({
    required this.amount,
    required this.currency,
    required this.provider,
  });

  final String amount;
  final SupportedCurrency currency;
  final MomoProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: TransferOutcomeScaffold(
        glyphColor: const Color(0xFFFF4D2E),
        glyphIcon: Icons.close_rounded,
        title: l10n.withdrawFailedTitle,
        body: TransferOutcomeBody(
          spans: [
            TransferOutcomeBody.muted(l10n.withdrawFailedBodyPrefix),
            TransferOutcomeBody.bold('${currency.code} $amount'),
            TransferOutcomeBody.muted(
              l10n.withdrawFailedBodySuffix(provider.label),
            ),
          ],
        ),
        primaryLabel: l10n.withdrawFailedPrimaryCta,
        // "Try again": pop just the outcome. The amount form is still
        // mounted underneath because we used `Get.off` to replace the
        // amount → outcome route only — the wizard's earlier routes
        // are untouched. The auth-service's idempotency key is
        // preserved across the retry so a second tap with the same
        // (amount, recipient) is server-side idempotent.
        onPrimary: () => Get.back<void>(),
        secondaryLabel: l10n.withdrawFailedSecondaryCta,
        onSecondary: () => Get.until((r) => r.isFirst),
      ),
    );
  }
}
