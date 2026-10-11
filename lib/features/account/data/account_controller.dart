import 'package:get/get.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/logging/pii.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/api_result.dart';
import '../../../core/session/session_controller.dart';
import '../../home/domain/supported_currency.dart';
import '../../home/domain/transaction.dart';
import '../../ramp/domain/ramp_mapping.dart';
import 'account_dtos.dart';
import 'account_repository.dart';

enum LoadState { idle, loading, ready, error }

/// Live account data shown on Home and the Transactions tab: the balance in the
/// selected currency and the user's transaction history.
///
/// Reads are best-effort: a failed load keeps whatever was already on screen and
/// flips the matching [LoadState] to `error` so the UI can offer a retry.
class AccountController extends GetxService {
  AccountController({AccountRepository? repository, SessionController? session})
    : _repo = repository ?? AccountRepository(),
      _session = session;

  final AccountRepository _repo;
  final SessionController? _session;
  SessionController get _sessionOrFind =>
      _session ?? Get.find<SessionController>();

  static const int _pageSize = 20;

  final Rxn<WalletBalance> wallet = Rxn<WalletBalance>();
  final Rx<LoadState> walletState = LoadState.idle.obs;
  final RxList<Transaction> transactions = <Transaction>[].obs;
  final Rx<LoadState> transactionsState = LoadState.idle.obs;
  final RxBool loadingMore = false.obs;
  final Rx<SupportedCurrency> currency = SupportedCurrency.xof.obs;

  String? _nextCursor;
  String? _loadedFor; // user id the current data belongs to
  int _walletRequest = 0;
  int _txnRequest = 0;

  bool get hasMore => _nextCursor != null;

  /// Name shown in headers. The account has no name yet, so this is the masked
  /// phone number; it switches to the real name once the profile carries one.
  String get userLabel {
    final s = _sessionOrFind.sessionRx.value;
    if (s == null) return '';
    final name = s.fullName?.trim();
    return (name != null && name.isNotEmpty) ? name : maskPhone(s.phone);
  }

  /// Loads everything for the signed-in user. A no-op when the data already
  /// belongs to them, unless [force] is set (pull-to-refresh, after a ramp).
  Future<void> ensureLoaded({bool force = false}) async {
    final s = _sessionOrFind.sessionRx.value;
    if (s == null) return;
    if (_loadedFor != s.userId) {
      _reset();
      _loadedFor = s.userId;
      currency.value = _homeCurrency(s.countryIso2);
    } else if (!force) {
      return;
    }
    await Future.wait([_loadWallet(), _loadTransactions()]);
  }

  Future<void> refresh() => ensureLoaded(force: true);

  Future<void> selectCurrency(SupportedCurrency c) async {
    if (c == currency.value) return;
    currency.value = c;
    wallet.value =
        null; // never show another currency's amount under this label
    await _loadWallet();
  }

  Future<void> reloadWallet() => _loadWallet();
  Future<void> reloadTransactions() => _loadTransactions();

  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || loadingMore.value) return;
    loadingMore.value = true;
    final request = _txnRequest;
    final result = await _repo.transactions(limit: _pageSize, cursor: cursor);
    loadingMore.value = false;
    if (request != _txnRequest) return; // a refresh started meanwhile
    if (result case Success(:final value)) {
      transactions.addAll(value.items);
      _nextCursor = value.nextCursor;
    } else {
      _logFailure('transactions.more', result);
    }
  }

  /// Forget everything (logout / account switch).
  void clear() => _reset();

  void _reset() {
    _walletRequest++;
    _txnRequest++;
    wallet.value = null;
    walletState.value = LoadState.idle;
    transactions.clear();
    transactionsState.value = LoadState.idle;
    loadingMore.value = false;
    _nextCursor = null;
    _loadedFor = null;
  }

  Future<void> _loadWallet() async {
    final request = ++_walletRequest;
    final wire = RampMapping.wireCurrency(currency.value);
    walletState.value = LoadState.loading;
    final result = await _repo.wallet(currency: wire);
    if (request != _walletRequest) return; // superseded by a newer request
    switch (result) {
      case Success(:final value):
        wallet.value = value;
        walletState.value = LoadState.ready;
      case Failure():
        walletState.value = LoadState.error;
        _logFailure('balance', result);
    }
  }

  Future<void> _loadTransactions() async {
    final request = ++_txnRequest;
    transactionsState.value = LoadState.loading;
    final result = await _repo.transactions(limit: _pageSize);
    if (request != _txnRequest) return;
    switch (result) {
      case Success(:final value):
        transactions.assignAll(value.items);
        _nextCursor = value.nextCursor;
        transactionsState.value = LoadState.ready;
      case Failure():
        transactionsState.value = LoadState.error;
        _logFailure('transactions', result);
    }
  }

  void _logFailure(String what, ApiResult<Object?> result) {
    final error = result.errorOrNull;
    AppLogger.w('account.$what.failed', {
      'error': error is ApiError ? error.runtimeType.toString() : 'unknown',
    });
  }

  /// A user's balance currency before they pick another: their country's.
  static SupportedCurrency _homeCurrency(String iso2) => switch (iso2) {
    'GH' => SupportedCurrency.ghs,
    'NG' => SupportedCurrency.ngn,
    'KE' => SupportedCurrency.kes,
    'CM' || 'GA' || 'CG' || 'TD' || 'CF' || 'GQ' => SupportedCurrency.xaf,
    _ => SupportedCurrency.xof,
  };
}
