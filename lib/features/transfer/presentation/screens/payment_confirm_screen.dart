import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/domain/supported_country.dart';
import '../../../home/domain/supported_currency.dart';
import '../../data/transaction_auth_service.dart';
import '../../domain/funding_provider.dart';
import '../../domain/recipient_lookup.dart';
import '../widgets/swipe_to_pay_button.dart';
import 'payment_success_screen.dart';
import 'transfer_money_screen.dart' show fundingProviderLabel;

/// Confirm-payment screen reached after the user taps `Confirm` on
/// [TransferMoneyScreen]. Shows the amount, the From → To detail card,
/// fee + recipient receivable, and a slide-to-confirm CTA.
///
/// Two pencil icons (amount card + From source card) `Navigator.pop()`
/// back to the Send Money screen so the user can tweak any field and
/// re-open this screen with fresh values. We don't try to round-trip
/// edits — Send Money is the single source of truth.
///
/// Stateful for two reasons:
/// 1. We mint a UUIDv4 **idempotency key** in [initState] and reuse it
///    for every retry of this transfer (per fintech-security skill).
///    Re-swiping after an auth failure must NOT mint a new key —
///    otherwise the backend can't dedupe a double-submit.
/// 2. We hold a `GlobalKey<SwipeToPayButtonState>` so we can spring
///    the thumb back to the start when step-up auth fails or the
///    user cancels the passcode sheet.
///
/// On successful step-up auth we [Navigator.pushReplacement] to
/// [PaymentSuccessScreen]. The transfer call itself is still stubbed —
/// no real backend, no balance debit. The idempotency key is generated
/// but not yet sent anywhere.
class PaymentConfirmScreen extends StatefulWidget {
  const PaymentConfirmScreen({
    required this.amount,
    required this.currency,
    required this.feeAmount,
    required this.netAmount,
    required this.provider,
    required this.senderCountry,
    required this.senderPhoneLocal,
    required this.recipientCountry,
    required this.recipientPhoneLocal,
    required this.recipientName,
    required this.lookupResult,
    required this.purpose,
    super.key,
  });

  /// Gross amount the sender entered, e.g. `2000`.
  final String amount;
  final SupportedCurrency currency;

  /// Stub fee — passed through from the send screen.
  final double feeAmount;
  final double netAmount;

  final FundingProvider provider;

  final SupportedCountry senderCountry;
  final String senderPhoneLocal;

  final SupportedCountry recipientCountry;
  final String recipientPhoneLocal;
  final String recipientName;

  /// `RecipientFound` (direct) vs `RecipientNotFound` (SMS invite +
  /// escrow). Drives the success-screen copy.
  final RecipientLookupResult? lookupResult;

  /// Optional free-text reason — currently unused on this screen, kept
  /// so we can show it later if design adds a "Note" row.
  final String purpose;

  @override
  State<PaymentConfirmScreen> createState() => _PaymentConfirmScreenState();
}

class _PaymentConfirmScreenState extends State<PaymentConfirmScreen> {
  /// Idempotency key for this transfer attempt. Stable across retries
  /// so the backend can dedupe if the swipe fires twice.
  late final String _idempotencyKey;

  /// Lets us reset the swipe thumb after auth failure / cancel.
  final GlobalKey<SwipeToPayButtonState> _swipeKey =
      GlobalKey<SwipeToPayButtonState>();

  final TransactionAuthService _authService = TransactionAuthService();

