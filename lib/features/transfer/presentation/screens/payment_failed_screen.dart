import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../home/domain/supported_currency.dart';
import '../widgets/transfer_outcome_scaffold.dart';

/// Terminal screen of the Send Money flow when the backend rejected
/// the transfer.
///
/// Reached when `POST /transfers` returns 4xx/5xx — insufficient
/// funds, KYC limit exceeded, provider declined, recipient corridor
/// suspended, etc. The user's wallet has NOT been debited.
///
/// **Navigation contract.** This screen must be reached via
/// `Navigator.push` (not `pushReplacement`) so [PaymentConfirmScreen]
/// stays on the stack underneath. The primary CTA `Try again` simply
/// pops back to the confirm screen — which still holds the original
/// UUIDv4 idempotency key minted in its `initState`. Reusing that key
/// is the whole point of generating it once: it lets the backend
/// safely dedupe a retried submission. Minting a fresh key on every
/// attempt would defeat that.
///
/// CTAs:
/// * **Try again** (primary) — `Navigator.pop()` back to the confirm
///   screen so the user can re-swipe with the same idempotency key.
/// * **Go back home** (secondary) — pop to first route.
class PaymentFailedScreen extends StatelessWidget {
  const PaymentFailedScreen({
    required this.amount,
    required this.currency,
    required this.recipientName,
    this.reason,
    super.key,
  });

  final String amount;
  final SupportedCurrency currency;
  final String recipientName;

  /// Optional human-readable backend error (e.g., "Insufficient
  /// funds", "Daily limit exceeded"). When `null` we fall back to a
  /// generic "something went wrong" message — never expose raw error
  /// codes / stack traces to the user.
  final String? reason;

  String get _displayName =>
      recipientName.isEmpty ? 'the recipient' : recipientName;

  @override
  Widget build(BuildContext context) {
    final amountSpan = '${currency.code} $amount';
    final hasReason = reason != null && reason!.isNotEmpty;
    return PopScope(
      // Terminal screen: predictive back must not return to the
      // (already-replaced) confirm form. Even "Try again" is an
      // explicit user choice via the primary CTA, not a back gesture.
      // See flutter-navigation skill §4.
      canPop: false,
      child: TransferOutcomeScaffold(
      // Brand-friendly red — readable on the brand gradient without
      // clashing with the purple.
      glyphColor: const Color(0xFFE5484D),
      glyphIcon: Icons.close_rounded,
      title: 'Transfer Failed',
      body: TransferOutcomeBody(
        spans: [
          TransferOutcomeBody.muted('We couldn\'t send '),
          TransferOutcomeBody.bold(amountSpan),
          TransferOutcomeBody.muted(' to $_displayName. '),
          if (hasReason) ...[
            TransferOutcomeBody.bold(reason!),
            TransferOutcomeBody.muted(
              '. No funds were taken from your wallet — please try '
              'again.',
            ),
          ] else
            TransferOutcomeBody.muted(
              'No funds were taken from your wallet — please try '
              'again in a moment.',
            ),
        ],
      ),
      primaryLabel: 'Try again',
      onPrimary: () {
        // Pop back to PaymentConfirmScreen so the original
        // idempotency key is preserved on retry. See class docs.
        if (Get.key.currentState?.canPop() ?? false) Get.back<void>();
      },
      secondaryLabel: 'Go back home',
      onSecondary: () {
        Get.until((r) => r.isFirst);
      },
      ),
    );
  }
}
