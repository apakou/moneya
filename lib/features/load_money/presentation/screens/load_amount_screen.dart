import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../core/widgets/dirty_form_scope.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/domain/supported_country.dart';
import '../../../home/domain/supported_currency.dart';
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
import '../../../../core/format/money_format.dart';
import '../../domain/load_money_limits.dart';
import '../../domain/momo_provider.dart';

/// Step 2/2 of the Load Money flow — enter the amount to pull from
/// the chosen mobile-money rail into the MoneyA balance.
///
/// Layout mirrors `TransferMoneyScreen` so the user feels at home:
/// brand-gradient background, header chevron + title, large
/// tappable amount card opening [showAmountKeypadSheet], then a
/// single "From" section with the locked provider + editable source
/// phone. Confirmation uses [SwipeToPayButton] + the shared
/// [showTransactionPasscodeSheet] (mirroring the Send flow exactly —
/// both flows are debits, so the step-up requirements are the same).
///
/// Validation rules:
/// * Amount > 0 AND <= [LoadMoneyLimits.maxPerTransaction] for the
///   user's currency. Exceeding the cap shows an inline error
///   pointing at the KYC tier — the user can still see the keypad
///   and adjust without re-navigating.
/// * Source phone is a valid number for [country] per
///   `phone_numbers_parser`. Invalid → swipe stays disabled.
///
/// On confirm we don't talk to a backend yet — just push a
/// success outcome screen. The `// TODO` markers are where the real
/// onramp API call, idempotency key, and KYC-tier check will land.
class LoadAmountScreen extends StatefulWidget {
  const LoadAmountScreen({
    required this.currency,
    required this.country,
    required this.provider,
    this.rampRepository,
    super.key,
  });

  final SupportedCurrency currency;
  final SupportedCountry country;
  final MomoProvider provider;

  /// Test seam.
  final RampRepository? rampRepository;

  static const String routePath = '/load/amount';

  @override
  State<LoadAmountScreen> createState() => _LoadAmountScreenState();
}

class _LoadAmountScreenState extends State<LoadAmountScreen> {
  // Numeric string from the keypad (e.g. "15000" or "15000.50"). We
  // keep it as a string rather than a double so trailing decimals
  // entered by the user are preserved verbatim until we format for
  // display — same convention as TransferMoneyScreen._amount.
  String _amount = '0';

  final _sourcePhoneController = TextEditingController();
  bool _sourcePhoneValid = false;

  late final LoadMoneyLimits _limits = LoadMoneyLimits.defaultFor(
    widget.currency,
  );

  // Shared biometric-first → 6-digit passcode (single-entry) auth.
  // Same instance pattern as PaymentConfirmScreen so the Load flow
  // inherits any future changes to the step-up policy without
  // diverging.
  final TransactionAuthService _authService = const TransactionAuthService();

  // Re-entrancy guard. Swipe gestures can fire twice if the user
  // releases at exactly the completion threshold; without this the
  // biometric prompt opens, races with itself, and crashes.
  bool _authInFlight = false;

  // Price + submit rules (see features/ramp). Injectable for tests.
  late final RampRepository _ramp = widget.rampRepository ?? RampRepository();
  late final RampSubmitter _submitter = RampSubmitter(repository: _ramp);
  late final RampQuoteController _quotes = RampQuoteController(
    fetch: (amount) => _ramp.quoteOnramp(
      currency: RampMapping.wireCurrency(widget.currency),
      amount: amount,
    ),
  )..addListener(_onQuoteChanged);

