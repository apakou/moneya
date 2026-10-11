import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/format/money_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/ramp_dtos.dart';
import '../domain/ramp_mapping.dart';

/// The locked price: what the user receives, the all-in fee, and how long it holds.
///
/// Fiat only (plan §1.1). The countdown is shown, not hidden: when it ends the card says so and
/// offers a refresh — a new price is never swapped in silently.
class RampQuoteCard extends StatefulWidget {
  const RampQuoteCard({
    required this.direction,
    required this.quote,
    required this.loading,
    required this.failed,
    required this.onRefresh,
    this.now,
    super.key,
  });

  final RampDirection direction;
  final RampQuote? quote;
  final bool loading;
  final bool failed;
  final VoidCallback onRefresh;

  /// Test seam.
  final DateTime Function()? now;

  @override
  State<RampQuoteCard> createState() => _RampQuoteCardState();
}

class _RampQuoteCardState extends State<RampQuoteCard> {
  Timer? _ticker;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.quote != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _money(String amount, String wireCurrency) =>
      '${MoneyFormat.fromString(amount)} ${RampMapping.displayCurrency(wireCurrency)}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = widget.quote;
    final style = const TextStyle(color: AppColors.onBrand, fontSize: 15, fontWeight: FontWeight.w500);
    final muted = const TextStyle(color: AppColors.onBrandMuted, fontSize: 13);

    Widget body;
    if (widget.failed) {
      body = Row(children: [
        Expanded(child: Text(l10n.rampQuoteError, style: muted)),
        TextButton(onPressed: widget.onRefresh, child: Text(l10n.rampQuoteRefresh)),
      ]);
    } else if (q == null) {
      body = Center(
        child: widget.loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const SizedBox.shrink(),
      );
    } else {
      final secs = q.expiresAt.difference(_now()).inSeconds;
      final expired = secs <= 0;
      final receiveLabel =
          widget.direction == RampDirection.onramp ? l10n.rampQuoteTopUpReceiveLabel : l10n.rampQuotePayoutReceiveLabel;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(receiveLabel, _money(q.toAmount, q.toCurrency), style, key: const Key('quote.receive')),
          const SizedBox(height: 8),
          _row(l10n.rampQuoteFeeLabel, _money(q.fee, q.fromCurrency), muted, key: const Key('quote.fee')),
          const SizedBox(height: 8),
          if (expired)
            Row(children: [
              Expanded(child: Text(l10n.rampQuoteExpired, style: muted, key: const Key('quote.expired'))),
              TextButton(onPressed: widget.onRefresh, child: Text(l10n.rampQuoteRefresh)),
            ])
          else
            Text(l10n.rampQuoteValidFor(secs), style: muted, key: const Key('quote.countdown')),
        ],
      );
    }

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: body,
      ),
    );
  }

  Widget _row(String label, String value, TextStyle style, {Key? key}) => Row(
        key: key,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      );
}
