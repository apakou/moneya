import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_result.dart';
import 'ramp_dtos.dart';

/// Holds the price shown on an amount screen. Debounces keystrokes, drops answers that arrive
/// after a newer request (a slow response for "10" must never overwrite the price for "100"),
/// and clears the price the moment the amount stops being valid.
class RampQuoteController extends ChangeNotifier {
  RampQuoteController({
    required this.fetch,
    this.debounce = const Duration(milliseconds: 400),
  });

  final Future<ApiResult<RampQuote>> Function(String amount) fetch;
  final Duration debounce;

  RampQuote? _quote;
  bool _loading = false;
  bool _failed = false;
  String _amount = '';
  bool _valid = false;
  Timer? _timer;
  int _seq = 0;
  bool _disposed = false;

  RampQuote? get quote => _quote;
  bool get loading => _loading;
  bool get failed => _failed;

  /// Call on every amount change. [valid] = within limits and > 0.
  void setAmount(String amount, {required bool valid}) {
    _timer?.cancel();
    _seq++; // invalidate any in-flight request for the previous amount
    final changed = amount != _amount;
    _amount = amount;
    _valid = valid;
    if (!valid) {
      _clear();
      return;
    }
    if (changed) {
      _quote = null; // never show the old price next to a new amount
      _failed = false;
    }
    _loading = true;
    _notify();
    _timer = Timer(debounce, _run);
  }

  /// Fetch now (also used when the user taps "Refresh price"). Returns the result so the submit
  /// flow can use it directly.
  Future<ApiResult<RampQuote>> requote() async {
    _timer?.cancel();
    return _run();
  }

  Future<ApiResult<RampQuote>> _run() async {
    final my = ++_seq;
    _loading = true;
    _failed = false;
    _notify();
    final result = await fetch(_amount);
    if (my == _seq && !_disposed && _valid) {
      switch (result) {
        case Success(:final value):
          _quote = value;
        case Failure():
          _quote = null;
          _failed = true;
      }
      _loading = false;
      _notify();
    }
    return result;
  }

  /// A re-quote the user has just been shown and accepted/inspected becomes the displayed price.
  void adopt(RampQuote q) {
    _quote = q;
    _failed = false;
    _loading = false;
    _notify();
  }

  void _clear() {
    _quote = null;
    _loading = false;
    _failed = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
