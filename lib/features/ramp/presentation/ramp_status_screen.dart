import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/format/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../account/data/account_controller.dart';
import '../../transfer/presentation/widgets/transfer_outcome_scaffold.dart';
import '../data/ramp_dtos.dart';
import '../data/ramp_order_tracker.dart';
import '../domain/ramp_mapping.dart';

/// Follows an accepted top-up / cash-out until it is terminal, then shows the outcome.
///
/// The state is whatever the server says (the provider webhook moves it); the screen only
/// polls. While waiting it explains what to do (approve on the phone). After the tracker's
/// timeout it does NOT claim failure: the order is alive and the user is told they'll be notified.
/// Terminal screen: back is a no-op so a finished order can't be re-submitted from the form.
class RampStatusScreen extends StatefulWidget {
  const RampStatusScreen({
    required this.order,
    required this.phone,
    this.tracker,
    super.key,
  });

  final RampOrder order;

  /// E.164 payer (top-up) or payee (cash-out) number, shown in the copy.
  final String phone;

  /// Test seam.
  final RampOrderTracker? tracker;

  @override
  State<RampStatusScreen> createState() => _RampStatusScreenState();
}

class _RampStatusScreenState extends State<RampStatusScreen> {
  late RampOrder _order = widget.order;
  StreamSubscription<RampOrder>? _sub;
  bool _gaveUp = false;
  bool _failedToTrack = false;

  @override
  void initState() {
    super.initState();
    if (_order.isTerminal) return;
    final tracker = widget.tracker ?? RampOrderTracker();
    _sub = tracker.watch(_order.direction, _order.id).listen(
      (o) {
        if (mounted) setState(() => _order = o);
        if (o.isTerminal) _refreshAccount();
      },
      onError: (Object _) {
        if (mounted) setState(() => _failedToTrack = true);
      },
      onDone: () {
        if (mounted && !_order.isTerminal) setState(() => _gaveUp = true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _amount(String amount, String wire) => '${MoneyFormat.fromString(amount)} ${RampMapping.displayCurrency(wire)}';

  /// A finished order changes the balance and the history: reload both.
  void _refreshAccount() {
    if (Get.isRegistered<AccountController>()) {
      Get.find<AccountController>().refresh();
    }
  }

  void _home() {
    _refreshAccount(); // covers leaving before the order was seen finishing
    Get.until((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final o = _order;
    final onramp = o.direction == RampDirection.onramp;
    final shown = onramp ? _amount(o.quote.toAmount, o.quote.toCurrency) : _amount(o.quote.toAmount, o.quote.toCurrency);

    late final Color color;
    late final IconData icon;
    late final String title;
    late final String body;

    if (o.isSuccess) {
      color = const Color(0xFF2BC46A);
      icon = Icons.check_rounded;
      title = onramp ? l10n.rampTopUpSuccessTitle : l10n.rampCashOutSuccessTitle;
      body = onramp ? l10n.rampTopUpSuccessBody(shown) : l10n.rampCashOutSuccessBody(shown, widget.phone);
    } else if (o.isTerminal) {
      color = const Color(0xFFE5484D);
      icon = Icons.close_rounded;
      if (onramp) {
        title = l10n.rampTopUpFailedTitle;
        body = o.failureReason == 'PROVIDER_TIMEOUT' ? l10n.rampTopUpFailedTimeoutBody : l10n.rampTopUpFailedBody;
      } else {
        title = l10n.rampCashOutFailedTitle;
        body = l10n.rampCashOutFailedBody; // REFUNDED: the money is back in the balance
      }
    } else {
      color = const Color(0xFFF5A623);
      icon = Icons.hourglass_top_rounded;
      title = onramp ? l10n.rampTopUpPendingTitle : l10n.rampCashOutPendingTitle;
      body = onramp
          ? l10n.rampTopUpPendingBody(_amount(o.quote.fromAmount, o.quote.fromCurrency))
          : l10n.rampCashOutPendingBody(shown, widget.phone);
    }

    final note = (!o.isTerminal && (_gaveUp || _failedToTrack)) ? l10n.rampSlowNote : null;
    return PopScope(
      canPop: false,
      child: TransferOutcomeScaffold(
        glyphColor: color,
        glyphIcon: icon,
        title: title,
        body: TransferOutcomeBody(spans: [TransferOutcomeBody.muted(body)]),
        extras: note == null
            ? null
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(note, key: const Key('ramp.slowNote'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
        primaryLabel: o.isTerminal && !o.isSuccess ? l10n.rampTryAgainCta : l10n.rampBackHomeCta,
        onPrimary: o.isTerminal && !o.isSuccess
            ? () {
                if (Get.key.currentState?.canPop() ?? false) Get.back<void>();
              }
            : _home,
        secondaryLabel: l10n.rampDoneCta,
        onSecondary: _home,
      ),
    );
  }
}
