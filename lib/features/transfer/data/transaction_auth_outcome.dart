import '../../../core/network/api_error.dart';

/// Result of running step-up authentication for a money-moving operation.
///
/// Returned by [TransactionAuthService.authenticate] and the underlying
/// [showTransactionPasscodeSheet]. Callers exhaustively switch on it and
/// either proceed with the minted `X-Txn-Token` or surface the error.
///
/// The outcome model intentionally mirrors the server contract (per
/// `client-integration-notes.md` §5 / §7): the only "happy" path is
/// [Authorised]; everything else is some flavour of failure that the
/// caller decides how to surface. The sheet itself handles in-place
/// retry for soft wrong-passcode errors — by the time you receive a
/// non-[Authorised] outcome the sheet has already closed.
sealed class TransactionAuthOutcome {
  const TransactionAuthOutcome();
}

/// User entered the correct passcode and the server minted a fresh
/// step-up token. Pass [txnToken] to the downstream money endpoint via
/// `Options(extra: {AuthInterceptor.txnTokenKey: txnToken})`.
class TransactionAuthAuthorised extends TransactionAuthOutcome {
  const TransactionAuthAuthorised(this.txnToken);

  final String txnToken;
}

/// User dismissed the sheet (drag-down / tap outside / back). Caller
/// should silently reset its swipe button and stay on the screen.
class TransactionAuthCancelled extends TransactionAuthOutcome {
  const TransactionAuthCancelled();
}

/// Server kept returning 401 / wrong-passcode beyond the client's
/// retry cap, OR returned a 423 lockout. The sheet has closed; the
/// caller should surface [message] via a snackbar and reset its
/// swipe button.
class TransactionAuthLockedOut extends TransactionAuthOutcome {
  const TransactionAuthLockedOut(this.message);

  final String message;
}

/// Transport / non-auth server failure during step-up (network drop,
/// 5xx, malformed response). Caller should surface [error] and let
/// the user retry by swiping again.
class TransactionAuthNetworkError extends TransactionAuthOutcome {
  const TransactionAuthNetworkError(this.error);

  final ApiError error;
}
