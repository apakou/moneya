import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../presentation/widgets/transaction_passcode_sheet.dart';

/// Outcome of a step-up authentication challenge.
enum TransactionAuthResult {
  /// User authenticated successfully (via biometric or passcode).
  success,

  /// User dismissed / cancelled the prompt without completing.
  cancelled,

  /// User exhausted retry budget. Caller should soft-fail and let the
  /// user re-attempt by re-swiping (no real lockout yet — that lives
  /// server-side per the fintech-security skill).
  failed,
}

/// Step-up authentication for a single transaction (the swipe-to-pay
/// confirmation on `PaymentConfirmScreen`).
///
/// Flow per the fintech-security skill:
/// 1. If the user enrolled biometric login during onboarding AND the
///    device still has biometrics registered, prompt biometric with
///    `sensitiveTransaction: true`.
/// 2. On biometric success → return [TransactionAuthResult.success].
/// 3. On biometric cancel / hardware failure / not-enrolled → fall
///    through to a 6-digit passcode bottom sheet.
/// 4. The passcode sheet enforces a 3-attempt soft cap; after 3 wrong
///    entries it returns [TransactionAuthResult.failed] so the caller
///    can spring the swipe button back to start.
///
/// The biometric-enabled flag is currently hardcoded to `true` — once
/// `flutter_secure_storage` is wired up we'll read the persisted
/// `is_biometric_enabled` value here instead.
class TransactionAuthService {
  TransactionAuthService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  /// Hardcoded for now. Replace with a `flutter_secure_storage` read
  /// once the onboarding biometric screen persists the flag.
  static const bool _biometricEnabledHardcoded = true;

  /// Run the full auth challenge for a transaction. [context] is used
  /// to show the passcode bottom sheet when biometric isn't available
  /// or is rejected.
  Future<TransactionAuthResult> authenticate(BuildContext context) async {
    final biometricOk = await _tryBiometric();
    if (biometricOk) return TransactionAuthResult.success;

    // Either biometrics aren't enrolled / supported, or the user
    // failed / cancelled the biometric prompt. Fall through to the
    // passcode bottom sheet.
    if (!context.mounted) return TransactionAuthResult.cancelled;
    final passcodeOk = await showTransactionPasscodeSheet(context: context);
    if (passcodeOk == null) return TransactionAuthResult.cancelled;
    return passcodeOk
        ? TransactionAuthResult.success
        : TransactionAuthResult.failed;
  }

  Future<bool> _tryBiometric() async {
    if (!_biometricEnabledHardcoded) return false;
    try {
      final supported =
          await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
      if (!supported) return false;
      final available = await _localAuth.getAvailableBiometrics();
      if (available.isEmpty) return false;
      return await _localAuth.authenticate(
        localizedReason: 'Confirm your transfer',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (e, st) {
      debugPrint('Biometric auth threw: $e\n$st');
      return false;
    }
  }
}
