import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/features/ramp/data/ramp_dtos.dart';
import 'package:moneya/features/ramp/data/ramp_order_tracker.dart';
import 'package:moneya/features/ramp/data/ramp_repository.dart';
import 'package:moneya/features/ramp/data/ramp_submitter.dart';
import 'package:moneya/features/transfer/data/transaction_auth_outcome.dart';

RampQuote quote({String id = 'q1', String to = '98.5', String fee = '1.5', DateTime? expires}) => RampQuote(
      id: id,
      kind: 'ONRAMP',
      fromCurrency: 'GHS',
      fromAmount: '100',
      toCurrency: 'GHS',
      toAmount: to,
      rate: '1',
      fee: fee,
      expiresAt: expires ?? DateTime.utc(2026, 10, 10, 12, 1),
    );

RampOrder order(String status, {RampDirection d = RampDirection.onramp}) => RampOrder(
      id: 'o1',
      direction: d,
      status: status,
      quote: quote(),
      createdAt: DateTime.utc(2026, 10, 10, 12),
    );

class _Repo extends RampRepository {
  _Repo() : super();
  final created = <Map<String, String>>[];
  ApiResult<RampOrder> createResult = Success(order('AWAITING_PAYMENT'));
  final polls = <ApiResult<RampOrder>>[];
  int pollCount = 0;

  @override
  Future<ApiResult<RampOrder>> createOnramp({required String quoteId, required String paymentMethod, required String payerMsisdn, required String txnToken, required String idempotencyKey}) async {
    created.add({'quote': quoteId, 'token': txnToken, 'key': idempotencyKey, 'method': paymentMethod});
    return createResult;
  }

  @override
  Future<ApiResult<RampOrder>> getOrder(RampDirection direction, String id) async {
    pollCount++;
    return polls.removeAt(0);
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 10, 12);
  late _Repo repo;
  late RampSubmitter submitter;
  var stepUps = 0;
  Future<TransactionAuthOutcome> ok() async {
    stepUps++;
    return TransactionAuthAuthorised('tok-$stepUps');
  }

  setUp(() {
    repo = _Repo();
    stepUps = 0;
    submitter = RampSubmitter(repository: repo, now: () => now);
  });

  Future<RampSubmitResult> submit(RampQuote q, {Future<ApiResult<RampQuote>> Function()? requote, Future<TransactionAuthOutcome> Function()? auth}) =>
      submitter.submitOnramp(
        quote: q,
        requote: requote ?? () async => Success(quote(id: 'q2')),
        paymentMethod: 'MTN_MOMO',
        payerMsisdn: '+233201234567',
        stepUp: auth ?? ok,
      );

