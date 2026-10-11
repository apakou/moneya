import 'package:uuid/uuid.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/api_result.dart';
import '../../transfer/data/transaction_auth_outcome.dart';
import 'ramp_dtos.dart';
import 'ramp_repository.dart';

/// What happened when the user confirmed a top-up / cash-out.
sealed class RampSubmitResult {
  const RampSubmitResult();
}

/// The server accepted the order (it may still be waiting for the user's approval or the provider).
class RampPlaced extends RampSubmitResult {
  const RampPlaced(this.order);
  final RampOrder order;
}

/// The quote the user saw is no longer valid and the NEW one has different numbers.
/// Nothing was sent. The UI must show [fresh] and let the user confirm it again.
class RampRequoted extends RampSubmitResult {
  const RampRequoted(this.fresh);
  final RampQuote fresh;
}

class RampCancelled extends RampSubmitResult {
  const RampCancelled();
}

/// Step-up refused (locked out): show [message]; the user must wait.
class RampBlocked extends RampSubmitResult {
  const RampBlocked(this.message);
  final String message;
}

/// A real failure ([ApiError.code] e.g. `INSUFFICIENT_FUNDS`, a `NetworkError`, ...).
/// Retrying with the same quote reuses the same Idempotency-Key.
class RampFailed extends RampSubmitResult {
  const RampFailed(this.error);
  final ApiError error;
}

/// The rules around placing a money order, kept out of the widgets so they are tested:
///  * an expired quote is re-fetched; if the numbers changed it is surfaced, NEVER swapped in silently;
///  * `QUOTE_EXPIRED` from the server is handled the same way and the order is never auto-retried;
///  * one Idempotency-Key per quote, reused on retry (lost response → replay, not a second order);
///  * every submit goes through step-up (the passcode sheet), even a retry.
class RampSubmitter {
  RampSubmitter({RampRepository? repository, DateTime Function()? now, Uuid? uuid})
      : _repo = repository ?? RampRepository(),
        _now = now ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final RampRepository _repo;
  final DateTime Function() _now;
  final Uuid _uuid;

  final Map<String, String> _keys = {};
  String _keyFor(String quoteId) => _keys.putIfAbsent(quoteId, _uuid.v4);

  Future<RampSubmitResult> submitOnramp({
    required RampQuote quote,
    required Future<ApiResult<RampQuote>> Function() requote,
    required String paymentMethod,
    required String payerMsisdn,
    required Future<TransactionAuthOutcome> Function() stepUp,
  }) {
    return _submit(
      quote: quote,
      requote: requote,
      stepUp: stepUp,
      create: (q, token) => _repo.createOnramp(
        quoteId: q.id,
        paymentMethod: paymentMethod,
        payerMsisdn: payerMsisdn,
        txnToken: token,
        idempotencyKey: _keyFor(q.id),
      ),
    );
  }

  Future<RampSubmitResult> submitOfframp({
    required RampQuote quote,
    required Future<ApiResult<RampQuote>> Function() requote,
    required String payoutMethod,
    required String payeeMsisdn,
    String? payeeName,
    required Future<TransactionAuthOutcome> Function() stepUp,
  }) {
    return _submit(
      quote: quote,
      requote: requote,
      stepUp: stepUp,
      create: (q, token) => _repo.createOfframp(
        quoteId: q.id,
        payoutMethod: payoutMethod,
        payeeMsisdn: payeeMsisdn,
        payeeName: payeeName,
        txnToken: token,
        idempotencyKey: _keyFor(q.id),
      ),
    );
  }

  Future<RampSubmitResult> _submit({
    required RampQuote quote,
    required Future<ApiResult<RampQuote>> Function() requote,
    required Future<TransactionAuthOutcome> Function() stepUp,
    required Future<ApiResult<RampOrder>> Function(RampQuote quote, String txnToken) create,
  }) async {
    var current = quote;

    if (current.isExpiredAt(_now())) {
      final fresh = await requote();
      switch (fresh) {
        case Failure(:final error):
          return RampFailed(error);
        case Success(:final value):
          if (value.differsFrom(current)) return RampRequoted(value);
          current = value; // same numbers under a new id: nothing for the user to re-confirm
      }
    }

    final auth = await stepUp();
    final String token;
    switch (auth) {
      case TransactionAuthAuthorised(:final txnToken):
        token = txnToken;
      case TransactionAuthCancelled():
        return const RampCancelled();
      case TransactionAuthLockedOut(:final message):
        return RampBlocked(message);
      case TransactionAuthNetworkError(:final error):
        return RampFailed(error);
    }

    final result = await create(current, token);
    switch (result) {
      case Success(:final value):
        return RampPlaced(value);
      case Failure(:final error):
        if (error.code == 'QUOTE_EXPIRED') {
          // The server's clock disagrees with ours. Fetch the new quote and let the user decide.
          final fresh = await requote();
          return switch (fresh) {
            Success(:final value) => RampRequoted(value),
            Failure(error: final e) => RampFailed(e),
          };
        }
        return RampFailed(error);
    }
  }
}
