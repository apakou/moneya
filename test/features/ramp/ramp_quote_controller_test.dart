import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/features/ramp/data/ramp_dtos.dart';
import 'package:moneya/features/ramp/data/ramp_quote_controller.dart';

RampQuote q(String id, String from) => RampQuote(
      id: id,
      kind: 'ONRAMP',
      fromCurrency: 'GHS',
      fromAmount: from,
      toCurrency: 'GHS',
      toAmount: from,
      rate: '1',
      fee: '1',
      expiresAt: DateTime.utc(2030),
    );

void main() {
  testWidgets('debounces keystrokes: one request for the last amount', (tester) async {
    {
      final asked = <String>[];
      final c = RampQuoteController(fetch: (a) async {
        asked.add(a);
        return Success(q('q$a', a));
      });
      c.setAmount('1', valid: true);
      await tester.pump(const Duration(milliseconds: 100));
      c.setAmount('10', valid: true);
      await tester.pump(const Duration(milliseconds: 100));
      c.setAmount('100', valid: true);
      expect(c.loading, isTrue);
      expect(c.quote, isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(asked, ['100']);
      expect(c.quote!.id, 'q100');
      expect(c.loading, isFalse);
      c.dispose();
    }
  });

  testWidgets('a slow answer for an old amount never overwrites the newer price', (tester) async {
    {
      final pending = <String, Completer<ApiResult<RampQuote>>>{};
      final c = RampQuoteController(
        debounce: Duration.zero,
        fetch: (a) => (pending[a] = Completer<ApiResult<RampQuote>>()).future,
      );
      c.setAmount('10', valid: true);
      await tester.pump(const Duration(milliseconds: 1));
      c.setAmount('100', valid: true);
      await tester.pump(const Duration(milliseconds: 1));
      pending['100']!.complete(Success(q('new', '100')));
      await tester.pump();
      pending['10']!.complete(Success(q('stale', '10')));
      await tester.pump();
      expect(c.quote!.id, 'new');
      c.dispose();
    }
  });

  testWidgets('an invalid amount clears the price and cancels the request', (tester) async {
    {
      var calls = 0;
      final c = RampQuoteController(fetch: (a) async {
        calls++;
        return Success(q('x', a));
      });
      c.setAmount('5', valid: true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(c.quote, isNotNull);
      c.setAmount('0', valid: false);
      expect(c.quote, isNull);
      expect(c.loading, isFalse);
      c.setAmount('7', valid: true);
      c.setAmount('0', valid: false);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(calls, 1, reason: 'the cancelled debounce never fired');
      c.dispose();
    }
  });

  test('failure shows failed (no stale price); requote() recovers and returns the result', () async {
    var fail = true;
    final c = RampQuoteController(
      debounce: Duration.zero,
      fetch: (a) async => fail ? const Failure(NetworkError()) : Success(q('ok', a)),
    );
    c.setAmount('5', valid: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.failed, isTrue);
    expect(c.quote, isNull);
    fail = false;
    final r = await c.requote();
    expect(r, isA<Success<RampQuote>>());
    expect(c.failed, isFalse);
    expect(c.quote!.id, 'ok');
    c.dispose();
  });

  test('changing the amount drops the old price immediately (no old price beside a new amount)', () async {
    final c = RampQuoteController(debounce: Duration.zero, fetch: (a) async => Success(q('q$a', a)));
    c.setAmount('5', valid: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.quote!.id, 'q5');
    c.setAmount('6', valid: true);
    expect(c.quote, isNull);
    c.dispose();
  });
}
