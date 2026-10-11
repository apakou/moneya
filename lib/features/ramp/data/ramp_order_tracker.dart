import '../../../core/network/api_error.dart';
import '../../../core/network/api_result.dart';
import 'ramp_dtos.dart';
import 'ramp_repository.dart';

/// Polls an order until it is terminal (the webhook updates the server; the app asks).
///
/// Emits every observed state (so the UI can show progress), then completes. Transient
/// network errors and 5xx are tolerated; anything else (404, auth) ends the stream with
/// that error. After [timeout] the stream just completes: the order is still alive on the
/// server and shows up in history — the UI says "we'll notify you", it does not call it failed.
class RampOrderTracker {
  RampOrderTracker({
    RampRepository? repository,
    this.interval = const Duration(seconds: 3),
    this.slowInterval = const Duration(seconds: 6),
    this.slowAfter = const Duration(minutes: 1),
    this.timeout = const Duration(minutes: 5),
    Future<void> Function(Duration)? delay,
  })  : _repo = repository ?? RampRepository(),
        _delay = delay ?? Future<void>.delayed;

  final RampRepository _repo;
  final Duration interval;
  final Duration slowInterval;
  final Duration slowAfter;
  final Duration timeout;
  final Future<void> Function(Duration) _delay;

  Stream<RampOrder> watch(RampDirection direction, String orderId) async* {
    var elapsed = Duration.zero;
    String? lastStatus;
    while (true) {
      final result = await _repo.getOrder(direction, orderId);
      switch (result) {
        case Success(:final value):
          if (value.status != lastStatus) {
            lastStatus = value.status;
            yield value;
          }
          if (value.isTerminal) return;
        case Failure(:final error):
          if (!_transient(error)) throw error;
      }
      final step = elapsed >= slowAfter ? slowInterval : interval;
      if (elapsed + step > timeout) return;
      await _delay(step);
      elapsed += step;
    }
  }

  static bool _transient(ApiError e) => e is NetworkError || e is ServerError;
}
