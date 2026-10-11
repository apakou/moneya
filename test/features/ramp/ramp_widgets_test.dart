import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/features/ramp/data/ramp_dtos.dart';
import 'package:moneya/features/ramp/data/ramp_order_tracker.dart';
import 'package:moneya/features/ramp/data/ramp_repository.dart';
import 'package:moneya/features/ramp/presentation/ramp_error_text.dart';
import 'package:moneya/features/ramp/presentation/ramp_quote_card.dart';
import 'package:moneya/features/ramp/presentation/ramp_status_screen.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';

Widget app(Widget home, {Locale locale = const Locale('en')}) => GetMaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: home),
    );

RampQuote quote({DateTime? expires, String kind = 'ONRAMP', String toCur = 'GHS'}) => RampQuote(
      id: 'q',
      kind: kind,
      fromCurrency: 'GHS',
      fromAmount: '100',
      toCurrency: toCur,
      toAmount: '98.5',
      rate: '1',
      fee: '1.5',
      expiresAt: expires ?? DateTime.utc(2026, 10, 10, 12, 0, 42),
    );

RampOrder order(String status, {RampDirection d = RampDirection.onramp, String? reason}) => RampOrder(
      id: 'o',
      direction: d,
      status: status,
      quote: quote(kind: d == RampDirection.onramp ? 'ONRAMP' : 'OFFRAMP'),
      createdAt: DateTime.utc(2026, 10, 10, 12),
      failureReason: reason,
    );

class _Repo extends RampRepository {
  _Repo(this.script) : super();
  final List<ApiResult<RampOrder>> script;
  @override
  Future<ApiResult<RampOrder>> getOrder(RampDirection direction, String id) async => script.removeAt(0);
}