  /// Guards against double-firing while the auth sheet / biometric
  /// prompt is on screen.
  bool _authInFlight = false;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = const Uuid().v4();
    AppLogger.d('payment_confirm.init', {'idempotency_key': _idempotencyKey});
  }

  String get _formattedFee => _stripDot(widget.feeAmount);
  String get _formattedNet => _stripDot(widget.netAmount);

  static String _stripDot(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  /// Pretty-print the sender's national-significant number with a
  /// space every two digits (the mock shows `+225 98 76 62 65`).
  String _prettyIntl(SupportedCountry country, String local) {
    final spaced = _spaceEveryTwo(local);
    return '+${country.dialCode} $spaced';
  }

  String _prettyLocal(String local) => _spaceEveryTwo(local);

  static String _spaceEveryTwo(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 2 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  Future<void> _onSwipeCompleted() async {
    if (_authInFlight) return;
    _authInFlight = true;
    final messenger = ScaffoldMessenger.of(context);
    final isInvite = widget.lookupResult is RecipientNotFound;
    try {
      final result = await _authService.authenticate(context);
      if (!mounted) return;
      switch (result) {
        case TransactionAuthResult.success:
          // Stub: no backend call yet. The idempotency key is logged
          // in initState and would be the `Idempotency-Key` HTTP
          // header on `POST /transfers`.
          Get.off<void>(
            () => PaymentSuccessScreen(
              amount: widget.amount,
              currency: widget.currency,
              netAmount: _formattedNet,
              recipientName: widget.recipientName,
              recipientCountry: widget.recipientCountry,
              recipientPhoneLocal: widget.recipientPhoneLocal,
              isInvite: isInvite,
            ),
          );
          return;
        case TransactionAuthResult.cancelled:
          // User dismissed the passcode sheet — silent reset.
          break;
        case TransactionAuthResult.failed:
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).confirmPaymentAuthFailedSnack,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      _swipeKey.currentState?.reset();
    } finally {
      _authInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pop helper used by both pencil affordances. `Get.back()` is the
    // GetX wrapper around `Navigator.pop`; safe here because the
    // pencils use `GestureDetector` (no Material splash), so the
    // "deactivated widget's ancestor" race doesn't apply — see
    // `popAfterFrame` for the splash-callsite variant.
    void popToTransfer() {
      if (Get.key.currentState?.canPop() ?? false) {
        Get.back<void>();
      }
    }
    final l10n = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: DecoratedBox(
          // Brand gradient at the top fades into black behind the fee
          // rows — matches the mock where the lower portion of the
          // screen is solid black.
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Column(
              children: [
                _Header(onBack: Get.back),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 24),
                            child: Text(
                              l10n.confirmPaymentTitle,
                              style: AppTextStyles.sectionTitle,
                            ),
                          ),
                        ),
                        Text(
                          l10n.confirmPaymentDetailsHeading,
                          style: AppTextStyles.subsectionTitle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.confirmPaymentDetailsSubtitle,
                          style: AppTextStyles.bodyMuted,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          l10n.confirmPaymentAmountLabel,
                          style: AppTextStyles.bodyMuted,
                        ),
                        const SizedBox(height: 8),
                        _AmountCard(
                          currencyCode: widget.currency.code,
                          amount: widget.amount,
                          onEdit: popToTransfer,
                        ),
                        const SizedBox(height: 16),
                        _FromToCard(
                          provider: widget.provider,
                          senderLine: _prettyIntl(
                            widget.senderCountry,
                            widget.senderPhoneLocal,
                          ),
                          recipientName: widget.recipientName,
                          recipientLine:
                              _prettyLocal(widget.recipientPhoneLocal),
                          onEdit: popToTransfer,
                        ),
                        const SizedBox(height: 28),
                        _FeeRow(
                          label: l10n.transferFeeLabel,
                          value: '${widget.currency.code} $_formattedFee',
                        ),
                        const SizedBox(height: 12),
                        _FeeRow(
                          label: l10n.transferRecipientReceivesLabel,
                          value: '${widget.currency.code} $_formattedNet',
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: SwipeToPayButton(
                    key: _swipeKey,
                    label: l10n.confirmPaymentSwipeLabel,
                    onCompleted: _onSwipeCompleted,
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

// ---------------------------------------------------------------------------
// Subcomponents
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
      child: Row(
        children: [
          BackChevronButton(onTap: onBack, tooltip: l10n.commonBack),
          Text(
            l10n.confirmPaymentHeaderTitle,
            style: AppTextStyles.screenTitle,
          ),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.currencyCode,
    required this.amount,
    required this.onEdit,
  });

  final String currencyCode;
  final String amount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: HeroTextScaleClamp(
              child: Text(
                '$currencyCode $amount',
                style: AppTextStyles.heroAmountConfirm,
              ),
            ),
          ),
          _EditPencil(onTap: onEdit),
        ],
      ),
    );
  }
}

class _FromToCard extends StatelessWidget {
  const _FromToCard({
    required this.provider,
    required this.senderLine,
    required this.recipientName,
    required this.recipientLine,
    required this.onEdit,
  });

  final FundingProvider provider;
  final String senderLine;
  final String recipientName;
  final String recipientLine;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final providerName = fundingProviderLabel(provider, l10n);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ProviderGlyph(provider: provider, displayName: providerName),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: l10n.confirmPaymentFromYourPrefix,
                            style: AppTextStyles.label,
                          ),
                          TextSpan(
                            text: providerName,
                            style: AppTextStyles.label
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      senderLine,
                      style: AppTextStyles.captionMuted,
                    ),
                  ],
                ),
              ),
              _EditPencil(onTap: onEdit),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 18),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _RecipientAvatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: l10n.confirmPaymentToRecipientPrefix,
                            style: AppTextStyles.label,
                          ),
                          TextSpan(
                            text: recipientName.isEmpty
                                ? l10n.confirmPaymentRecipientFallback
                                : recipientName,
                            style: AppTextStyles.label
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipientLine,
                      style: AppTextStyles.captionMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderGlyph extends StatelessWidget {
  const _ProviderGlyph({required this.provider, required this.displayName});

  final FundingProvider provider;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final icon = provider.iconAsset;
    return SizedBox(
      width: 44,
      height: 44,
      child: icon == null
          ? _ProviderInitialBadge(label: displayName)
          : Image.asset(
              icon,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  _ProviderInitialBadge(label: displayName),
            ),
    );
  }
}

class _ProviderInitialBadge extends StatelessWidget {
  const _ProviderInitialBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final initial = label.isEmpty ? '?' : label.characters.first.toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.actionPurple.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RecipientAvatar extends StatelessWidget {
  const _RecipientAvatar();

  @override
  Widget build(BuildContext context) {
    // Until we have a real avatar service, render a generic person
    // glyph in a soft circle. The mock uses a flat illustration; this
    // is a clean stand-in that matches our icon vocabulary.
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

class _EditPencil extends StatelessWidget {
  const _EditPencil({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Plain GestureDetector instead of InkResponse: the route pops
    // synchronously on tap and the InkResponse ripple animation would
    // try to look up `Material.of(context)` after the element was
    // deactivated — that triggered the
    // "Looking up a deactivated widget's ancestor is unsafe" error.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: const Icon(
          Icons.edit_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$label : ',
          style: AppTextStyles.bodyMuted,
        ),
        Text(
          value,
          style: AppTextStyles.numeric(AppTextStyles.pillLabel),
        ),
      ],
    );
  }
}