  group('RampSubmitter', () {
    test('valid quote: step-up then one order with token and key', () async {
      final r = await submit(quote());
      expect(r, isA<RampPlaced>());
      expect(repo.created.single, {'quote': 'q1', 'token': 'tok-1', 'key': repo.created.single['key'], 'method': 'MTN_MOMO'});
      expect(repo.created.single['key'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    });

    test('retry of the SAME quote reuses the idempotency key (lost response → replay, not a 2nd order)', () async {
      repo.createResult = const Failure(NetworkError());
      final first = await submit(quote());
      expect(first, isA<RampFailed>());
      repo.createResult = Success(order('AWAITING_PAYMENT'));
      await submit(quote());
      expect(repo.created.map((c) => c['key']).toSet(), hasLength(1));
      expect(repo.created.map((c) => c['token']), ['tok-1', 'tok-2'], reason: 'every attempt re-authenticates');
    });

    test('a different quote gets a different key', () async {
      await submit(quote(id: 'a'));
      await submit(quote(id: 'b'));
      expect(repo.created.map((c) => c['key']).toSet(), hasLength(2));
    });

    test('expired quote with CHANGED numbers → Requoted, nothing sent, no step-up', () async {
      final r = await submit(quote(expires: now.subtract(const Duration(seconds: 1))), requote: () async => Success(quote(id: 'q2', to: '98', fee: '2')));
      expect(r, isA<RampRequoted>());
      expect((r as RampRequoted).fresh.toAmount, '98');
      expect(repo.created, isEmpty);
      expect(stepUps, 0);
    });

    test('expired quote with SAME numbers → proceeds with the new quote id', () async {
      final r = await submit(quote(expires: now.subtract(const Duration(seconds: 1))));
      expect(r, isA<RampPlaced>());
      expect(repo.created.single['quote'], 'q2');
    });

    test('server says QUOTE_EXPIRED → Requoted, order not retried automatically', () async {
      repo.createResult = const Failure(ConflictError(code: 'QUOTE_EXPIRED', title: 'Quote expired'));
      final r = await submit(quote());
      expect(r, isA<RampRequoted>());
      expect(repo.created, hasLength(1));
    });

    test('cancelled / locked out / insufficient funds map to distinct results', () async {
      expect(await submit(quote(), auth: () async => const TransactionAuthCancelled()), isA<RampCancelled>());
      final blocked = await submit(quote(), auth: () async => const TransactionAuthLockedOut('Try again in 15 min'));
      expect((blocked as RampBlocked).message, 'Try again in 15 min');
      repo.createResult = const Failure(PaymentError(code: 'INSUFFICIENT_FUNDS', title: 'Insufficient balance', statusCode: 402));
      final failed = await submit(quote());
      expect((failed as RampFailed).error.code, 'INSUFFICIENT_FUNDS');
    });

    test('requote failure surfaces as Failed, not a crash', () async {
      final r = await submit(quote(expires: now.subtract(const Duration(seconds: 1))), requote: () async => const Failure(NetworkError()));
      expect(r, isA<RampFailed>());
    });
  });

  group('RampOrderTracker', () {
    Future<List<String>> collect(RampOrderTracker t) async => (await t.watch(RampDirection.onramp, 'o1').toList()).map((o) => o.status).toList();
    final waits = <Duration>[];
    RampOrderTracker tracker({Duration timeout = const Duration(minutes: 5)}) =>
        RampOrderTracker(repository: repo, timeout: timeout, delay: (d) async => waits.add(d));
    setUp(waits.clear);

    test('emits each new state and stops at a terminal one', () async {
      repo.polls.addAll([
        Success(order('AWAITING_PAYMENT')),
        Success(order('AWAITING_PAYMENT')), // unchanged → not re-emitted
        Success(order('COLLECTED')),
        Success(order('COMPLETED')),
      ]);
      expect(await collect(tracker()), ['AWAITING_PAYMENT', 'COLLECTED', 'COMPLETED']);
      expect(repo.pollCount, 4);
    });

    test('tolerates a network blip and a 5xx, then continues', () async {
      repo.polls.addAll([
        const Failure(NetworkError()),
        const Failure(ServerError()),
        Success(order('COMPLETED')),
      ]);
      expect(await collect(tracker()), ['COMPLETED']);
    });

    test('a 404 ends the stream with the error', () async {
      repo.polls.add(const Failure(UnknownError(code: 'NOT_FOUND', title: 'Order not found', statusCode: 404)));
      await expectLater(tracker().watch(RampDirection.onramp, 'o1').toList(), throwsA(isA<ApiError>()));
    });

    test('gives up quietly at the timeout (the order stays alive on the server)', () async {
      for (var i = 0; i < 50; i++) {
        repo.polls.add(Success(order('AWAITING_PAYMENT')));
      }
      expect(await collect(tracker(timeout: const Duration(seconds: 30))), ['AWAITING_PAYMENT']);
      expect(waits.length, lessThanOrEqualTo(10));
    });

    test('slows down after the first minute', () async {
      for (var i = 0; i < 80; i++) {
        repo.polls.add(Success(order('AWAITING_PAYMENT')));
      }
      await collect(tracker(timeout: const Duration(minutes: 3)));
      expect(waits.first, const Duration(seconds: 3));
      expect(waits.last, const Duration(seconds: 6));
    });
  });

  group('DTOs', () {
    test('order status helpers', () {
      expect(order('COMPLETED').isSuccess, isTrue);
      expect(order('SETTLED', d: RampDirection.offramp).isSuccess, isTrue);
      expect(order('AWAITING_PAYMENT').isTerminal, isFalse);
      expect(order('REFUNDED', d: RampDirection.offramp).wasRefunded, isTrue);
      expect(order('EXPIRED').isTerminal, isTrue);
    });
    test('quote.differsFrom only reacts to user-visible numbers', () {
      expect(quote().differsFrom(quote(id: 'other')), isFalse);
      expect(quote().differsFrom(quote(fee: '2')), isTrue);
    });
    test('malformed order throws instead of building a half object', () {
      expect(() => RampOrder.fromJson({'id': 'x'}, RampDirection.onramp), throwsFormatException);
    });
  });
}
