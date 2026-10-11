import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:moneya/core/network/api_client.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/session/step_up_controller.dart';
import 'package:moneya/core/storage/secure_storage.dart';
import 'package:moneya/features/auth/domain/supported_country.dart';
import 'package:moneya/features/home/domain/supported_currency.dart';
import 'package:moneya/features/load_money/domain/momo_provider.dart';
import 'package:moneya/features/load_money/presentation/screens/load_amount_screen.dart';
import 'package:moneya/features/ramp/data/ramp_dtos.dart';
import 'package:moneya/features/ramp/data/ramp_repository.dart';
import 'package:moneya/features/ramp/presentation/ramp_status_screen.dart';
import 'package:moneya/features/transfer/presentation/widgets/swipe_to_pay_button.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';

RampQuote _quote({String id = 'q1', String to = '98.5', String fee = '1.5', DateTime? expires}) => RampQuote(
      id: id,
      kind: 'ONRAMP',
      fromCurrency: 'GHS',
      fromAmount: '100',
      toCurrency: 'GHS',
      toAmount: to,
      rate: '1',
      fee: fee,
      expiresAt: expires ?? DateTime.now().add(const Duration(minutes: 10)),
    );

RampOrder _order() => RampOrder(
      id: 'o1',
      direction: RampDirection.onramp,
      status: 'AWAITING_PAYMENT',
      quote: _quote(),
      ussdInstructions: 'Approve the payment on your phone',
      createdAt: DateTime.now(),
    );

class _Repo extends RampRepository {
  _Repo() : super();
  final quoteCalls = <(String, String)>[];
  final orders = <Map<String, String>>[];
  List<ApiResult<RampQuote>> quotes = [];
  ApiResult<RampOrder> orderResult = Success(_order());

  @override
  Future<ApiResult<RampQuote>> quoteOnramp({required String currency, required String amount}) async {
    quoteCalls.add((currency, amount));
    return quotes.isEmpty ? Success(_quote()) : quotes.removeAt(0);
  }

  @override
  Future<ApiResult<RampOrder>> createOnramp({required String quoteId, required String paymentMethod, required String payerMsisdn, required String txnToken, required String idempotencyKey}) async {
    orders.add({'quote': quoteId, 'method': paymentMethod, 'phone': payerMsisdn, 'token': txnToken, 'key': idempotencyKey});
    return orderResult;
  }

  @override
  Future<ApiResult<RampOrder>> getOrder(RampDirection direction, String id) async => Success(_order());
}

class _NoRefresh implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) async => throw StateError('unused');
}

/// Real controller (so GetX lifecycle works); only the network call is replaced.
class _StepUp extends StepUpController {
  _StepUp(super.api, this.result);
  ApiResult<String> result;
  final passcodes = <String>[];

  @override
  Future<ApiResult<String>> fresh({required String passcode}) async {
    passcodes.add(passcode);
    return result;
  }
}

