import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/format/money_format.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/transaction_pdf_generator.dart';
import '../../domain/transaction.dart';

/// Read-only detail screen for one [Transaction], rendered as a
/// stylized paper receipt over the brand gradient.
///
/// Layout:
///   * Edge-to-edge brand gradient strip behind the status bar +
///     header. Header has a back chevron + centered title in white.
///   * A white "receipt" card sits over the gradient/dark seam, with
///     a serrated bottom edge (sawtooth) so it visually reads as a
///     torn ticket. Inside: small status disc, counterparty name,
///     timestamp, giant signed amount, dashed divider, spec rows
///     (Fee / Total / Phone / Method / Reference), dashed divider,
///     and a "Powered by MoneyA" footer.
///   * Phone and Reference rows have a trailing copy affordance —
///     tap copies to clipboard with a light haptic + SnackBar.
///   * Below the receipt: two pill CTAs — outline "Share Receipt"
///     and filled "Download PDF". PDF generation is stubbed
///     (`debugPrint`); see project notes for the proposed `pdf` +
///     `printing` stack.
class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({
    super.key,
    required this.txn,
    required this.currencyCode,
  });

  final Transaction txn;

  /// Currency code displayed alongside the amount, e.g. `GHC`. Owned
  /// by the home screen today; will be derived from the transaction
  /// itself once the backend model carries currency per-row.
  final String currencyCode;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  /// Anchors the [RepaintBoundary] around the receipt card so we can
  /// rasterize it on demand for share. Mirrors the QR tab's pattern.
  /// The boundary wraps only the receipt itself — not the action
  /// pills or the brand gradient — so the captured PNG is a clean
  /// shareable receipt image.
  final _receiptKey = GlobalKey();

  /// True while a share-capture is in flight. Prevents double-taps
  /// of the share pill from firing two share sheets back-to-back.
  bool _capturing = false;

  /// True while a PDF is being generated + handed off to the share
  /// sheet. Prevents double-taps of the download pill.
  bool _downloading = false;

  Transaction get txn => widget.txn;
  String get currencyCode => widget.currencyCode;

  // Status palette. Same hex values used everywhere status is
  // shown — keeps the disc, label, and amount sign in sync.
  static const _green = Color(0xFF16A34A); // success
  static const _amber = Color(0xFFD97706); // pending
  static const _red = Color(0xFFDC2626); // failed

  Color get _statusColor => switch (txn.status) {
    TxnStatus.success => _green,
    TxnStatus.pending => _amber,
    TxnStatus.failed => _red,
  };

  String _statusLabel(AppLocalizations l10n) => switch (txn.status) {
    TxnStatus.success => l10n.txnDetailStatusSuccess,
    TxnStatus.pending => l10n.txnDetailStatusPending,
    TxnStatus.failed => l10n.txnDetailStatusFailed,
  };

  String _directionLabel(AppLocalizations l10n) => switch (txn.kind) {
    TxnKind.sent => l10n.txnDetailDirectionSent,
    TxnKind.received => l10n.txnDetailDirectionReceived,
  };

  IconData get _statusIcon => switch (txn.status) {
    TxnStatus.success => Icons.check_circle_rounded,
    TxnStatus.pending => Icons.schedule_rounded,
    TxnStatus.failed => Icons.error_rounded,
  };

  /// Direction-tinted color for the giant signed amount. Sent =
  /// red so the user sees money leaving; received = green.
  Color get _amountColor => switch (txn.kind) {
    TxnKind.sent => _red,
    TxnKind.received => _green,
  };

  /// `+` for received, `-` for sent.
  String get _amountSign => switch (txn.kind) {
    TxnKind.sent => '-',
    TxnKind.received => '+',
  };

  /// Inserts locale-aware thousands separators via [MoneyFormat]. Once the
  /// backend lands and amounts become numeric (Decimal/num) we'll call
  /// [MoneyFormat.fromNum] directly and drop this shim.
  String _withCommas(String s) => MoneyFormat.fromString(s);

  void _copy(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        backgroundColor: const Color(0xFF1F1F23),
        content: Text(
          l10n.txnDetailCopiedSnack(label),
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Rasterize the [RepaintBoundary] holding the receipt card to PNG
  /// bytes. Returns null if the boundary isn't yet mounted (shouldn't
  /// happen in practice — capture is only triggered by user taps
  /// after layout has settled). Uses `pixelRatio: 3.0` so the
  /// resulting image is sharp on hi-DPI receiving devices.
  Future<Uint8List?> _captureReceiptPng() async {
    final boundary =
        _receiptKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  /// Captures the on-screen receipt as a PNG and hands both the image
  /// and a plain-text caption to the platform share sheet. Mirrors
  /// the QR tab's share flow — recipients on WhatsApp, iMessage,
  /// email etc. receive a visual receipt + text summary they can
  /// search and forward.
  ///
  /// Text caption uses the same locale-formatted timestamp + same
  /// `MoneyFormat` thousands separators as the rendered receipt, so
  /// the textual content matches the image pixel-for-pixel in copy.
  Future<void> _onShare() async {
    if (_capturing) return;
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    setState(() => _capturing = true);
    try {
      final png = await _captureReceiptPng();
      if (!mounted) return;
      if (png == null) return;

      final timestamp =
          '${DateFormat.yMMMd(localeTag).format(txn.when)} • ${DateFormat.jm(localeTag).format(txn.when)}';
      final amountStr = '$_amountSign$currencyCode ${_withCommas(txn.amount)}';
      final feeStr = '$currencyCode ${_withCommas(txn.fee)}';
      final totalStr = '$currencyCode ${_withCommas(txn.total)}';

      // Reuse the existing transferSectionFrom/To keys for the
      // counterparty preposition — semantically identical to the
      // detail screen's "From X / To Y" framing and avoids
      // duplicating single-word ARB entries.
      final counterpartyLabel = switch (txn.kind) {
        TxnKind.sent => l10n.transferSectionTo,
        TxnKind.received => l10n.transferSectionFrom,
      };

      final body = [
        l10n.txnDetailShareHeader,
        '',
        l10n.txnDetailShareLineStatus(_statusLabel(l10n)),
        l10n.txnDetailShareLineDirection(_directionLabel(l10n)),
        l10n.txnDetailShareLineCounterparty(
          counterpartyLabel,
          txn.counterparty,
        ),
        l10n.txnDetailShareLineWhen(timestamp),
        '',
        l10n.txnDetailShareLineAmount(amountStr),
        l10n.txnDetailShareLineFee(feeStr),
        l10n.txnDetailShareLineTotal(totalStr),
        '',
        l10n.txnDetailShareLineMethod(txn.paymentMethod),
        l10n.txnDetailShareLinePhone(txn.counterpartyPhone),
        l10n.txnDetailShareLineReference(txn.id),
        '',
        l10n.txnDetailShareFooter,
      ].join('\n');

      HapticFeedback.selectionClick();
      await Share.shareXFiles(
        [
          XFile.fromData(
            png,
            name: 'moneya-receipt-${txn.id}.png',
            mimeType: 'image/png',
          ),
        ],
        text: body,
        subject: l10n.txnDetailShareSubject(txn.id),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Generates a typeset, vector PDF receipt and hands it to the
  /// platform share/print sheet. Users get the full set of native
  /// destinations: Save to Files (iOS/Android), AirPrint, Google
  /// Drive, WhatsApp, email — anywhere the OS can route a PDF.
  ///
  /// PDF is built off-thread by `pdf`'s deferred-rendering pipeline;
  /// the spinner stays on the pill until the share sheet appears.
  /// All copy is locale-aware via [TransactionPdfGenerator].
  Future<void> _onDownload() async {
    if (_downloading) return;
    final l10n = AppLocalizations.of(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    setState(() => _downloading = true);
    try {
      final bytes = await const TransactionPdfGenerator().build(
        txn: txn,
        currencyCode: currencyCode,
        l10n: l10n,
        localeTag: localeTag,
      );
      if (!mounted) return;
      HapticFeedback.selectionClick();
      // `Printing.sharePdf` opens the OS share sheet with PDF-aware
      // destinations (Files, AirPrint, Mail, WhatsApp, Drive). On
      // iPad / desktop a positional anchor is required; we anchor
      // it to the screen's bounds so the popover spawns from the
      // CTA region.
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'moneya-receipt-${txn.id}.pdf',
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      // Transparent so the brand-gradient `DecoratedBox` below paints
      // edge-to-edge under the status bar and home indicator.
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Column(
            children: [
              _Header(onBack: () => Navigator.of(context).maybePop()),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        // Centers the receipt+actions block when it
                        // fits in the viewport; falls back to natural
                        // top-aligned scroll when it doesn't.
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // RepaintBoundary anchors the receipt
                              // card for PNG capture in `_onShare`.
                              // Wraps only the receipt — not the
                              // action pills below — so the captured
                              // image is a clean shareable receipt.
                              RepaintBoundary(
                                key: _receiptKey,
                                child: _ReceiptCard(
                                  statusColor: _statusColor,
                                  statusLabel: _statusLabel(l10n),
                                  statusIcon: _statusIcon,
                                  counterparty: txn.counterparty,
                                  directionLabel: _directionLabel(l10n),
                                  when: txn.when,
                                  amountText:
                                      '$_amountSign$currencyCode ${_withCommas(txn.amount)}',
                                  amountColor: _amountColor,
                                  rows: [
                                    _ReceiptRowData(
                                      label: l10n.txnDetailRowFee,
                                      value:
                                          '$currencyCode ${_withCommas(txn.fee)}',
                                    ),
                                    _ReceiptRowData(
                                      label: l10n.txnDetailRowTotal,
                                      value:
                                          '$currencyCode ${_withCommas(txn.total)}',
                                      emphasize: true,
                                    ),
                                    _ReceiptRowData(
                                      label: l10n.txnDetailRowPhone,
                                      value: txn.counterpartyPhone,
                                      onCopy: () => _copy(
                                        context,
                                        label: l10n.txnDetailRowPhone,
                                        value: txn.counterpartyPhone,
                                      ),
                                    ),
                                    _ReceiptRowData(
                                      label: l10n.txnDetailRowMethod,
                                      value: txn.paymentMethod,
                                    ),
                                    _ReceiptRowData(
                                      label: l10n.txnDetailRowReference,
                                      value: txn.id,
                                      monospace: true,
                                      onCopy: () => _copy(
                                        context,
                                        label: l10n.txnDetailRowReference,
                                        value: txn.id,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),
                              _ActionPills(
                                onShare: _capturing ? null : _onShare,
                                onDownload: _downloading ? null : _onDownload,
                                shareBusy: _capturing,
                                downloadBusy: _downloading,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — back chevron + centered title.
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
      child: Row(
        children: [
          BackChevronButton(onTap: onBack, tooltip: l10n.commonBack),
          Text(l10n.txnDetailTitle, style: AppTextStyles.screenTitle),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt card — sawtooth bottom, dashed dividers inside.
// ---------------------------------------------------------------------------

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
    required this.counterparty,
    required this.directionLabel,
    required this.when,
    required this.amountText,
    required this.amountColor,
    required this.rows,
  });

  final Color statusColor;
  final String statusLabel;
  final IconData statusIcon;
  final String counterparty;
  final String directionLabel;
  final DateTime when;
  final String amountText;
  final Color amountColor;
  final List<_ReceiptRowData> rows;

  @override
  Widget build(BuildContext context) {
    // Format the timestamp at render time with the current locale so
    // month names + AM/PM render in the user's language. Single source
    // of truth replaces the (English-only) `Transaction.timestamp`
    // getter — keep that getter for debug logs only.
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final timestamp =
        '${DateFormat.yMMMd(localeTag).format(when)} • ${DateFormat.jm(localeTag).format(when)}';
    return PhysicalShape(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      clipper: const _ReceiptClipper(),
      child: Padding(
        // Extra bottom padding so content doesn't run into the
        // sawtooth teeth.
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status disc + label
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(alpha: 0.12),
                ),
                child: Icon(statusIcon, color: statusColor, size: 36),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Direction tag (SENT / RECEIVED)
            Center(
              child: Text(
                directionLabel.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFB0B0B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Counterparty
            Center(
              child: Text(
                counterparty,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF1F1F23),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                timestamp,
                style: const TextStyle(
                  color: Color(0xFF8A8A92),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Giant signed amount
            Center(
              child: HeroTextScaleClamp(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    amountText,
                    style: AppTextStyles.heroAmountReceipt.copyWith(
                      color: amountColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _DashedDivider(),
            const SizedBox(height: 8),
            // Spec rows
            for (var i = 0; i < rows.length; i++) ...[
              _ReceiptRow(data: rows[i]),
              if (i != rows.length - 1)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF0F0F2),
                ),
            ],
            const SizedBox(height: 8),
            const _DashedDivider(),
            const SizedBox(height: 16),
            // Brand mark — colored logo, sized to fit the receipt
            // footer comfortably without dominating it.
            Center(
              child: SvgPicture.asset(
                'assets/logo/logo-colored.svg',
                height: 25,
                semanticsLabel: 'MoneyA',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clipper that gives the receipt card a straight top + sides and a
/// sawtooth bottom edge. Tooth width is ~12dp; depth ~8dp. Width is
/// driven by [size] so the layout stays responsive.
class _ReceiptClipper extends CustomClipper<Path> {
  const _ReceiptClipper();

  static const double _toothWidth = 12;
  static const double _toothDepth = 8;
  static const double _radius = 16;

  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    final bottom = h - _toothDepth;

    // Rounded top-left
    path.moveTo(0, _radius);
    path.quadraticBezierTo(0, 0, _radius, 0);
    // Top edge → top-right
    path.lineTo(w - _radius, 0);
    path.quadraticBezierTo(w, 0, w, _radius);
    // Right edge down to where sawtooth starts
    path.lineTo(w, bottom);
    // Sawtooth back to x=0
    var x = w;
    var goingDown = true;
    while (x > 0) {
      final next = (x - _toothWidth).clamp(0, w).toDouble();
      path.lineTo(next, goingDown ? h : bottom);
      goingDown = !goingDown;
      x = next;
    }
    // Left edge up
    path.lineTo(0, _radius);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _ReceiptClipper oldClipper) => false;
}

// ---------------------------------------------------------------------------
// Dashed divider — pure decoration, drawn with a CustomPaint.
// ---------------------------------------------------------------------------

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: _DashedLinePainter(color: const Color(0xFFD9D9DD)),
        size: const Size(double.infinity, 1),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 4.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + dash, 0.5), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Receipt row — label left, value right (+ optional copy icon).
// ---------------------------------------------------------------------------

class _ReceiptRowData {
  const _ReceiptRowData({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.monospace = false,
    this.onCopy,
  });

  final String label;
  final String value;

  /// Bumps the value to w700 so it stands out (Total row).
  final bool emphasize;

  /// Renders the value in a monospaced face (Reference).
  final bool monospace;

  /// When non-null, a small copy icon is appended and tapping
  /// either the icon or long-pressing the row triggers it.
  final VoidCallback? onCopy;
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.data});

  final _ReceiptRowData data;

  @override
  Widget build(BuildContext context) {
    final value = Text(
      data.value,
      textAlign: TextAlign.right,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFF1F1F23),
        fontSize: data.emphasize ? 16 : 14,
        fontWeight: data.emphasize ? FontWeight.w700 : FontWeight.w600,
        fontFamily: data.monospace ? 'monospace' : null,
        letterSpacing: data.monospace ? 0.5 : 0,
        fontFeatures: data.monospace ? AppTextStyles.tabular : null,
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              data.label,
              style: const TextStyle(
                color: Color(0xFF8A8A92),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(child: value),
          if (data.onCopy != null) ...[
            const SizedBox(width: 8),
            InkResponse(
              onTap: data.onCopy,
              radius: 18,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: Color(0xFF8A8A92),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (data.onCopy != null) {
      return GestureDetector(
        onLongPress: data.onCopy,
        behavior: HitTestBehavior.opaque,
        child: row,
      );
    }
    return row;
  }
}

// ---------------------------------------------------------------------------
// Action pills — Share (outline) + Download PDF (filled).
// ---------------------------------------------------------------------------

class _ActionPills extends StatelessWidget {
  const _ActionPills({
    required this.onShare,
    required this.onDownload,
    this.shareBusy = false,
    this.downloadBusy = false,
  });

  /// Pass `null` to render the share pill in a disabled state (used
  /// while a PNG capture is in flight).
  final VoidCallback? onShare;

  /// Pass `null` to render the download pill in a disabled state
  /// (used while the PDF is being generated + the share sheet is
  /// being prepared).
  final VoidCallback? onDownload;

  /// True while the share capture is running. Swaps the leading icon
  /// for a spinner.
  final bool shareBusy;

  /// True while the PDF generation + share-sheet hand-off is running.
  /// Swaps the leading icon for a spinner.
  final bool downloadBusy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _PillButton(
            label: l10n.txnDetailActionShare,
            icon: Icons.ios_share_rounded,
            onTap: onShare,
            filled: false,
            busy: shareBusy,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PillButton(
            label: l10n.txnDetailActionDownloadPdf,
            icon: Icons.file_download_outlined,
            onTap: onDownload,
            filled: true,
            busy: downloadBusy,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.filled,
    this.busy = false,
  });

  final String label;
  final IconData icon;

  /// Pass `null` to render the pill in a disabled state.
  final VoidCallback? onTap;
  final bool filled;

  /// When true, renders a spinner in place of the leading icon.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const fg = AppColors.onBrand;
    final disabled = onTap == null;
    final bg = filled ? AppColors.actionPurple : Colors.transparent;
    final border = filled
        ? null
        : Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: disabled ? 0.55 : 1.0,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: border,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else
                  Icon(icon, color: fg, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
