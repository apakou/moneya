import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../home/domain/supported_currency.dart';
import '../widgets/transfer_outcome_scaffold.dart';
import 'transfer_money_screen.dart';

/// Terminal screen of the Send Money flow when the backend accepted
/// the transfer but it hasn't settled yet.
///
/// Reached via `Navigator.pushReplacement` from
/// [PaymentConfirmScreen] when `POST /transfers` returns
/// `202 Accepted` with `status=pending` — typically because the
/// downstream MoMo provider hasn't acknowledged the debit, the
/// transaction is on AML hold, or the recipient corridor is in a
/// scheduled-batch settlement window.
///
/// Pending transfers are NOT failed: the user's wallet has been
/// debited (or escrowed), and the recipient will be credited once the
/// provider confirms. We tell the user it can take a few minutes and
/// give them two ways out:
/// * **Send more money** (primary) — same as the success screen.
///   Pending transfers don't lock the wallet, so a follow-up transfer
///   is fine.
/// * **View transaction** (secondary) — eventually deep-links to a
///   transaction-detail screen where they can poll status. We don't
///   have that screen yet, so for now this just pops to home and
///   logs a TODO.
class PaymentPendingScreen extends StatelessWidget {
  const PaymentPendingScreen({
    required this.amount,
    required this.currency,
    required this.netAmount,
    required this.recipientName,
    this.transactionId,
    this.reason,
    super.key,
  });

  /// Gross amount the sender entered (display only).
  final String amount;
  final SupportedCurrency currency;

  /// Net amount the recipient will eventually receive. Quoted in body
  /// copy because that's the number the recipient sees land.
  final String netAmount;
  final String recipientName;

  /// Server-issued transaction id. Once we have the transaction-detail
  /// screen it'll be the navigation argument; for now we just log it.
  final String? transactionId;

  /// Optional human-readable backend reason (e.g., "Awaiting provider
  /// confirmation"). When `null` we fall back to a generic message.
  final String? reason;

  String get _displayName =>
      recipientName.isEmpty ? 'Recipient' : recipientName;

  @override
  Widget build(BuildContext context) {
    final amountSpan = '${currency.code} $netAmount';
    final reasonSuffix = reason == null || reason!.isEmpty
        ? ' We\'ll notify you once it settles, usually within '
              'a few minutes.'
        : ' $reason';
    return PopScope(
      // Terminal screen: predictive back must not return to the
      // (already-replaced) confirm form. Primary/secondary CTAs are
      // the only sanctioned exits. See flutter-navigation skill §4.
      canPop: false,
      child: TransferOutcomeScaffold(
      // Amber/orange — neutral "in progress" tint that doesn't read
      // as success or failure.
      glyphColor: const Color(0xFFF5A524),
      // Filled clock face matches the existing rounded icon vocabulary
      // used elsewhere in the app.
      glyphIcon: Icons.access_time_rounded,
      title: 'Transfer Pending',
      body: TransferOutcomeBody(
        spans: [
          TransferOutcomeBody.muted("Your transfer of "),
          TransferOutcomeBody.bold(amountSpan),
          TransferOutcomeBody.muted(' to '),
          TransferOutcomeBody.bold(_displayName),
          TransferOutcomeBody.muted(' is being processed.$reasonSuffix'),
        ],
      ),
      primaryLabel: 'Send more money',
      onPrimary: () {
        Get.until((r) => r.isFirst);
        Get.to<void>(() => TransferMoneyScreen(currency: currency));
      },
      secondaryLabel: 'View transaction',
      onSecondary: () {
        // TODO(transactions): replace with a push to the transaction
        // detail screen once that lands. For now log the id we'd open
        // and pop to home so the user isn't stranded.
        AppLogger.i('payment.pending.view_tx.tap', {
          'tx_id': transactionId,
        });
        Get.until((r) => r.isFirst);
      },
      ),
    );
  }
}
