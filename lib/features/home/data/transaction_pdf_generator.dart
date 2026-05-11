import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/money_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/transaction.dart';

/// Generates a typeset, vector PDF receipt for a single [Transaction].
///
/// The output mirrors the on-screen receipt's information architecture
/// — branded header, status badge, counterparty + timestamp, signed
/// amount, spec rows (Fee / Total / Phone / Method / Reference), and
/// a "Powered by MoneyA" footer — but renders as native PDF text
/// (selectable, searchable, copy-pasteable in any PDF viewer) rather
/// than as a raster image.
///
/// All copy passes through `AppLocalizations` so the PDF matches the
/// user's current app language; amounts use the same `MoneyFormat`
/// thousands separators as the rendered receipt; the timestamp uses
/// `intl` `DateFormat` keyed to the active locale tag, so French
/// users see `3 mai 2026` and English users see `May 3, 2026`.
///
/// Returns the PDF document as a byte buffer suitable for
/// `Printing.sharePdf` / `Printing.layoutPdf`.
class TransactionPdfGenerator {
  const TransactionPdfGenerator();

  // -----------------------------------------------------------------
  // Brand palette — kept locally rather than pulling from
  // `AppColors` because the `pdf` package uses its own [PdfColor]
  // primitive rather than Flutter's [Color]. Values mirror the
  // brand tokens used in the on-screen receipt.
  // -----------------------------------------------------------------

  static const _brandPurple = PdfColor.fromInt(0xFF2B0033);
  static const _accentPurple = PdfColor.fromInt(0xFFB200D6);
  static const _bodyDark = PdfColor.fromInt(0xFF1F1F23);
  static const _muted = PdfColor.fromInt(0xFF8A8A92);
  static const _divider = PdfColor.fromInt(0xFFD9D9DD);
  static const _green = PdfColor.fromInt(0xFF16A34A);
  static const _amber = PdfColor.fromInt(0xFFD97706);
  static const _red = PdfColor.fromInt(0xFFDC2626);

