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
import 'package:moneya/features/withdraw/presentation/screens/withdraw_amount_screen.dart';
import 'package:moneya/features/ramp/data/ramp_dtos.dart';
import 'package:moneya/features/ramp/data/ramp_repository.dart';
import 'package:moneya/features/ramp/presentation/ramp_status_screen.dart';
import 'package:moneya/features/transfer/presentation/widgets/swipe_to_pay_button.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';

RampQuote _quote({String id = 'q1', String to = '98.5', String fee = '1.5', String amount = '100'}) => RampQuote(
      id: id,
      kind: 'OFFRAMP',
      fromCurrency: 'GHS',
      fromAmount: amount,
      toCurrency: 'GHS',
      toAmount: to,
      rate: '1',
      fee: fee,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );

RampOrder _order({String status = 'PROCESSING'}) => RampOrder(
      id: 'o1',
      direction: RampDirection.offramp,
      status: status,
      quote: _quote(),
      createdAt: DateTime.now(),
    );

class _Repo extends RampRepository {
  _Repo() : super();
  final quoteCalls = <(String, String, String)>[];
  final orders = <Map<String, String?>>[];
  List<ApiResult<RampQuote>> quotes = [];
  ApiResult<RampOrder> orderResult = Success(_order());

  @override
  Future<ApiResult<RampQuote>> quoteOfframp({required String amount, required String currency, required String payoutCurrency}) async {
    quoteCalls.add((amount, currency, payoutCurrency));
    return quotes.isEmpty ? Success(_quote(amount: amount)) : quotes.removeAt(0);
  }

  @override
  Future<ApiResult<RampOrder>> createOfframp({required String quoteId, required String payoutMethod, required String payeeMsisdn, String? payeeName, required String txnToken, required String idempotencyKey}) async {
    orders.add({'quote': quoteId, 'method': payoutMethod, 'phone': payeeMsisdn, 'token': txnToken, 'key': idempotencyKey});
    return orderResult;
  }

  @override
  Future<ApiResult<RampOrder>> getOrder(RampDirection direction, String id) async => Success(_order());
}

class _NoRefresh implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) async => throw StateError('unused');
}

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

  Future<void> pump(WidgetTester tester, {num balance = 500}) async {
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
      home: WithdrawAmountScreen(
        currency: SupportedCurrency.ghs,
        balanceMinor: balance,
        country: SupportedCountry.ghana,
        provider: MomoProvider.mtnMomo,
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
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<void> swipe(WidgetTester tester) async {
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
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(7), reason: 'passcode sheet is open');
    for (var i = 0; i < code.length; i++) {
      await tester.enterText(fields.at(1 + i), code[i]);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('price card shows what the recipient gets; quote uses ISO currency for both sides', (tester) async {
    await pump(tester);
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    expect(repo.quoteCalls, [('100', 'GHS', 'GHS')]);
    expect(find.text('Recipient gets'), findsOneWidget);
    expect(find.text('98.50 GHC'), findsOneWidget);
  });

  testWidgets('happy path: ONE cash-out order with the payee in E.164, token and idempotency key → status screen', (tester) async {
    await pump(tester);
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    await swipe(tester);
    await typePasscode(tester, '482916');
    expect(repo.orders, hasLength(1));
    final o = repo.orders.single;
    expect((o['method'], o['phone'], o['token']), ('MTN_MOMO', '+233201234567', 'txn-1'));
    expect(o['key'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(find.byType(RampStatusScreen), findsOneWidget);
    expect(find.text('Sending your money'), findsOneWidget);
  });

  testWidgets('an amount above the balance is stopped locally: no price is requested', (tester) async {
    await pump(tester, balance: 50);
    await enterAmount(tester, '100');
    await tester.enterText(find.byType(TextField), '201234567');
    await tester.pump(const Duration(milliseconds: 600));
    expect(repo.quoteCalls, isEmpty);
    expect(find.text("You'll receive"), findsNothing);
    expect(find.text('Recipient gets'), findsNothing);
  });

  testWidgets('server 402 (balance changed elsewhere) → clear message, no status screen', (tester) async {
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

  testWidgets('changed price on a cash-out is shown with the payout wording and needs a second passcode', (tester) async {
    repo.orderResult = const Failure(ConflictError(code: 'QUOTE_EXPIRED', title: 'Quote expired'));
    await pump(tester);
    await enterAmount(tester, '100');
    await enterPhoneAndWaitForPrice(tester);
    repo.quotes = [Success(_quote(id: 'q2', to: '98', fee: '2'))];
    await swipe(tester);
    await typePasscode(tester, '482916');
    await tester.pumpAndSettle();
    expect(find.text('The price changed'), findsOneWidget);
    expect(find.textContaining('recipient will now get 98 GHC'), findsOneWidget);
    expect(repo.orders, hasLength(1));
    repo.orderResult = Success(_order());
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await typePasscode(tester, '482916');
    expect(repo.orders.last['quote'], 'q2');
    expect(find.byType(RampStatusScreen), findsOneWidget);
  });
}