  void _onQuoteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _quotes
      ..removeListener(_onQuoteChanged)
      ..dispose();
    _sourcePhoneController.dispose();
    super.dispose();
  }

  /// The keypad can leave a trailing dot ("15000."); the API wants a clean decimal.
  String get _wireAmount => _amount.endsWith('.') ? _amount.substring(0, _amount.length - 1) : _amount;

  void _refreshQuote() => _quotes.setAmount(_wireAmount, valid: _isWithinLimit);

  // -- Validation -------------------------------------------------------------

  /// Parsed numeric amount. Returns `0` for empty / unparseable input
  /// so [_isWithinLimit] short-circuits cleanly instead of throwing.
  num get _numericAmount {
    final raw = _amount.trim();
    if (raw.isEmpty) return 0;
    return num.tryParse(raw) ?? 0;
  }

  bool get _isWithinLimit => _limits.isWithinLimit(_numericAmount);

  bool get _exceedsLimit =>
      _numericAmount > 0 && _numericAmount > _limits.maxPerTransaction;

  /// Swipe-to-pay enabled state: every required field has to be
  /// valid. Mirrors `_canConfirm` on TransferMoneyScreen.
  bool get _canConfirm =>
      _isWithinLimit && _sourcePhoneValid && _quotes.quote != null && !_quotes.loading;

  /// Whether the user has entered anything worth confirming-before-
  /// discarding. Amount stays at the initial `'0'` until the keypad
  /// is used; source phone starts empty. Either being populated is
  /// enough to trigger the discard prompt.
  ///
  /// Reset to clean by clearing both fields (we don't currently
  /// expose a manual reset, but the form is also dropped from the
  /// stack via `Get.off` on successful submit, so re-prompt on the
  /// post-submit back path is structurally impossible).
  bool get _isDirty {
    final hasAmount = _amount.isNotEmpty && _amount != '0';
    final hasPhone = _sourcePhoneController.text.trim().isNotEmpty;
    return hasAmount || hasPhone;
  }

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

  // -- Handlers ---------------------------------------------------------------

  /// Pop the route safely, prompting to discard typed input first.
  ///
  /// Forms with a focused `TextField` race the route-pop against
  /// focus-scope teardown: when the user taps back with the keyboard
  /// up, the `TextField` element gets deactivated while focus
  /// listeners are still walking the tree, throwing the "Looking up
  /// a deactivated widget's ancestor" error.
  ///
  /// Unfocusing first detaches the IME and the focus listeners
  /// before the route is removed. We then route through the same
  /// discard-changes dialog that the system back gesture uses
  /// (`DirtyFormScope`) so both back paths feel identical — see the
  /// flutter-navigation skill §3 & §7.
  Future<void> _onBack() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    // Routes through `DirtyFormScope` so both the chevron and the
    // system-back gesture share the same dialog AND the same async-
    // gap-safe post-frame pop. Doing `Get.back()` inline here after
    // awaiting the dialog crashes with "Looking up a deactivated
    // widget's ancestor is unsafe" because the chevron's Tooltip /
    // GestureDetector ancestors schedule post-tap cleanup that runs
    // after the await resumes.
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

  void _onSourcePhoneChanged(String value) {
    setState(() {
      _sourcePhoneValid = _validatePhone(value);
    });
  }

  /// `+233201234567` for the typed national number.
  String? _payerE164() {
    try {
      final iso = IsoCode.values.firstWhere((c) => c.name.toUpperCase() == widget.country.isoCode);
      final parsed = PhoneNumber.parse(_sourcePhoneController.text, callerCountry: iso);
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
    final phone = _payerE164();
    void say(String text) => messenger.showSnackBar(
          SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
        );
    if (method == null) return say(l10n.rampErrorProviderNotSupported);
    if (phone == null) return;

    _authInFlight = true;
    try {
      final result = await _submitter.submitOnramp(
        quote: quote,
        requote: _quotes.requote,
        paymentMethod: method,
        payerMsisdn: phone,
        // Step-up auth — a single 6-digit passcode entry against the server step-up endpoint.
        stepUp: () => _authService.authenticate(context),
      );
      if (!mounted) return;
      switch (result) {
        case RampPlaced(:final order):
          Get.off<void>(() => RampStatusScreen(order: order, phone: phone));
        case RampRequoted(:final fresh):
          // The price changed: show it and let the user decide. Never swapped in silently.
          final old = _quotes.quote;
          _quotes.adopt(fresh);
          if (old != null && !old.differsFrom(fresh)) {
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
              content: Text(l10n.rampRequoteBody(
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
      // Guard back against losing typed amount / phone input. The
      // same dialog is invoked from the chevron's `_onBack` so the
      // user sees identical UX regardless of back path. See
      // flutter-navigation skill §3 & §7.
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
                          l10n.loadAmountHeaderTitle,
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
                              l10n.loadAmountTitle,
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
                          if (_exceedsLimit) ...[
                            const SizedBox(height: 12),
                            _LimitError(
                              message: l10n.loadAmountOverLimit(
                                widget.currency.code,
                                _limits.maxPerTransaction.toString(),
                                _limits.tierLabel,
                              ),
                            ),
                          ],
                          if (_isWithinLimit) ...[
                            const SizedBox(height: 16),
                            RampQuoteCard(
                              direction: RampDirection.onramp,
                              quote: _quotes.quote,
                              loading: _quotes.loading,
                              failed: _quotes.failed,
                              onRefresh: _quotes.requote,
                            ),
                          ],
                          const SizedBox(height: 28),

                          // From section ---------------------------------------
                          Text(
                            l10n.loadAmountFromLabel,
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
                            controller: _sourcePhoneController,
                            hint: l10n.loadAmountSourcePhoneHint,
                            onChanged: _onSourcePhoneChanged,
                          ),
                          const SizedBox(height: 28),

                          // Helper text under the form (limit summary).
                          Text(
                            l10n.loadAmountLimitHint(
                              widget.currency.code,
                              _limits.maxPerTransaction.toString(),
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
                    // SwipeToPayButton itself doesn't expose an
                    // `enabled` flag; wrap in an IgnorePointer + opacity
                    // shim so the disabled state reads correctly until
                    // we land a proper API on the widget.
                    child: Opacity(
                      opacity: _canConfirm ? 1.0 : 0.45,
                      child: IgnorePointer(
                        ignoring: !_canConfirm,
                        child: SwipeToPayButton(
                          label: l10n.loadAmountSwipeLabel,
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
// Subcomponents
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
// Outcome — minimal success screen reusing the shared scaffold.
// Kept private to this file because the copy is load-specific and
// the only entry point is _onConfirm above.
// ---------------------------------------------------------------------------
