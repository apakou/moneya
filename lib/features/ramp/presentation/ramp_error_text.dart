import '../../../core/network/api_error.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Localized copy for a failed top-up / cash-out request, keyed on the server's stable `code`.
String rampErrorText(AppLocalizations l10n, ApiError error) {
  if (error is NetworkError) return l10n.rampErrorNetwork;
  switch (error.code) {
    case 'INSUFFICIENT_FUNDS':
      return l10n.rampErrorInsufficientFunds;
    case 'PROVIDER_UNAVAILABLE':
      return l10n.rampErrorUnavailable;
    case 'RATE_LIMITED':
    case 'PASSCODE_LOCKED':
      final mins = ((error.retryAfter?.inSeconds ?? 60) / 60).ceil();
      return l10n.authErrorTooManyRequests(mins < 1 ? 1 : mins);
  }
  if (error is ServerError) return l10n.rampErrorUnavailable;
  return l10n.rampErrorGeneric;
}
