import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_result.dart';
import '../../../core/session/session_controller.dart';
import '../../home/domain/transaction.dart';
import 'wallet_dtos.dart';
import 'wallet_repository.dart';

/// The signed-in user's balance and history, from the server (never invented locally).
///
/// Rules: one refresh at a time; a failed refresh keeps the last good data (the UI shows stale money
/// rather than nothing) and sets [failed]; no session → nothing is fetched; [clear] on sign-out so one
/// user's numbers never show to the next.
class WalletController extends GetxService with ChangeNotifier {
  WalletController({WalletRepository? repository, SessionController? session})
      : _repo = repository ?? WalletRepository(),
        _session = session;

  final WalletRepository _repo;
  final SessionController? _session;
  SessionController get _sessions => _session ?? Get.find<SessionController>();

  WalletInfo? _wallet;
  List<TransferItem> _items = const [];
  bool _loading = false;
  bool _failed = false;
  bool _disposed = false;
  Future<void>? _inFlight;

  WalletInfo? get wallet => _wallet;
  bool get loaded => _wallet != null;
  bool get loading => _loading;

  /// The last refresh failed (data shown, if any, may be stale).
  bool get failed => _failed;

  /// Every loaded entry, newest first, in the shape the existing list/detail screens use.
  List<Transaction> get transactions => [for (final i in _items) i.toTransaction()];

  /// The four most recent, for the home dashboard.
  List<Transaction> get recent => transactions.take(4).toList(growable: false);

  /// Name for the home header: the profile name, else the masked phone number.
  String get displayName {
    final s = _sessions.sessionRx.value;
    if (s == null) return '';
    final name = s.fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final p = s.phone;
    return p.length > 6 ? '${p.substring(0, p.length - 6)}••••${p.substring(p.length - 2)}' : p;
  }

  /// Loads the balance and the first page of history together. Safe to call from anywhere, any time.
  Future<void> refresh() {
    if (!_sessions.hasSession) return Future.value();
    return _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);
  }

  Future<void> _doRefresh() async {
    _loading = true;
    _notify();
    final results = await Future.wait<Object>([_repo.getWallet(), _repo.listTransfers(limit: 50)]);
    final wallet = results[0] as ApiResult<WalletInfo>;
    final page = results[1] as ApiResult<TransfersPage>;
    var ok = true;
    switch (wallet) {
      case Success(:final value):
        _wallet = value;
      case Failure(:final error):
        ok = false;
        AppLogger.w('balance.refresh.failed', {'code': error.code});
    }
    switch (page) {
      case Success(:final value):
        _items = value.items;
      case Failure(:final error):
        ok = false;
        AppLogger.w('transfers.refresh.failed', {'code': error.code});
    }
    _failed = !ok;
    _loading = false;
    _notify();
  }

  /// Forget everything (sign-out).
  void clear() {
    _wallet = null;
    _items = const [];
    _failed = false;
    _loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
