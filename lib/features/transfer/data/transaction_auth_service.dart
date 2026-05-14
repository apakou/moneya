import 'package:flutter/material.dart';

import '../presentation/widgets/transaction_passcode_sheet.dart';
import 'transaction_auth_outcome.dart';

/// Step-up authentication for a single money-moving operation (the
/// swipe-to-pay / swipe-to-confirm gesture on PaymentConfirmScreen,
/// WithdrawAmountScreen, LoadAmountScreen).
///
/// **W2 contract — passcode only.** The previous biometric short-circuit
/// has been removed: the server treats step-up as an explicit passcode
/// challenge that produces a single-use `X-Txn-Token`, and biometric
/// alone cannot mint that token. When the backend lands a
/// `/auth/biometric-attest` endpoint we'll route through it again and
/// fall back to passcode; for now every step-up goes through the
/// passcode sheet, which calls [StepUpController.fresh] and emits one
/// of the [TransactionAuthOutcome] variants.
///
/// Biometric is still used for **app unlock** (passcode lock screen)
/// via [AppPrefs.biometricEnabled] — that path is unchanged.
///
/// Usage:
/// ```dart
/// final outcome = await _authService.authenticate(context);
/// switch (outcome) {
///   case TransactionAuthAuthorised(:final txnToken):
///     await repo.create(req, txnToken: txnToken);
///   case TransactionAuthCancelled():
///     // user dismissed — silent reset
///   case TransactionAuthLockedOut(:final message):
///     messenger.showSnackBar(SnackBar(content: Text(message)));
///   case TransactionAuthNetworkError(:final error):
///     messenger.showSnackBar(SnackBar(content: Text(error.title)));
/// }
/// ```
class TransactionAuthService {
  const TransactionAuthService();

  /// Run the step-up challenge. [context] is used to show the
  /// passcode bottom sheet. Returns a terminal [TransactionAuthOutcome]
  /// — the sheet handles in-place retry for wrong-passcode itself.
  Future<TransactionAuthOutcome> authenticate(BuildContext context) async {
    if (!context.mounted) return const TransactionAuthCancelled();
    return showTransactionPasscodeSheet(context: context);
  }
}
