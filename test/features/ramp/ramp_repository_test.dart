import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/network/api_client.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';
import 'package:moneya/features/home/domain/supported_currency.dart';
import 'package:moneya/features/load_money/domain/momo_provider.dart';
import 'package:moneya/features/ramp/data/ramp_dtos.dart';
import 'package:moneya/features/ramp/data/ramp_repository.dart';
import 'package:moneya/features/ramp/domain/ramp_mapping.dart';

const _quote = {
  'id': '11111111-1111-4111-8111-111111111111',
  'kind': 'ONRAMP',
  'from_currency': 'GHS',
  'from_amount': '100',
  'to_currency': 'GHS',
  'to_amount': '98.5',
  'rate': '1',
  'fee': '1.5',
  'expires_at': '2026-10-10T12:01:00.000Z',
};

void main() {
  late _Adapter adapter;
  late RampRepository repo;

  setUp(() async {
    final session = SessionController(store: SessionStore(InMemorySecureStorage()), refresher: _NoRefresh());
    await session.bootstrap();
    await session.setSession(AuthSession(
      accessToken: 'bearer-1',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      userId: 'u',
      phone: '+233201234567',
      countryIso2: 'GH',
      kycTier: KycTier.tier0,
    ));
    final api = ApiClient.build(session: session, appVersion: '1.0.0', localeProvider: () => 'en', baseUrlOverride: 'https://api.test');
    adapter = _Adapter();
    api.dio.httpClientAdapter = adapter;
    repo = RampRepository.test(api);
  });

  test('quoteOnramp sends ISO currency + string amount and parses the fiat-only quote', () async {
    adapter.reply(200, _quote);
    final r = await repo.quoteOnramp(currency: 'GHS', amount: '100');
    final q = (r as Success<RampQuote>).value;
    expect((q.toAmount, q.fee, q.rate), ('98.5', '1.5', '1'));
    expect(jsonDecode(adapter.last.body), {'fiat_currency': 'GHS', 'fiat_amount': '100'});
    expect(adapter.last.path, '/v1/onramp/quote');
  });

  test('createOnramp carries BOTH Idempotency-Key and X-Txn-Token, and parses the pending order', () async {
    adapter.reply(202, {
      'id': '22222222-2222-4222-8222-222222222222',
      'status': 'AWAITING_PAYMENT',
      'quote': _quote,
      'ussd_instructions': 'Approve the payment on your phone',
      'provider_reference': 'ref-1',
      'created_at': '2026-10-10T12:00:00.000Z',
    });
    final r = await repo.createOnramp(
      quoteId: _quote['id']!,
      paymentMethod: 'MTN_MOMO',
      payerMsisdn: '+233201234567',
      txnToken: 'tok-1',
      idempotencyKey: '33333333-3333-4333-8333-333333333333',
    );
    final o = (r as Success<RampOrder>).value;
    expect(o.status, 'AWAITING_PAYMENT');
    expect(o.ussdInstructions, contains('Approve'));
    expect(o.isTerminal, isFalse);
    expect(adapter.last.headers['Idempotency-Key'], '33333333-3333-4333-8333-333333333333');
    expect(adapter.last.headers['X-Txn-Token'], 'tok-1');
    expect(adapter.last.headers['Authorization'], 'Bearer bearer-1');
    expect(jsonDecode(adapter.last.body), {'quote_id': _quote['id'], 'payment_method': 'MTN_MOMO', 'payer_msisdn': '+233201234567'});
  });

  test('createOfframp: 402 INSUFFICIENT_FUNDS → PaymentError with the server code', () async {
    adapter.reply(402, {'code': 'INSUFFICIENT_FUNDS', 'title': 'Insufficient balance', 'status': 402});
    final r = await repo.createOfframp(quoteId: 'q', payoutMethod: 'MTN_MOMO', payeeMsisdn: '+233201234567', payeeName: 'Ama', txnToken: 't', idempotencyKey: 'k');
    final err = (r as Failure<RampOrder>).error;
    expect(err, isA<PaymentError>());
    expect(err.code, 'INSUFFICIENT_FUNDS');
    expect(jsonDecode(adapter.last.body)['payee_name'], 'Ama');
  });

  test('409 QUOTE_EXPIRED → ConflictError', () async {
    adapter.reply(409, {'code': 'QUOTE_EXPIRED', 'title': 'Quote expired, please request a new one', 'status': 409});
    final r = await repo.createOnramp(quoteId: 'q', paymentMethod: 'MTN_MOMO', payerMsisdn: '+233201234567', txnToken: 't', idempotencyKey: 'k');
    expect((r as Failure<RampOrder>).error, isA<ConflictError>());
  });

  test('getOrder hits the right path per direction and settles an offramp', () async {
    adapter.reply(200, {'id': 'o', 'status': 'SETTLED', 'quote': {..._quote, 'kind': 'OFFRAMP'}, 'created_at': '2026-10-10T12:00:00.000Z', 'settled_at': '2026-10-10T12:01:00.000Z'});
    final r = await repo.getOrder(RampDirection.offramp, 'o');
    expect(adapter.last.path, '/v1/offramp/orders/o');
    expect((r as Success<RampOrder>).value.isSuccess, isTrue);
    expect(r.value.finishedAt, isNotNull);
  });

  group('RampMapping', () {
    test('the cedi is GHS on the wire even though the app shows GHC', () {
      expect(SupportedCurrency.ghs.code, 'GHC');
      expect(RampMapping.wireCurrency(SupportedCurrency.ghs), 'GHS');
      expect(RampMapping.wireCurrency(SupportedCurrency.xof), 'XOF');
    });
    test('providers map to the contract enum; those not in the contract map to null', () {
      expect(RampMapping.paymentMethod(MomoProvider.mtnMomo), 'MTN_MOMO');
      expect(RampMapping.paymentMethod(MomoProvider.wave), 'WAVE');
      expect(RampMapping.paymentMethod(MomoProvider.moovAfrica), 'MOOV_MONEY');
      expect(RampMapping.paymentMethod(MomoProvider.tMoney), isNull);
      expect(RampMapping.paymentMethod(MomoProvider.opay), isNull);
    });
  });
}

class _NoRefresh implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) async => throw StateError('unused');
}

class _Req {
  _Req(this.path, this.headers, this.body);
  final String path;
  final Map<String, dynamic> headers;
  final String body;
}

class _Adapter implements HttpClientAdapter {
  final requests = <_Req>[];
  final _script = <(int, Object?)>[];
  _Req get last => requests.last;
  void reply(int status, Object? body) => _script.add((status, body));

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final c in requestStream) {
        bytes.addAll(c);
      }
    }
    requests.add(_Req(options.path, Map<String, dynamic>.from(options.headers), utf8.decode(bytes)));
    final (status, body) = _script.removeAt(0);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [status >= 400 ? 'application/problem+json' : 'application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
