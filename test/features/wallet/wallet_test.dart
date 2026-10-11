import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:moneya/core/locale/locale_controller.dart';
import 'package:moneya/core/network/api_client.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';
import 'package:moneya/features/home/domain/transaction.dart';
import 'package:moneya/features/home/domain/user_profile.dart';
import 'package:moneya/features/home/presentation/screens/home_screen.dart';
import 'package:moneya/features/ramp/data/ramp_dtos.dart';
import 'package:moneya/features/ramp/data/ramp_order_tracker.dart';
import 'package:moneya/features/ramp/data/ramp_repository.dart';
import 'package:moneya/features/ramp/presentation/ramp_status_screen.dart';
import 'package:moneya/features/wallet/data/wallet_controller.dart';
import 'package:moneya/features/wallet/data/wallet_dtos.dart';
import 'package:moneya/features/wallet/data/wallet_repository.dart';
import 'package:moneya/l10n/generated/app_localizations.dart';
import 'package:moneya/main.dart' show LocaleScope;

const _walletJson = {'provisioned': true, 'balance': '197', 'currency': 'GHS'};

Map<String, Object?> transfer(String id, String kind, String status, {String amount = '98.5', String fee = '1.5', String? failure, String created = '2026-10-10T12:00:00.000Z'}) {
  final you = {'user_id': 'u1', 'phone': '+233201111111', 'display_name': null};
  final other = {'user_id': null, 'phone': '+233242222222', 'display_name': null};
  final incoming = kind == 'ONRAMP' || kind == 'RECEIVED';
  return {
    'id': id,
    'kind': kind,
    'status': status,
    'sender': incoming ? other : you,
    'recipient': incoming ? you : other,
    'amount': amount,
    'fee': fee,
    'currency': 'GHS',
    'note': null,
    'failure_reason': failure,
    'created_at': created,
    'completed_at': null,
  };
}

AuthSession session({String? name}) => AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      userId: 'u1',
      phone: '+233201111111',
      countryIso2: 'GH',
      kycTier: KycTier.tier0,
      fullName: name,
    );

class _NoRefresh implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) async => throw StateError('unused');
}

class _Repo extends WalletRepository {
  _Repo() : super();
  ApiResult<WalletInfo> wallet = Success(WalletInfo.fromJson(_walletJson));
  ApiResult<TransfersPage> page = Success(TransfersPage.fromJson({
    'items': [transfer('11111111-aaaa', 'ONRAMP', 'COMPLETED')],
    'has_more': false,
    'next_cursor': null,
  }));
  int walletCalls = 0;
  int pageCalls = 0;
  Completer<void>? gate;

  @override
  Future<ApiResult<WalletInfo>> getWallet() async {
    walletCalls++;
    await gate?.future;
    return wallet;
  }

  @override
  Future<ApiResult<TransfersPage>> listTransfers({int limit = 20, String? cursor, String? kind}) async {
    pageCalls++;
    return page;
  }
}

