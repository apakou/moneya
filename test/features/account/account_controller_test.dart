import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:moneya/core/network/api_error.dart';
import 'package:moneya/core/network/api_result.dart';
import 'package:moneya/core/session/auth_session.dart';
import 'package:moneya/core/session/session_controller.dart';
import 'package:moneya/core/session/session_store.dart';
import 'package:moneya/core/storage/secure_storage.dart';
import 'package:moneya/features/account/data/account_controller.dart';
import 'package:moneya/features/account/data/account_dtos.dart';
import 'package:moneya/features/account/data/account_repository.dart';
import 'package:moneya/features/home/domain/supported_currency.dart';
import 'package:moneya/features/home/domain/transaction.dart';

class _NoRefresh implements SessionRefresher {
  @override
  Future<AuthSession> refresh(AuthSession current) async =>
      throw StateError('unused');
}

Transaction _txn(String id) => Transaction(
  id: id,
  kind: TxnKind.received,
  when: DateTime(2026, 10, 11),
  amount: '100',
  currencyCode: 'GHC',
  status: TxnStatus.success,
  counterparty: 'x',
  counterpartyPhone: '+233201234567',
  paymentMethod: 'm',
);

class _FakeRepo extends AccountRepository {
  final walletCalls = <String?>[];
  ApiResult<WalletBalance> walletResult = const Success(
    WalletBalance(
      currency: 'GHS',
      balance: '197',
      availableBalance: '197',
      equivalentBalance: '197',
      provisioned: false,
    ),
  );
  List<TransactionPage> pages = [
    TransactionPage(items: [_txn('A'), _txn('B')], nextCursor: 'c1'),
    TransactionPage(items: [_txn('C')], nextCursor: null),
  ];
  ApiResult<TransactionPage>? txnOverride;
  final cursors = <String?>[];

  @override
  Future<ApiResult<WalletBalance>> wallet({String? currency}) async {
    walletCalls.add(currency);
    return walletResult;
  }

  @override
  Future<ApiResult<TransactionPage>> transactions({
    int limit = 20,
    String? cursor,
  }) async {
    cursors.add(cursor);
    return txnOverride ?? Success(cursor == null ? pages[0] : pages[1]);
  }
}

Future<SessionController> _session({
  String country = 'GH',
  String? name,
}) async {
  final s = SessionController(
    store: SessionStore(InMemorySecureStorage()),
    refresher: _NoRefresh(),
  );
  await s.bootstrap();
  await s.setSession(
    AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      userId: 'u1',
      phone: '+233201234567',
      countryIso2: country,
      kycTier: KycTier.tier0,
      fullName: name,
    ),
  );
  return s;
}

void main() {
  setUp(Get.reset);

  test(
    'ensureLoaded starts in the home currency and loads balance + first page',
    () async {
      final repo = _FakeRepo();
      final c = AccountController(repository: repo, session: await _session());
      await c.ensureLoaded();
      expect(c.currency.value, SupportedCurrency.ghs);
      expect(repo.walletCalls, ['GHS']); // wire code, not the legacy GHC
      expect(c.wallet.value!.balance, '197');
      expect(c.walletState.value, LoadState.ready);
      expect(c.transactions.map((t) => t.id), ['A', 'B']);
      expect(c.hasMore, isTrue);
    },
  );

  test('home currency follows the country', () async {
    final c = AccountController(
      repository: _FakeRepo(),
      session: await _session(country: 'TG'),
    );
    await c.ensureLoaded();
    expect(c.currency.value, SupportedCurrency.xof);
  });

  test('a second ensureLoaded is a no-op; force reloads', () async {
    final repo = _FakeRepo();
    final c = AccountController(repository: repo, session: await _session());
    await c.ensureLoaded();
    await c.ensureLoaded();
    expect(repo.walletCalls, hasLength(1));
    await c.refresh();
    expect(repo.walletCalls, hasLength(2));
  });

  test('loadMore appends the next page and stops at the end', () async {
    final repo = _FakeRepo();
    final c = AccountController(repository: repo, session: await _session());
    await c.ensureLoaded();
    await c.loadMore();
    expect(c.transactions.map((t) => t.id), ['A', 'B', 'C']);
    expect(c.hasMore, isFalse);
    await c.loadMore(); // no cursor → no request
    expect(repo.cursors, [null, 'c1']);
  });

  test(
    'switching currency clears the old amount and loads that currency',
    () async {
      final repo = _FakeRepo();
      final c = AccountController(repository: repo, session: await _session());
      await c.ensureLoaded();
      final pending = c.selectCurrency(SupportedCurrency.xof);
      expect(c.wallet.value, isNull); // never show GHS under the XOF label
      await pending;
      expect(repo.walletCalls.last, 'XOF');
    },
  );

  test(
    'a failed load flips the state to error and keeps the list usable',
    () async {
      final repo = _FakeRepo()
        ..walletResult = const Failure(NetworkError())
        ..txnOverride = const Failure(NetworkError());
      final c = AccountController(repository: repo, session: await _session());
      await c.ensureLoaded();
      expect(c.walletState.value, LoadState.error);
      expect(c.transactionsState.value, LoadState.error);
      expect(c.wallet.value, isNull);
      expect(c.transactions, isEmpty);
    },
  );

  test('userLabel is the masked phone until the account has a name', () async {
    final anon = AccountController(
      repository: _FakeRepo(),
      session: await _session(),
    );
    expect(anon.userLabel, '+233 ** ** ** 67');
    final named = AccountController(
      repository: _FakeRepo(),
      session: await _session(name: 'Ama Mensah'),
    );
    expect(named.userLabel, 'Ama Mensah');
  });
}
