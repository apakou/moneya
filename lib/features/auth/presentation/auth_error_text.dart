import '../../../core/network/api_error.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Localized, user-facing copy for an error from the auth endpoints. Branches on
/// the server's stable `code` (backend `problem.code`), never on English titles.
/// `OTP_INVALID` is deliberately NOT handled here: the verify screen has its own
/// "incorrect code" sheet.
String authErrorText(AppLocalizations l10n, ApiError error) {
  int minutes() {
    final secs = error.retryAfter?.inSeconds ?? 0;
    return secs <= 0 ? 1 : (secs / 60).ceil();
  }

  if (error is NetworkError) return l10n.authErrorNetwork;
  switch (error.code) {
    case 'RATE_LIMITED':
      return l10n.authErrorTooManyRequests(minutes());
    case 'OTP_LOCKED':
    case 'PASSCODE_LOCKED':
      return l10n.authErrorOtpLocked(minutes());
    case 'SMS_UNAVAILABLE':
      return l10n.authErrorSmsUnavailable;
    case 'PASSCODE_TOO_WEAK':
      return l10n.passcodeErrorWeak;
    case 'VALIDATION_ERROR':
      return l10n.authErrorInvalidPhone;
  }
  return l10n.authErrorGeneric;
}