void main() {
  group('DTOs and mapping to the existing UI model', () {
    test('a completed top-up is a received, successful row with the payer as counterparty', () {
      final t = TransferItem.fromJson(transfer('0123456789ab', 'ONRAMP', 'COMPLETED')).toTransaction();
      expect(t.kind, TxnKind.received);
      expect(t.status, TxnStatus.success);
      expect(t.id, '01234567');
      expect(t.amount, '98.5');
      expect(t.fee, '1.5');
      expect(t.counterpartyPhone, '+233242222222');
      expect(t.total, '100', reason: 'what the user actually paid: 98.5 + 1.5, exactly');
    });

    test('a cash-out is a sent row addressed to the payee; statuses map to success/pending/failed', () {
      TxnStatus st(String s) => TransferItem.fromJson(transfer('x' * 12, 'OFFRAMP', s)).toTransaction().status;
      expect(TransferItem.fromJson(transfer('x' * 12, 'OFFRAMP', 'PROCESSING')).toTransaction().kind, TxnKind.sent);
      expect(st('PROCESSING'), TxnStatus.pending);
      expect(st('AWAITING_CLAIM'), TxnStatus.pending);
      expect(st('COMPLETED'), TxnStatus.success);
      expect(st('FAILED'), TxnStatus.failed);
      expect(st('EXPIRED_REFUNDED'), TxnStatus.failed);
      expect(st('CANCELLED'), TxnStatus.failed);
    });

    test('Transaction.total adds decimals exactly and never throws on junk', () {
      Transaction t(String a, String f) => Transaction(id: 'x', kind: TxnKind.sent, when: DateTime(2026), amount: a, status: TxnStatus.success, counterparty: '', counterpartyPhone: '', paymentMethod: '', fee: f);
      expect(t('0.1', '0.2').total, '0.3');
      expect(t('13000', '50').total, '13050');
      expect(t('98.50', '1.50').total, '100');
      expect(t('1e3', '1').total, '1e3');
    });

    test('malformed bodies throw instead of building half objects', () {
      expect(() => WalletInfo.fromJson({'balance': '1'}), throwsFormatException);
      expect(() => TransfersPage.fromJson({'oops': 1}), throwsFormatException);
      expect(() => TransferItem.fromJson({'id': 'x'}), throwsFormatException);
    });

    test('profile from the session: phone verified, KYC not, never an empty-name crash', () {
      final p = UserProfile.fromSession(session());
      expect(p.phoneVerified, isTrue);
      expect(p.kycVerified, isFalse);
      expect(p.initials, 'M');
      expect(UserProfile.fromSession(session(name: 'Ama Mensah')).initials, 'AM');
      expect(const UserProfile(fullName: '', phone: '', email: '', address: '', dateOfBirth: '', kycDocLabel: '', phoneVerified: false, emailVerified: false, addressVerified: false, dobVerified: false, kycVerified: false).initials, '?');
    });
  });

  group('WalletRepository', () {
    test('GET /v1/wallet and GET /v1/transfers with query parameters', () async {
      final sc = SessionController(store: SessionStore(InMemorySecureStorage()), refresher: _NoRefresh());
      await sc.bootstrap();
      await sc.setSession(session());
      final api = ApiClient.build(session: sc, appVersion: '1.0.0', localeProvider: () => 'en', baseUrlOverride: 'https://api.test');
      final adapter = _Adapter();
      api.dio.httpClientAdapter = adapter;
      final repo = WalletRepository.test(api);

      adapter.reply(200, _walletJson);
      final w = (await repo.getWallet() as Success<WalletInfo>).value;
      expect((w.balance, w.currency), ('197', 'GHS'));
      expect(adapter.last.headers['Authorization'], 'Bearer a');

      adapter.reply(200, {'items': [transfer('x' * 12, 'OFFRAMP', 'PROCESSING')], 'has_more': true, 'next_cursor': '2026|abc'});
      final p = (await repo.listTransfers(limit: 5, cursor: '2026|abc', kind: 'OFFRAMP') as Success<TransfersPage>).value;
      expect(p.items.single.kind, 'OFFRAMP');
      expect((p.hasMore, p.nextCursor), (true, '2026|abc'));
      expect(adapter.last.query, {'limit': '5', 'cursor': '2026|abc', 'kind': 'OFFRAMP'});

      adapter.reply(401, {'code': 'UNAUTHORIZED', 'title': 'x', 'status': 401});
      adapter.reply(401, {'code': 'UNAUTHORIZED', 'title': 'x', 'status': 401});
      expect((await repo.getWallet() as Failure<WalletInfo>).error, isA<AuthError>());
    });
  });

  group('WalletController', () {
    late SessionController sc;
    late _Repo repo;
    late WalletController c;

    setUp(() async {
      Get.reset();
      sc = SessionController(store: SessionStore(InMemorySecureStorage()), refresher: _NoRefresh());
      await sc.bootstrap();
      repo = _Repo();
      c = WalletController(repository: repo, session: sc);
    });

    test('without a session nothing is fetched', () async {
      await c.refresh();
      expect(repo.walletCalls + repo.pageCalls, 0);
      expect(c.loaded, isFalse);
    });

    test('loads balance and history together and exposes the four most recent', () async {
      await sc.setSession(session());
      repo.page = Success(TransfersPage.fromJson({
        'items': [for (var i = 0; i < 6; i++) transfer('00000000-000$i', 'ONRAMP', 'COMPLETED')],
        'has_more': false,
      }));
      await c.refresh();
      expect(c.wallet!.balance, '197');
      expect(c.transactions, hasLength(6));
      expect(c.recent, hasLength(4));
      expect(c.failed, isFalse);
    });

    test('concurrent refreshes share one request', () async {
      await sc.setSession(session());
      repo.gate = Completer<void>();
      final a = c.refresh();
      final b = c.refresh();
      repo.gate!.complete();
      await Future.wait([a, b]);
      expect(repo.walletCalls, 1);
    });

    test('a failed refresh keeps the last good numbers and raises the flag; the next success clears it', () async {
      await sc.setSession(session());
      await c.refresh();
      repo.wallet = const Failure(NetworkError());
      await c.refresh();
      expect(c.failed, isTrue);
      expect(c.wallet!.balance, '197', reason: 'stale money beats a blank screen');
      repo.wallet = Success(WalletInfo.fromJson({..._walletJson, 'balance': '250'}));
      await c.refresh();
      expect((c.failed, c.wallet!.balance), (false, '250'));
    });

    test('clear() forgets everything (sign-out)', () async {
      await sc.setSession(session());
      await c.refresh();
      c.clear();
      expect(c.loaded, isFalse);
      expect(c.transactions, isEmpty);
    });

    test('display name: profile name, else the phone masked', () async {
      await sc.setSession(session(name: 'Ama Mensah'));
      expect(c.displayName, 'Ama Mensah');
      await sc.setSession(session());
      expect(c.displayName, '+233201••••11');
      expect(c.displayName, isNot(contains('201111111')));
    });

    testWidgets('a finished order refreshes the wallet so the new balance shows up', (tester) async {
      await sc.setSession(session());
      Get.put<WalletController>(c);
      final done = RampOrder(
        id: 'o',
        direction: RampDirection.onramp,
        status: 'AWAITING_PAYMENT',
        quote: RampQuote(id: 'q', kind: 'ONRAMP', fromCurrency: 'GHS', fromAmount: '100', toCurrency: 'GHS', toAmount: '98.5', rate: '1', fee: '1.5', expiresAt: DateTime.utc(2030)),
        createdAt: DateTime.utc(2026),
      );
      final completed = RampOrder(id: 'o', direction: RampDirection.onramp, status: 'COMPLETED', quote: done.quote, createdAt: done.createdAt);
      await tester.pumpWidget(GetMaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RampStatusScreen(order: done, phone: '+233201111111', tracker: RampOrderTracker(repository: _OrderRepo(completed), delay: (d) async {})),
      ));
      await tester.pumpAndSettle();
      expect(repo.walletCalls, 1, reason: 'terminal state → balance re-read from the server');
    });
  });

  group('HomeScreen shows the real wallet', () {
    late SessionController sc;
    late _Repo repo;
    late WalletController c;

    setUp(() async {
      Get.reset();
      sc = SessionController(store: SessionStore(InMemorySecureStorage()), refresher: _NoRefresh());
      await sc.bootstrap();
      repo = _Repo();
      c = WalletController(repository: repo, session: sc);
    });
    tearDown(Get.reset);

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900 * 3, 1400 * 3); // wide: the test font (Ahem) makes labels huge
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LocaleScope(
        controller: LocaleController(),
        child: GetMaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: HomeScreen()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('signed in: the server balance, the user, and real history — not the demo numbers', (tester) async {
      await sc.setSession(session(name: 'Ama Mensah'));
      Get.put<SessionController>(sc);
      Get.put<WalletController>(c);
      await pump(tester);
      expect(find.text('197'), findsOneWidget);
      expect(find.text('13,000'), findsNothing);
      expect(find.textContaining('Ama Mensah'), findsWidgets);
      expect(find.text('John Doe'), findsNothing);
      expect(find.textContaining('GHC 98.50'), findsOneWidget);
      expect(repo.walletCalls, 1);
    });

    testWidgets('pull to refresh re-reads the server', (tester) async {
      await sc.setSession(session());
      Get.put<SessionController>(sc);
      Get.put<WalletController>(c);
      await pump(tester);
      repo.wallet = Success(WalletInfo.fromJson({..._walletJson, 'balance': '1234.5'}));
      await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(repo.walletCalls, 2);
      expect(find.text('1,234.50'), findsOneWidget);
    });

    testWidgets('the currency pill does not relabel real money as another currency', (tester) async {
      await sc.setSession(session());
      Get.put<SessionController>(sc);
      Get.put<WalletController>(c);
      await pump(tester);
      await tester.tap(find.text('GHC').first);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a failed first load shows a dash, never the demo balance', (tester) async {
      await sc.setSession(session());
      Get.put<SessionController>(sc);
      repo.wallet = const Failure(NetworkError());
      Get.put<WalletController>(c);
      await pump(tester);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('13,000'), findsNothing);
    });

    testWidgets('dev bypass (no session) keeps the demo data', (tester) async {
      Get.put<WalletController>(c);
      await pump(tester);
      expect(find.text('13,000'), findsOneWidget);
      expect(find.text('John Doe'), findsWidgets);
      expect(repo.walletCalls, 0);
    });
  });
}

class _OrderRepo extends RampRepository {
  _OrderRepo(this.o) : super();
  final RampOrder o;
  @override
  Future<ApiResult<RampOrder>> getOrder(RampDirection direction, String id) async => Success(o);
}

class _Req {
  _Req(this.headers, this.query);
  final Map<String, dynamic> headers;
  final Map<String, String> query;
}

class _Adapter implements HttpClientAdapter {
  final requests = <_Req>[];
  final _script = <(int, Object?)>[];
  _Req get last => requests.last;
  void reply(int status, Object? body) => _script.add((status, body));

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(_Req(Map<String, dynamic>.from(options.headers), options.uri.queryParameters));
    final (status, body) = _script.removeAt(0);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [status >= 400 ? 'application/problem+json' : 'application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