void main() {
  group('RampQuoteCard', () {
    final now = DateTime.utc(2026, 10, 10, 12);

    testWidgets('shows what you receive, the fee and the countdown (display code GHC for the cedi)', (tester) async {
      await tester.pumpWidget(app(RampQuoteCard(direction: RampDirection.onramp, quote: quote(), loading: false, failed: false, onRefresh: () {}, now: () => now)));
      expect(find.text("You'll receive"), findsOneWidget);
      expect(find.text('98.50 GHC'), findsOneWidget);
      expect(find.text('1.50 GHC'), findsOneWidget);
      expect(find.text('Price valid for 42s'), findsOneWidget);
    });

    testWidgets('cash-out labels the amount as what the recipient gets', (tester) async {
      await tester.pumpWidget(app(RampQuoteCard(direction: RampDirection.offramp, quote: quote(kind: 'OFFRAMP'), loading: false, failed: false, onRefresh: () {}, now: () => now)));
      expect(find.text('Recipient gets'), findsOneWidget);
    });

    testWidgets('an expired price says so and offers a refresh (never refreshed silently)', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(app(RampQuoteCard(
        direction: RampDirection.onramp,
        quote: quote(expires: now.subtract(const Duration(seconds: 1))),
        loading: false,
        failed: false,
        onRefresh: () => refreshed++,
        now: () => now,
      )));
      expect(find.text('Price expired'), findsOneWidget);
      await tester.tap(find.text('Refresh price'));
      expect(refreshed, 1);
    });

    testWidgets('a failed fetch shows the error with a retry, and no stale numbers', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(app(RampQuoteCard(direction: RampDirection.onramp, quote: null, loading: false, failed: true, onRefresh: () => refreshed++)));
      expect(find.textContaining("couldn't get a price"), findsOneWidget);
      await tester.tap(find.text('Refresh price'));
      expect(refreshed, 1);
    });

    testWidgets('French copy', (tester) async {
      await tester.pumpWidget(app(RampQuoteCard(direction: RampDirection.onramp, quote: quote(), loading: false, failed: false, onRefresh: () {}, now: () => now), locale: const Locale('fr')));
      expect(find.text('Vous recevrez'), findsOneWidget);
      expect(find.text('Frais'), findsOneWidget);
    });

    testWidgets('no settlement-asset vocabulary is ever rendered', (tester) async {
      await tester.pumpWidget(app(RampQuoteCard(direction: RampDirection.onramp, quote: quote(), loading: false, failed: false, onRefresh: () {}, now: () => now)));
      final all = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' ').toLowerCase();
      expect(all, isNot(matches(RegExp(r'usdc|stablecoin|stellar|crypto|blockchain'))));
    });
  });

  group('RampStatusScreen', () {
    Future<void> pump(WidgetTester tester, RampOrder o, List<ApiResult<RampOrder>> script, {Duration timeout = const Duration(minutes: 5)}) async {
      await tester.pumpWidget(app(RampStatusScreen(
        order: o,
        phone: '+233201234567',
        tracker: RampOrderTracker(repository: _Repo(script), timeout: timeout, delay: (d) async {}),
      )));
      await tester.pump();
    }

    testWidgets('top-up: waits for the phone approval, then shows the credit', (tester) async {
      await pump(tester, order('AWAITING_PAYMENT'), [Success(order('COMPLETED'))]);
      await tester.pumpAndSettle();
      expect(find.text('Top-up complete'), findsOneWidget);
      expect(find.textContaining('98.50 GHC was added'), findsOneWidget);
    });

    testWidgets('top-up pending copy tells the user to approve on their phone', (tester) async {
      await pump(tester, order('AWAITING_PAYMENT'), [Success(order('AWAITING_PAYMENT'))], timeout: Duration.zero);
      await tester.pump();
      expect(find.text('Approve on your phone'), findsOneWidget);
      expect(find.textContaining('approve the payment of 100 GHC'), findsOneWidget);
    });

    testWidgets('top-up declined → "You were not charged"', (tester) async {
      await pump(tester, order('AWAITING_PAYMENT'), [Success(order('FAILED', reason: 'PAYER_DECLINED'))]);
      await tester.pumpAndSettle();
      expect(find.text('Payment not completed'), findsOneWidget);
      expect(find.textContaining('not charged'), findsOneWidget);
    });

    testWidgets('top-up timeout has its own copy', (tester) async {
      await pump(tester, order('AWAITING_PAYMENT'), [Success(order('FAILED', reason: 'PROVIDER_TIMEOUT'))]);
      await tester.pumpAndSettle();
      expect(find.textContaining("didn't respond in time"), findsOneWidget);
    });

    testWidgets('cash-out refunded → the money is back in the balance', (tester) async {
      await pump(tester, order('PROCESSING', d: RampDirection.offramp), [Success(order('REFUNDED', d: RampDirection.offramp, reason: 'PROVIDER_REJECTED'))]);
      await tester.pumpAndSettle();
      expect(find.text('Cash-out failed'), findsOneWidget);
      expect(find.textContaining('back in your MoneyA balance'), findsOneWidget);
    });

    testWidgets('cash-out settled', (tester) async {
      await pump(tester, order('PROCESSING', d: RampDirection.offramp), [Success(order('SETTLED', d: RampDirection.offramp))]);
      await tester.pumpAndSettle();
      expect(find.text('Money sent'), findsOneWidget);
      expect(find.textContaining('+233201234567'), findsOneWidget);
    });

    testWidgets('slow order: no failure claim, just "we will notify you"', (tester) async {
      await pump(tester, order('AWAITING_PAYMENT'), [Success(order('AWAITING_PAYMENT'))], timeout: Duration.zero);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ramp.slowNote')), findsOneWidget);
      expect(find.text('Payment not completed'), findsNothing);
    });

    testWidgets('an already-terminal order renders immediately without polling', (tester) async {
      await pump(tester, order('COMPLETED'), const []);
      expect(find.text('Top-up complete'), findsOneWidget);
    });
  });

  group('rampErrorText', () {
    late AppLocalizations l10n;
    setUp(() => l10n = lookupAppLocalizations(const Locale('en')));
    test('maps server codes to copy', () {
      expect(rampErrorText(l10n, const PaymentError(code: 'INSUFFICIENT_FUNDS', title: 'x', statusCode: 402)), contains("don't have enough"));
      expect(rampErrorText(l10n, const NetworkError()), contains("won't be charged twice"));
      expect(rampErrorText(l10n, const ServerError(code: 'PROVIDER_UNAVAILABLE', title: 'x', statusCode: 503)), contains('temporarily unavailable'));
      expect(rampErrorText(l10n, const UnknownError(code: 'WHATEVER', title: 'x')), contains('Something went wrong'));
    });
  });
}
