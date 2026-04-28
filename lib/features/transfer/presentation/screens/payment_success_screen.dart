import 'package:flutter/material.dart';

import '../../../home/domain/supported_currency.dart';
import '../widgets/transfer_outcome_scaffold.dart';
import 'transfer_money_screen.dart';

/// Terminal screen of the Send Money flow when the transfer succeeded.
/// Reached via `Navigator.pushReplacement` from
/// [PaymentConfirmScreen] when the swipe-to-pay control completes,
/// step-up auth succeeds, and the backend returns 200 OK on
/// `POST /transfers`.
///
/// Two copy variants:
/// * **Direct** ([isInvite] = false) — recipient is on MoneyA. Body:
///   `<name> will receive <code> <amount> within a few seconds…`.
/// * **SMS invite + escrow** ([isInvite] = true) — recipient isn't
///   registered yet. Body explains that funds are held in escrow
///   until the recipient signs up and verifies their phone.
///
/// CTAs:
/// * **Send more money** (primary, white pill) — pops back to
///   `HomeShell` then re-pushes [TransferMoneyScreen] so the user can
///   fire another transfer with one tap.
/// * **Go back home** (secondary, dark pill) — just pops to the first
///   route.
class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({
    required this.amount,
    required this.currency,
    required this.netAmount,
    required this.recipientName,
    required this.isInvite,
    super.key,
  });

  /// Gross amount the sender entered (display only).
  final String amount;
  final SupportedCurrency currency;

  /// Net amount the recipient receives (after fees). This is what we
  /// quote in the body copy because it's the number the recipient
  /// actually sees land in their wallet.
  final String netAmount;
  final String recipientName;
  final bool isInvite;

  String get _displayName =>
      recipientName.isEmpty ? 'Recipient' : recipientName;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    final amountSpan = '${currency.code} $netAmount';
    final title = isInvite
        ? 'Invite Sent Successfully'
        : 'Transfer Done Successfully';
    return TransferOutcomeScaffold(
      glyphColor: const Color(0xFF2BC46A),
      glyphIcon: Icons.check_rounded,
      title: title,
      body: TransferOutcomeBody(
        spans: isInvite
            ? [
                TransferOutcomeBody.muted(
                  '$_displayName will get an SMS to claim ',
                ),
                TransferOutcomeBody.bold(amountSpan),
                TransferOutcomeBody.muted(
                  '. Funds are held in escrow until they sign '
                  'up and verify their phone.',
                ),
              ]
            : [
                TransferOutcomeBody.muted('$_displayName will receive '),
                TransferOutcomeBody.bold(amountSpan),
                TransferOutcomeBody.muted(
                  ' within a few seconds, but it can take up to '
                  '2 hours in some special cases.',
                ),
              ],
      ),
      primaryLabel: 'Send more money',
      onPrimary: () {
        // Pop down to HomeShell, then re-open Send Money with the
        // same currency so the user lands on a fresh transfer screen
        // with one tap.
        navigator.popUntil((r) => r.isFirst);
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => TransferMoneyScreen(currency: currency),
          ),
        );
      },
      secondaryLabel: 'Go back home',
      onSecondary: () {
        navigator.popUntil((r) => r.isFirst);
      },
    );
  }
}
