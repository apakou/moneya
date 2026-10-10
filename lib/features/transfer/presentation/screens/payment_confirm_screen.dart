import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/api_result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/domain/supported_country.dart';
import '../../../home/domain/supported_currency.dart';
import '../../data/transaction_auth_outcome.dart';
import '../../data/transaction_auth_service.dart';
import '../../data/transfer_dtos.dart';
import '../../data/transfer_repository.dart';
import '../../domain/funding_provider.dart';
import '../../domain/recipient_lookup.dart';
import '../widgets/swipe_to_pay_button.dart';
import 'payment_failed_screen.dart';
import 'payment_pending_screen.dart';
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
    this.repository,
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

  /// Override for tests. When `null`, a default
  /// [TransferRepository] is constructed inside the state — it
  /// resolves the shared `ApiClient` from GetX lazily on first use.
  final TransferRepository? repository;

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

  final TransactionAuthService _authService = const TransactionAuthService();

  /// Repository for `POST /v1/transfers`. In production we lazily
  /// resolve the shared `ApiClient` from GetX (see [TransferRepository]
  /// default ctor). Tests inject a scripted-adapter-backed repo via
  /// `widget.repository`.
  late final TransferRepository _repository;

  /// Guards against double-firing while the auth sheet / biometric
  /// prompt is on screen.
  bool _authInFlight = false;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = const Uuid().v4();
    _repository = widget.repository ?? TransferRepository();
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
      final outcome = await _authService.authenticate(context);
      if (!mounted) return;
      switch (outcome) {
        case TransactionAuthAuthorised(:final txnToken):
          await _submitTransfer(
            txnToken: txnToken,
            isInvite: isInvite,
            messenger: messenger,
          );
          // _submitTransfer navigates away on every terminal outcome
          // except NetworkError, where it resets the swipe itself.
          // The fall-through `_swipeKey.reset()` below is for the
          // non-Authorised cases only.
          return;
        case TransactionAuthCancelled():
          // User dismissed the passcode sheet — silent reset.
          break;
        case TransactionAuthLockedOut(:final message):
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        case TransactionAuthNetworkError(:final error):
          messenger.showSnackBar(
            SnackBar(
              content: Text(error.title),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      _swipeKey.currentState?.reset();
    } finally {
      _authInFlight = false;
    }
  }

  /// Invoke `POST /v1/transfers` and route to the appropriate terminal
  /// screen.
  ///
  /// Navigation contract:
  /// - `COMPLETED` → [PaymentSuccessScreen] via `Get.off`
  ///   (pushReplacement). Wallet has been debited; no retry semantics.
  /// - `PROCESSING` / `AWAITING_CLAIM` → [PaymentPendingScreen] via
  ///   `Get.off`. The pending screen handles polling and is also
  ///   terminal for this flow.
  /// - `FAILED` (server returned 202 with status=FAILED, or a 4xx
  ///   business error) → [PaymentFailedScreen] via `Get.to` (push,
  ///   NOT pushReplacement) so this confirm screen stays underneath
  ///   and "Try again" pops back here — preserving the original
  ///   [_idempotencyKey]. See `payment_failed_screen.dart` docs.
  /// - [NetworkError] → snackbar + swipe reset. The user can re-swipe;
  ///   the idempotency key is still good so the server will dedupe if
  ///   the prior request actually reached it before the socket died.
  /// - [AuthError] → snackbar (token was invalid despite the fresh
  ///   step-up; usually means the user re-keyed mid-flight or device
  ///   clock skew). The auth interceptor already attempted refresh;
  ///   bubbling up is the right call.
  /// - All other [ApiError] subtypes → [PaymentFailedScreen] with the
  ///   server-supplied title, never raw codes.
  ///
  /// We **never** show raw server error codes in the failure reason.
  /// `ApiError.title` is the localised user-facing copy resolved by
  /// `error_mapping_interceptor.dart`.
  Future<void> _submitTransfer({
    required String txnToken,
    required bool isInvite,
    required ScaffoldMessengerState messenger,
  }) async {
    // E.164 = "+" + dialCode + national digits. Both halves are
    // already digit-only by the time they reach this screen.
    final recipientE164 =
        '+${widget.recipientCountry.dialCode}${widget.recipientPhoneLocal}';

    // Fiat-only contract: the amount travels with its ISO 4217 currency
    // (the sender's balance currency). Any conversion happens server-side;
    // the client never handles a settlement asset. A quote step may be
    // added later (see client-integration-notes Q-FX).
    final request = TransferRequest(
      recipientPhone: recipientE164,
      amount: widget.amount,
      currency: widget.currency.code,
      note: widget.purpose.isEmpty ? null : widget.purpose,
    );

    AppLogger.i('payment_confirm.submit', {
      'idempotency_key': _idempotencyKey,
      'recipient_phone_redacted': _redactPhone(recipientE164),
      'amount': widget.amount,
      'currency': widget.currency.code,
      'is_invite': isInvite,
    });

    final result = await _repository.createTransfer(
      request: request,
      txnToken: txnToken,
      idempotencyKey: _idempotencyKey,
    );

    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        _routeByStatus(value, isInvite: isInvite);
      case Failure(:final error):
        _routeByError(error, messenger: messenger);
    }
  }

  void _routeByStatus(Transfer transfer, {required bool isInvite}) {
    AppLogger.i('payment_confirm.submit.ok', {
      'transfer_id': transfer.id,
      'status': transfer.status.wire,
      'is_invite': isInvite,
    });
    switch (transfer.status) {
      case TransferStatus.completed:
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
      case TransferStatus.processing:
      case TransferStatus.awaitingClaim:
        Get.off<void>(
          () => PaymentPendingScreen(
            amount: widget.amount,
            currency: widget.currency,
            netAmount: _formattedNet,
            recipientName: widget.recipientName,
            transactionId: transfer.id,
          ),
        );
      case TransferStatus.failed:
      case TransferStatus.expiredRefunded:
      case TransferStatus.cancelled:
      case TransferStatus.unknown:
        // 202-with-status=FAILED, or a status we don't recognise.
        // Push (not replace) so "Try again" preserves idempotency.
        Get.to<void>(
          () => PaymentFailedScreen(
            amount: widget.amount,
            currency: widget.currency,
            recipientName: widget.recipientName,
            reason: _failureReasonCopy(transfer.failureReason),
          ),
        );
    }
  }

  void _routeByError(
    ApiError error, {
    required ScaffoldMessengerState messenger,
  }) {
    AppLogger.w('payment_confirm.submit.err', {
      'idempotency_key': _idempotencyKey,
      'error_type': error.runtimeType.toString(),
      'code': error.code,
    });
    switch (error) {
      case NetworkError():
        // Transient — let the user re-swipe; idempotency key is
        // stable so the server will dedupe if needed.
        messenger.showSnackBar(
          SnackBar(
            content: Text(error.title),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _swipeKey.currentState?.reset();
      case AuthError():
        // Auth interceptor already tried refresh. Surfacing means the
        // session is unrecoverable on this device — show the message
        // and reset; a higher-level auth listener will route to login.
        messenger.showSnackBar(
          SnackBar(
            content: Text(error.title),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _swipeKey.currentState?.reset();
      case PaymentError():
      case ValidationError():
      case ConflictError():
      case RateLimitError():
      case ServerError():
      case UnknownError():
        Get.to<void>(
          () => PaymentFailedScreen(
            amount: widget.amount,
            currency: widget.currency,
            recipientName: widget.recipientName,
            reason: error.title,
          ),
        );
    }
  }

  /// Map the structured `TransferFailureReason` enum onto the short
  /// user-facing copy `PaymentFailedScreen` injects between the
  /// amount and the "no funds were taken" reassurance. Returning
  /// `null` lets the failure screen fall back to its generic message.
  String? _failureReasonCopy(TransferFailureReason? reason) {
    if (reason == null) return null;
    switch (reason) {
      case TransferFailureReason.insufficientFunds:
        return 'Insufficient funds';
      case TransferFailureReason.complianceBlock:
        return 'Compliance review required';
      case TransferFailureReason.velocityLimit:
        return 'Daily limit reached';
      case TransferFailureReason.quoteExpired:
        return 'Rate expired';
      case TransferFailureReason.providerRejected:
        return 'Provider declined';
      case TransferFailureReason.serviceUnavailable:
        // Infrastructure failure — never expose its mechanics to the
        // end user.
        return 'Service temporarily unavailable';
      case TransferFailureReason.unknown:
        // Never expose the raw wire value — fall back to generic.
        return null;
    }
  }

  /// Phone redaction for structured logs. Keeps country code + last 2
  /// digits, masks the middle, e.g. `+225********65`. Required by
  /// fintech-security skill — never log full PII.
  static String _redactPhone(String e164) {
    if (e164.length <= 5) return '***';
    final dial = e164.substring(0, 4); // "+225"
    final tail = e164.substring(e164.length - 2);
    return '$dial${'*' * (e164.length - 6)}$tail';
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