  /// Build the PDF for [txn] and return the bytes.
  ///
  /// [currencyCode] mirrors the screen's prop — e.g. `GHC`. Once the
  /// backend lands and currency moves onto [Transaction] itself, this
  /// arg can be dropped.
  ///
  /// [l10n] is captured at the call site so we don't reach into
  /// [BuildContext] from the data layer.
  ///
  /// [localeTag] is the BCP-47 language tag used to format dates,
  /// e.g. `en-US` or `fr-FR`. Caller is responsible for ensuring
  /// `initializeDateFormatting(<tag>)` has run (already wired in
  /// `main.dart`).
  Future<Uint8List> build({
    required Transaction txn,
    required String currencyCode,
    required AppLocalizations l10n,
    required String localeTag,
  }) async {
    // Load the brand mark once, up front. `logo-colored.svg` is the
    // canonical brand asset and the single source of truth — we
    // rasterize it to PNG at PDF-build time via `_rasterizeSvg` so
    // the `pdf` package can embed it through `pw.MemoryImage` (the
    // pdf package's native `pw.Image` only accepts raster bytes; SVG
    // support exists via `pw.SvgImage` but covers only a subset of
    // the SVG spec, so runtime rasterization is the safer path).
    //
    // We rasterize at 600px tall so the PDF header logo (~36pt at
    // 72dpi ≈ 50px) stays sharp even when the user prints to A3 or
    // zooms in.
    final logoImage = await _rasterizeSvg(
      'assets/logo/logo-colored.svg',
      pixelHeight: 700,
    );

    final doc = pw.Document(
      title: 'MoneyA receipt — ${txn.id}',
      author: 'MoneyA',
      creator: 'MoneyA mobile app',
      // Subject + keywords help PDF search/indexing on macOS / Windows.
      subject: l10n.txnDetailShareHeader,
      keywords: 'MoneyA, receipt, transaction, ${txn.id}',
    );

    final timestamp =
        '${DateFormat.yMMMd(localeTag).format(txn.when)} • ${DateFormat.jm(localeTag).format(txn.when)}';
    final amountSign = switch (txn.kind) {
      TxnKind.sent => '-',
      TxnKind.received => '+',
    };
    final amountStr =
        '$amountSign$currencyCode ${MoneyFormat.fromString(txn.amount)}';
    final feeStr = '$currencyCode ${MoneyFormat.fromString(txn.fee)}';
    final totalStr = '$currencyCode ${MoneyFormat.fromString(txn.total)}';
    final amountColor = switch (txn.kind) {
      TxnKind.sent => _red,
      TxnKind.received => _green,
    };
    final statusColor = switch (txn.status) {
      TxnStatus.success => _green,
      TxnStatus.pending => _amber,
      TxnStatus.failed => _red,
    };
    final statusLabel = switch (txn.status) {
      TxnStatus.success => l10n.txnDetailStatusSuccess,
      TxnStatus.pending => l10n.txnDetailStatusPending,
      TxnStatus.failed => l10n.txnDetailStatusFailed,
    };
    final directionLabel = switch (txn.kind) {
      TxnKind.sent => l10n.txnDetailDirectionSent,
      TxnKind.received => l10n.txnDetailDirectionReceived,
    };
    final counterpartyLabel = switch (txn.kind) {
      TxnKind.sent => l10n.transferSectionTo,
      TxnKind.received => l10n.transferSectionFrom,
    };

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 56, 48, 56),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // -----------------------------------------------------
            // Header — brand logo + screen title
            // -----------------------------------------------------
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Image(logoImage, height: 36),
                pw.Text(
                  l10n.txnDetailShareHeader,
                  style: pw.TextStyle(
                    color: _muted,
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 28),

            // -----------------------------------------------------
            // Status pill — colored chip mirroring the on-screen
            // status disc, but in flat-pill form so it renders
            // crisply at PDF text resolutions.
            // -----------------------------------------------------
            pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor(
                  statusColor.red,
                  statusColor.green,
                  statusColor.blue,
                  0.12,
                ),
                borderRadius: pw.BorderRadius.circular(20),
              ),
              // Wrap in a Row so the pill hugs its content rather
              // than stretching to full container width.
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Container(
                    width: 8,
                    height: 8,
                    decoration: pw.BoxDecoration(
                      color: statusColor,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    statusLabel,
                    style: pw.TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 28),

            // -----------------------------------------------------
            // Direction tag + counterparty + timestamp
            // -----------------------------------------------------
            pw.Center(
              child: pw.Text(
                directionLabel.toUpperCase(),
                style: pw.TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                txn.counterparty,
                style: pw.TextStyle(
                  color: _bodyDark,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                timestamp,
                style: const pw.TextStyle(color: _muted, fontSize: 11),
              ),
            ),
            pw.SizedBox(height: 24),

            // -----------------------------------------------------
            // Hero amount — direction-tinted, large.
            // FittedBox-equivalent isn't available in pdf; rely on
            // the page width being wide enough for any realistic
            // amount string.
            // -----------------------------------------------------
            pw.Center(
              child: pw.Text(
                amountStr,
                style: pw.TextStyle(
                  color: amountColor,
                  fontSize: 36,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            pw.SizedBox(height: 28),

            _dashedDivider(),
            pw.SizedBox(height: 8),

            // -----------------------------------------------------
            // Spec rows — Fee / Total / Phone / Method / Reference.
            // The counterparty label/name is also surfaced here so
            // the row block is a self-contained data summary.
            // -----------------------------------------------------
            _row(counterpartyLabel, txn.counterparty),
            _rowDivider(),
            _row(l10n.txnDetailRowPhone, txn.counterpartyPhone),
            _rowDivider(),
            _row(l10n.txnDetailRowMethod, txn.paymentMethod),
            _rowDivider(),
            _row(l10n.txnDetailRowFee, feeStr),
            _rowDivider(),
            _row(l10n.txnDetailRowTotal, totalStr, emphasize: true),
            _rowDivider(),
            _row(l10n.txnDetailRowReference, txn.id, monospace: true),

            pw.SizedBox(height: 8),
            _dashedDivider(),

            // -----------------------------------------------------
            // Spacer pushes the footer down so the receipt block
            // stays anchored to the page top regardless of content
            // height.
            // -----------------------------------------------------
            pw.Expanded(child: pw.SizedBox()),

            pw.Center(
              child: pw.Text(
                l10n.txnDetailShareFooter,
                style: pw.TextStyle(
                  color: _accentPurple,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'moneya.app',
                style: const pw.TextStyle(color: _brandPurple, fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------

  pw.Widget _row(
    String label,
    String value, {
    bool emphasize = false,
    bool monospace = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: const pw.TextStyle(color: _muted, fontSize: 11),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Flexible(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                color: _bodyDark,
                fontSize: emphasize ? 13 : 12,
                fontWeight: emphasize
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                // The default pdf font (Helvetica) is proportional;
                // for the reference row we want a monospaced look so
                // tx IDs line up cleanly. Courier ships built-in
                // with the pdf package.
                font: monospace ? pw.Font.courier() : null,
                letterSpacing: monospace ? 0.4 : 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _rowDivider() =>
      pw.Container(height: 1, color: const PdfColor.fromInt(0xFFF0F0F2));

  /// Dashed horizontal divider — drawn as a row of small Containers
  /// rather than a single CustomPainter (pdf doesn't expose canvas
  /// draws inside Widget trees the same way Flutter does).
  pw.Widget _dashedDivider() {
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints?.maxWidth ?? 500;
        const dash = 4.0;
        const gap = 4.0;
        final dashCount = (width / (dash + gap)).floor();
        return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: List.generate(
            dashCount,
            (_) => pw.Container(width: dash, height: 1, color: _divider),
          ),
        );
      },
    );
  }

  /// Rasterize an SVG asset to a [pw.MemoryImage] suitable for PDF
  /// embedding.
  ///
  /// Pipeline:
  ///   1. Load the SVG bytes from rootBundle.
  ///   2. Decode via `flutter_svg`'s `vg.loadPicture` → a
  ///      `PictureInfo` carrying the parsed picture + intrinsic size.
  ///   3. Replay the picture onto a [ui.PictureRecorder] canvas
  ///      scaled so the output is [pixelHeight] tall (preserves
  ///      aspect ratio).
  ///   4. Convert the recorded picture to a [ui.Image].
  ///   5. Encode that image as PNG bytes.
  ///   6. Wrap the bytes in [pw.MemoryImage].
  ///
  /// The intermediate PNG step is unavoidable: the `pdf` package's
  /// `pw.MemoryImage` only accepts raster bytes (PNG/JPEG). Doing
  /// the rasterization at runtime — rather than shipping a pre-baked
  /// PNG — keeps `logo-colored.svg` as the single brand-asset source
  /// of truth, so any future logo update propagates automatically to
  /// the PDF receipt.
  Future<pw.MemoryImage> _rasterizeSvg(
    String assetPath, {
    required int pixelHeight,
  }) async {
    // 1. Load + decode.
    final loader = SvgAssetLoader(assetPath);
    final pictureInfo = await vg.loadPicture(loader, null);
    try {
      final intrinsicSize = pictureInfo.size;
      final scale = pixelHeight / intrinsicSize.height;
      final pixelWidth = (intrinsicSize.width * scale).round();

      // 2. Replay the picture onto a sized recorder canvas.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(scale);
      canvas.drawPicture(pictureInfo.picture);
      final scaledPicture = recorder.endRecording();

      // 3. Convert to ui.Image at the desired resolution.
      final image = await scaledPicture.toImage(pixelWidth, pixelHeight);
      try {
        // 4. Encode as PNG.
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();
        return pw.MemoryImage(pngBytes);
      } finally {
        image.dispose();
      }
    } finally {
      // PictureInfo holds a native Picture handle — must be disposed
      // explicitly to avoid leaking GPU resources across PDF builds.
      pictureInfo.picture.dispose();
    }
  }
}