void main() {
  late _Repo repo;
  late _StepUp stepUp;

  setUp(() async {
    Get.reset();
    repo = _Repo();
    final session = SessionController(store: SessionStore(InMemorySecureStorage()), refresher: _NoRefresh());
    await session.bootstrap();
    final api = ApiClient.build(session: session, appVersion: '1.0.0', localeProvider: () => 'en', baseUrlOverride: 'https://api.test');
    stepUp = _StepUp(api, const Success('txn-1'));
    Get.put<StepUpController>(stepUp);
  });
  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, {MomoProvider provider = MomoProvider.mtnMomo}) async {
    tester.view.physicalSize = const Size(420 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: LoadAmountScreen(
        currency: SupportedCurrency.ghs,
        country: SupportedCountry.ghana,
        provider: provider,
        rampRepository: repo,
      ),
    ));
    await tester.pump();
  }

  Future<void> enterAmount(WidgetTester tester, String digits) async {
    await tester.tap(find.text('GHC'));
    await tester.pumpAndSettle();
    for (final d in digits.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  Future<void> enterPhoneAndWaitForPrice(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '201234567');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // debounce
    await tester.pump();
  }

  Future<void> swipe(WidgetTester tester) async {
    // Several small moves, like a thumb (one giant jump is swallowed by the gesture arena).
    final start = tester.getCenter(find.byType(SwipeToPayButton)) - const Offset(150, 0);
    final g = await tester.startGesture(start);
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  Future<void> typePasscode(WidgetTester tester, String code) async {
    // The screen's own phone field comes first; the passcode sheet adds six more.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(7), reason: 'passcode sheet is open');
    for (var i = 0; i < code.length; i++) {
      await tester.enterText(fields.at(1 + i), code[i]);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('no price until the amount is entered; then the price card appears with the fee', (tester) async {
    await pump(tester);
    expect(repo.quoteCalls, isEmpty);
    expect(find.text("You'll receive"), findsNothing);
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    expect(repo.quoteCalls, [('GHS', '100')], reason: 'ISO code on the wire, not the app\'s GHC');
    expect(find.text("You'll receive"), findsOneWidget);
    expect(find.text('98.50 GHC'), findsOneWidget);
    expect(find.text('1.50 GHC'), findsOneWidget);
  });

  testWidgets('happy path: swipe → passcode → ONE order with E.164 phone, token and idempotency key → status screen', (tester) async {
    await pump(tester);
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    await swipe(tester);
    await typePasscode(tester, '482916');

    expect(stepUp.passcodes, ['482916']);
    expect(repo.orders, hasLength(1));
    final o = repo.orders.single;
    expect(o['quote'], 'q1');
    expect(o['method'], 'MTN_MOMO');
    expect(o['phone'], '+233201234567');
    expect(o['token'], 'txn-1');
    expect(o['key'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(find.byType(RampStatusScreen), findsOneWidget);
    expect(find.text('Approve on your phone'), findsOneWidget);
  });

  testWidgets('wrong passcode never reaches the order endpoint', (tester) async {
    stepUp.result = const Failure(AuthError(code: 'PASSCODE_INVALID', title: 'Incorrect passcode', statusCode: 401));
    await pump(tester);
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    await swipe(tester);
    await typePasscode(tester, '111222');
    expect(repo.orders, isEmpty);
    expect(find.byType(RampStatusScreen), findsNothing);
  });

  testWidgets('insufficient funds from the server → clear message, stays on the form', (tester) async {
    repo.orderResult = const Failure(PaymentError(code: 'INSUFFICIENT_FUNDS', title: 'x', statusCode: 402));
    await pump(tester);
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    await swipe(tester);
    await typePasscode(tester, '482916');
    await tester.pump();
    expect(find.textContaining("don't have enough"), findsOneWidget);
    expect(find.byType(RampStatusScreen), findsNothing);
  });

  testWidgets('QUOTE_EXPIRED with different numbers → dialog shows the new price; continuing asks for the passcode again and orders on the NEW quote', (tester) async {
    repo.orderResult = const Failure(ConflictError(code: 'QUOTE_EXPIRED', title: 'Quote expired'));
    await pump(tester);
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    repo.quotes = [Success(_quote(id: 'q2', to: '98', fee: '2'))]; // the re-quote has worse numbers
    await swipe(tester);
    await typePasscode(tester, '482916');
    await tester.pumpAndSettle();

    expect(find.text('The price changed'), findsOneWidget);
    expect(find.textContaining('98 GHC'), findsWidgets);
    expect(repo.orders, hasLength(1), reason: 'never auto-retried');

    repo.orderResult = Success(_order());
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await typePasscode(tester, '482916');
    expect(repo.orders, hasLength(2));
    expect(repo.orders.last['quote'], 'q2');
    expect(find.byType(RampStatusScreen), findsOneWidget);
  });

  testWidgets('a provider that is not in the API contract is refused before anything is sent', (tester) async {
    await pump(tester, provider: MomoProvider.tMoney);
    await tester.pumpAndSettle();
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    await swipe(tester);
    expect(find.textContaining("isn't available yet"), findsOneWidget);
    expect(stepUp.passcodes, isEmpty);
    expect(repo.orders, isEmpty);
  });
}
