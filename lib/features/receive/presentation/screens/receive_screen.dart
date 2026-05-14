import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gal/gal.dart';
import 'package:get/get.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../core/widgets/dirty_form_scope.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../home/domain/supported_currency.dart';
import '../../../home/domain/user_profile.dart';
import '../../../home/presentation/widgets/currency_picker_sheet.dart';
import '../../../transfer/data/recipient_lookup_service.dart';
import '../../../transfer/domain/recipient_lookup.dart';
import '../../../transfer/presentation/widgets/swipe_to_pay_button.dart';
import '../../../transfer/presentation/widgets/transfer_outcome_scaffold.dart';

/// Receive screen — three modes for getting paid:
///
/// 1. **Account** — show the user's MoneyA account number (their phone)
///    with copy + share affordances.
/// 2. **QR code** — render a deep-link QR (`moneya://pay?to=…`) for
///    in-person payments.
/// 3. **Request** — pick another MoneyA user, type an amount + optional
///    note, and submit a payment request.
///
/// All three modes are mocked end-to-end. Real wiring lands when:
/// - `userProvider` exposes the signed-in user (replaces `kMockUser`)
/// - `POST /payment-requests` lands (replaces the stubbed submit)
/// - `share_plus` is added to the project (replaces share `debugPrint`s)
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({required this.currency, super.key});

  /// User's currently-active home currency. Used as the default for
  /// the Request tab's amount input.
  final SupportedCurrency currency;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  /// 0 = Account, 1 = QR, 2 = Request.
  int _tab = 0;

  /// Whether the Request tab has any user-entered content. Reported
  /// up from `_RequestTab` via [_onRequestDirtyChanged] so the parent
  /// can decide whether to prompt discard-changes on back. Account /
  /// QR tabs have no user input, so dirty-tracking is gated on
  /// `_tab == 2` regardless.
  bool _requestDirty = false;

  void _onRequestDirtyChanged(bool dirty) {
    if (dirty == _requestDirty) return;
    setState(() => _requestDirty = dirty);
  }

  bool get _isDirty => _tab == 2 && _requestDirty;

  /// Back handler shared by the chevron and the system back gesture
  /// (via [DirtyFormScope]). Prompts discard-changes if the Request
  /// tab has unsaved input; the Account / QR tabs always pop without
  /// confirmation. Pop is deferred a frame inside
  /// [DirtyFormScope.confirmAndPopIfDirty] to avoid the deactivated-
  /// ancestor crash that fires when popping synchronously after the
  /// dialog.
  Future<void> _onBack() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    await DirtyFormScope.confirmAndPopIfDirty(context, _isDirty);
  }

  /// Mock signed-in user. Replace with `ref.watch(userProvider)` once
  /// Riverpod lands.
  final UserProfile _user = kMockUser;

  @override
  Widget build(BuildContext context) {
    return DirtyFormScope(
      isDirty: _isDirty,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Column(
              children: [
                _Header(onBack: _onBack),
                const SizedBox(height: 4),
                _TabSwitcher(
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 18),
                Expanded(
                  // IndexedStack keeps all three tabs mounted simultaneously
                  // and only paints the active one. This is intentional:
                  //
                  // 1. Fixes a "Looking up a deactivated widget's ancestor
                  //    is unsafe" crash that fired when navigating
                  //    Request → QR. The previous AnimatedSwitcher tore the
                  //    outgoing tab subtree down during a cross-fade, and
                  //    descendants of the QR card (RepaintBoundary +
                  //    SvgPicture wordmark) performed inherited-widget
                  //    lookups during their dispose pass.
                  // 2. Preserves the Request tab's phone / amount / note
                  //    input state across accidental tab toggles.
                  // 3. Avoids re-decoding the QR SVG wordmark every time
                  //    the user lands on the QR tab.
                  child: IndexedStack(
                    index: _tab,
                    sizing: StackFit.expand,
                    children: [
                      _AccountTab(user: _user),
                      _QrTab(user: _user),
                      _RequestTab(
                        defaultCurrency: widget.currency,
                        onDirtyChanged: _onRequestDirtyChanged,
                      ),
                    ],
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

// ---------------------------------------------------------------------------
// Account number helper
// ---------------------------------------------------------------------------

/// Returns the user's MoneyA account number — the **national subscriber
/// number** (NSN) extracted from their stored phone, with no country
/// code or formatting.
///
/// This mirrors how Opay, Wave, MoMo and most African mobile-money
/// players surface account numbers: a Ghana user sees `240987631`, a
/// Nigeria user sees `8024571234`, regardless of how the number was
/// originally entered. The full E.164 form is reserved for system-level
/// identifiers (lookup keys, SMS) — never shown as the "account number".
///
/// If parsing fails (e.g. mock data with no country code at all) we
/// fall back to the digits-only form so the UI never shows an empty
/// state. Once the backend lands and `kMockUser` is replaced with a
/// real user profile that already carries `nationalNumber` as a stored
/// field, this helper can shrink to a simple property accessor.
String accountNumberFor(UserProfile user) {
  try {
    final parsed = PhoneNumber.parse(user.phone);
    return parsed.nsn;
  } catch (_) {
    return user.phone.replaceAll(RegExp(r'\D'), '');
  }
}

/// Formats a raw NSN with thin-space groups for readability while
/// keeping it copy-paste friendly (the copy action returns the
/// unformatted digits).
///
/// Grouping rule: split into 3-3-3-… from the left, padded to whatever
/// length the input has. Works for both 9-digit (GH/CI) and 10-digit
/// (NG) NSNs without locale-specific casing.
String formatAccountNumber(String nsn) {
  if (nsn.length <= 3) return nsn;
  final buf = StringBuffer();
  for (var i = 0; i < nsn.length; i++) {
    if (i > 0 && i % 3 == 0) buf.write(' ');
    buf.write(nsn[i]);
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Header
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
          // Mark the screen title as a header so screen readers announce
          // "Receive, heading" — establishes navigation landmark.
          Semantics(
            header: true,
            child: Text(l10n.receiveTitle, style: AppTextStyles.screenTitle),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented tab switcher
// ---------------------------------------------------------------------------

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = <String>[
      l10n.receiveTabAccount,
      l10n.receiveTabQrCode,
      l10n.receiveTabRequest,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          // 8% white surface + 24% white outline meet the 3:1
          // UI-component contrast floor on the brand gradient.
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.onBrandOutline),
        ),
        padding: const EdgeInsets.all(4),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final segWidth = constraints.maxWidth / labels.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: selected * segWidth,
                  top: 0,
                  bottom: 0,
                  width: segWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.actionPurple,
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(labels.length, (i) {
                    final active = i == selected;
                    // Tab semantics: each segment exposes selected state
                    // and a friendly hint ("Activate to switch tab").
                    // VoiceOver/TalkBack will announce e.g.
                    // "Account, tab, 1 of 3, selected".
                    return Expanded(
                      child: Semantics(
                        button: true,
                        selected: active,
                        label: l10n.receiveTabSemanticLabel(labels[i]),
                        hint: active ? null : l10n.receiveTabSemanticHint,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(i),
                          child: Center(
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                // Inactive label held at 80% white so it
                                // clears the 4.5:1 body-text floor on
                                // the deepest gradient stop. Active
                                // label sits on filled actionPurple
                                // (≥4.7:1).
                                color: active
                                    ? AppColors.onBrand
                                    : AppColors.onBrandSecondary,
                                fontSize: 13,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Account
// ---------------------------------------------------------------------------

class _AccountTab extends StatelessWidget {
  const _AccountTab({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountNumber = accountNumberFor(user);
    final formatted = formatAccountNumber(accountNumber);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        children: [
          // Identity block — avatar, name, status — is announced as
          // a single semantic node so screen-reader users hear
          // "John Amoako, MoneyA member" rather than three disjoint
          // pieces.
          MergeSemantics(
            child: Column(
              children: [
                _Avatar(initials: user.initials),
                const SizedBox(height: 16),
                Text(
                  user.fullName,
                  style: const TextStyle(
                    color: AppColors.onBrand,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.receiveAccountVerifiedMember,
                  style: AppTextStyles.captionMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _AccountNumberCard(accountNumber: accountNumber),
          const SizedBox(height: 16),
          // Help text — kept at AA-readable secondary, not the
          // decorative tertiary tier.
          Text(
            l10n.receiveAccountHelpText,
            textAlign: TextAlign.center,
            style: AppTextStyles.captionMuted.copyWith(height: 1.45),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _ActionPill(
                  label: l10n.receiveAccountCopyLabel,
                  icon: Icons.copy_rounded,
                  filled: true,
                  semanticLabel: l10n.receiveAccountCopySemantic(formatted),
                  onTap: () => _copyAccountNumber(context, accountNumber),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _ActionPill(
                  label: l10n.receiveAccountShareLabel,
                  icon: Icons.ios_share_rounded,
                  filled: false,
                  semanticLabel: l10n.receiveAccountShareSemantic,
                  onTap: () => _shareAccountNumber(context, accountNumber),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyAccountNumber(BuildContext context, String accountNumber) {
    final l10n = AppLocalizations.of(context);
    // Copy the raw NSN — no spaces, no country code — so paste-targets
    // (other apps' phone-input fields, banking forms) accept it
    // verbatim.
    Clipboard.setData(ClipboardData(text: accountNumber));
    // Tactile confirmation + announce-for-accessibility so screen
    // reader users get parity with the visual SnackBar.
    HapticFeedback.selectionClick();
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.receiveAccountCopyAnnouncement,
      Directionality.of(context),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.brandPurpleDeep,
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.receiveAccountCopySnack,
                  style: const TextStyle(color: AppColors.onBrand),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _shareAccountNumber(BuildContext context, String accountNumber) {
    final l10n = AppLocalizations.of(context);
    // Hand off to the native share sheet so users can pipe their MoneyA
    // account number into WhatsApp, SMS, email, etc. The text bundles
    // the formatted (human-readable) account number plus a deep-link
    // line so MoneyA-app recipients can tap straight into a pre-filled
    // Send screen.
    final formatted = formatAccountNumber(accountNumber);
    final text =
        '${l10n.receiveAccountShareBody(formatted)}\n\n'
        'moneya://pay?to=$accountNumber';
    Share.share(text, subject: l10n.receiveAccountShareSubject);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Decorative avatar — the parent MergeSemantics will pull the
      // owning identity-block label, so we hide our raw initials text
      // from screen readers (avoids "J A" being spelled letter-by-letter
      // before the actual full name).
      excludeSemantics: true,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.actionPurple.withValues(alpha: 0.22),
          border: Border.all(color: AppColors.onBrandOutline, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: const TextStyle(
            color: AppColors.onBrand,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _AccountNumberCard extends StatelessWidget {
  const _AccountNumberCard({required this.accountNumber});

  /// Raw NSN — e.g. `240987631`. Card renders a thin-space-grouped
  /// version for readability while keeping the underlying value clean.
  final String accountNumber;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatted = formatAccountNumber(accountNumber);
    return Semantics(
      // Read as a single field, with the digits spelled out one-by-one
      // (otherwise TalkBack/VoiceOver speak "240 987 631" as
      // "two hundred forty thousand…").
      label: l10n.receiveAccountCardLabel,
      value: accountNumber.split('').join(' '),
      readOnly: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.onBrandOutline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.receiveAccountCardLabel,
              style: AppTextStyles.trackedLabel.copyWith(letterSpacing: 0.6),
            ),
            const SizedBox(height: 10),
            Text(
              formatted,
              // Allow Dynamic Type to scale the account number without
              // letting it inflate beyond the card width.
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3),
              style: const TextStyle(
                color: AppColors.onBrand,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                // Tabular figures keep digit columns from shifting if
                // a user later edits or copies the number.
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — QR
// ---------------------------------------------------------------------------

class _QrTab extends StatefulWidget {
  const _QrTab({required this.user});

  final UserProfile user;

  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  /// Anchors the [RepaintBoundary] around the white QR card so we can
  /// rasterize it on demand for share/save. The brand-tinted glow is
  /// intentionally outside this boundary — captured PNGs should be
  /// clean, opaque, white-bg shareables.
  final _qrCardKey = GlobalKey();

  bool _capturing = false;

  /// Deep-link payload encoded into the QR. Anyone with the MoneyA app
  /// scanning this lands on a pre-filled Send screen targeting the
  /// user.
  ///
  /// We encode the **MoneyA account number** (NSN) rather than the raw
  /// E.164 phone — this way the deep-link is country-agnostic on the
  /// scanning side: the receiving app already knows its own dial-code
  /// context for in-network payments.
  String get _payload {
    final account = accountNumberFor(widget.user);
    return 'moneya://pay?to=$account';
  }

  /// Rasterize the [RepaintBoundary] holding the QR card to PNG bytes.
  ///
  /// Returns null if the boundary isn't yet mounted (shouldn't happen
  /// in practice — the capture is only triggered by user taps after
  /// the layout has settled). Uses `pixelRatio: 3.0` so the resulting
  /// image is sharp on hi-DPI receiving devices.
  Future<Uint8List?> _captureQrPng() async {
    final boundary =
        _qrCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _shareQr() async {
    if (_capturing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _capturing = true);
    try {
      final png = await _captureQrPng();
      if (png == null || !mounted) return;
      final account = accountNumberFor(widget.user);
      final formatted = formatAccountNumber(account);
      HapticFeedback.selectionClick();
      await Share.shareXFiles(
        [
          XFile.fromData(
            png,
            name: 'moneya-qr-$account.png',
            mimeType: 'image/png',
          ),
        ],
        text:
            '${l10n.receiveQrShareBody(formatted)}\n\n'
            'moneya://pay?to=$account',
        subject: l10n.receiveQrShareSubject,
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _saveQr() async {
    if (_capturing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _capturing = true);
    try {
      final png = await _captureQrPng();
      if (png == null || !mounted) return;
      final account = accountNumberFor(widget.user);

      // Gal handles the runtime permission prompt internally on both
      // iOS (NSPhotoLibraryAddUsageDescription) and Android. If the
      // user denies, we surface a SnackBar instead of crashing.
      try {
        await Gal.putImageBytes(png, name: 'moneya-qr-$account');
        if (!mounted) return;
        HapticFeedback.selectionClick();
        SemanticsService.sendAnnouncement(
          View.of(context),
          l10n.receiveQrSavedAnnouncement,
          Directionality.of(context),
        );
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.brandPurpleDeep,
              content: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.receiveQrSavedSnack,
                      style: const TextStyle(color: AppColors.onBrand),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
            ),
          );
      } on GalException catch (e) {
        if (!mounted) return;
        SemanticsService.sendAnnouncement(
          View.of(context),
          l10n.receiveQrSaveErrorAnnouncement(e.type.message),
          Directionality.of(context),
        );
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.brandPurpleDeep,
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.receiveQrSaveErrorSnack(e.type.message),
                      style: const TextStyle(color: AppColors.onBrand),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 3),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountNumber = accountNumberFor(widget.user);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      child: Column(
        children: [
          // The QR is a non-text image — provide a description so
          // assistive tech can announce its purpose. We deliberately
          // do NOT spell out the deep-link payload (noisy + unhelpful)
          // and instead direct screen-reader users to the Account tab
          // where the number is presented in a readable form.
          Semantics(
            image: true,
            label: l10n.receiveQrCardSemantic,
            child: ExcludeSemantics(
              child: _QrCard(
                captureKey: _qrCardKey,
                payload: _payload,
                name: widget.user.fullName,
                accountNumber: accountNumber,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            l10n.receiveQrHelpText,
            textAlign: TextAlign.center,
            style: AppTextStyles.captionMuted.copyWith(height: 1.45),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ActionPill(
                  label: l10n.receiveQrShareLabel,
                  icon: Icons.ios_share_rounded,
                  filled: true,
                  semanticLabel: l10n.receiveQrShareSemantic,
                  busy: _capturing,
                  onTap: _capturing ? null : _shareQr,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _ActionPill(
                  label: l10n.receiveQrSaveLabel,
                  icon: Icons.download_rounded,
                  filled: false,
                  semanticLabel: l10n.receiveQrSaveSemantic,
                  busy: _capturing,
                  onTap: _capturing ? null : _saveQr,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.captureKey,
    required this.payload,
    required this.name,
    required this.accountNumber,
  });

  /// Anchors a [RepaintBoundary] around the white inner card so the
  /// [_QrTabState] can rasterize it for share/save. The brand glow is
  /// deliberately outside this boundary — captured PNGs should be
  /// clean white-bg shareables, not include the in-screen halo.
  final GlobalKey captureKey;
  final String payload;
  final String name;
  final String accountNumber;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft brand-tinted glow behind the white card. Rendered
        // outside the RepaintBoundary so it doesn't bleed into the
        // captured PNG.
        Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.actionPurple.withValues(alpha: 0.45),
                AppColors.actionPurple.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        RepaintBoundary(
          key: captureKey,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Bump error-correction to H (~30% recovery) so the
                      // overlaid logo chip below doesn't break scannability.
                      QrImageView(
                        data: payload,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.brandPurpleDeep,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.brandPurpleDeep,
                        ),
                      ),
                      // Centered white rounded chip with the MoneyA
                      // wordmark. The 560:178 viewBox of logo-colored.svg
                      // gives a ~3.15:1 aspect, so we size the chip
                      // accordingly and let SvgPicture scale to fit.
                      Container(
                        width: 76,
                        height: 28,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandPurpleDeep.withValues(
                                alpha: 0.18,
                              ),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: SvgPicture.asset(
                          'assets/logo/logo-colored.svg',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.listTitleStrong.copyWith(
                    color: AppColors.brandPurpleDeep,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatAccountNumber(accountNumber),
                  style: const TextStyle(
                    // brandPurpleDeep on pure white = 13:1 contrast
                    // — comfortably AA. Holding the caption at the
                    // full token rather than 65% alpha keeps the
                    // shareable PNG legible when reshared at small
                    // sizes (avatar thumbnails, WhatsApp previews).
                    color: AppColors.brandPurpleDeep,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3 — Request
// ---------------------------------------------------------------------------

class _RequestTab extends StatefulWidget {
  const _RequestTab({required this.defaultCurrency, this.onDirtyChanged});

  final SupportedCurrency defaultCurrency;

  /// Bubbles the tab's dirty state up to the parent so the receive
  /// screen can decide whether to prompt discard-changes on back.
  /// Fires only when the boolean value flips, not on every keystroke.
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<_RequestTab> createState() => _RequestTabState();
}

class _RequestTabState extends State<_RequestTab> {
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _lookupService = const RecipientLookupService();
  final _swipeKey = GlobalKey<SwipeToPayButtonState>();

  late SupportedCurrency _currency;
  RecipientLookupResult? _lookupResult;
  bool _looking = false;

  /// Cached last-reported dirty state so we only ping the parent on
  /// real edge transitions (any → none, none → any).
  bool _wasDirty = false;

  bool get _isDirty =>
      _phoneController.text.isNotEmpty ||
      _amountController.text.isNotEmpty ||
      _noteController.text.isNotEmpty;

  void _notifyDirty() {
    final now = _isDirty;
    if (now == _wasDirty) return;
    _wasDirty = now;
    widget.onDirtyChanged?.call(now);
  }

  @override
  void initState() {
    super.initState();
    _currency = widget.defaultCurrency;
    _phoneController.addListener(_onPhoneChanged);
    _amountController.addListener(_recomputeCanSubmit);
    _noteController.addListener(_notifyDirty);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Debounced lookup as the user types. Mirrors the transfer flow's
  /// pattern: only fire when the input parses to a complete-looking
  /// E.164-shaped number (≥9 digits after stripping non-digits).
  ///
  /// We keep this logic deliberately lightweight here — the transfer
  /// screen owns the canonical phone parsing; for the request flow the
  /// MVP just needs a plausible MoneyA phone to attach the request to.
  void _onPhoneChanged() {
    _notifyDirty();
    final raw = _phoneController.text;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) {
      if (_lookupResult != null || _looking) {
        setState(() {
          _lookupResult = null;
          _looking = false;
        });
      }
      return;
    }
    _runLookup(raw);
  }

  Future<void> _runLookup(String raw) async {
    setState(() => _looking = true);
    final result = await _lookupService.lookup(raw);
    if (!mounted) return;
    setState(() {
      _lookupResult = result;
      _looking = false;
    });
  }

  void _recomputeCanSubmit() {
    _notifyDirty();
    // Touch state so the swipe button enabled/disabled mirror flips.
    setState(() {});
  }

  bool get _canSubmit {
    final amount = double.tryParse(_amountController.text);
    return _lookupResult is RecipientFound && amount != null && amount > 0;
  }

  Future<void> _pickCurrency() async {
    final picked = await showCurrencyPickerSheet(
      context: context,
      selected: _currency,
    );
    if (picked != null && picked != _currency) {
      setState(() => _currency = picked);
    }
  }

  void _onSwipeCompleted() {
    if (!_canSubmit) {
      _swipeKey.currentState?.reset();
      return;
    }
    final found = _lookupResult as RecipientFound;
    final amount = _amountController.text;
    final note = _noteController.text.trim();

    // TODO: POST /payment-requests with idempotency key.
    debugPrint(
      'TODO: submit payment request — to=${_phoneController.text}, '
      'amount=${_currency.code} $amount, note="$note"',
    );

    Get.off<void>(
      () => _RequestSentScreen(
        recipientName: found.displayName,
        currencyCode: _currency.code,
        amount: amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 140),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RequestSectionLabel(l10n.receiveRequestSectionFrom),
              const SizedBox(height: 10),
              _PhoneField(
                controller: _phoneController,
                onClear: () {
                  _phoneController.clear();
                  setState(() {
                    _lookupResult = null;
                    _looking = false;
                  });
                },
              ),
              const SizedBox(height: 10),
              _LookupStatusRow(looking: _looking, result: _lookupResult),
              const SizedBox(height: 24),
              _RequestSectionLabel(l10n.receiveRequestSectionAmount),
              const SizedBox(height: 10),
              _AmountRow(
                currency: _currency,
                controller: _amountController,
                onCurrencyTap: _pickCurrency,
              ),
              const SizedBox(height: 24),
              _RequestSectionLabel(l10n.receiveRequestNoteLabel),
              const SizedBox(height: 10),
              _NoteField(controller: _noteController),
            ],
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          // Wrap the swipe affordance in Semantics so screen readers
          // get an explicit, accurate description regardless of whether
          // it's enabled or disabled. The visual gating
          // (AbsorbPointer + opacity) is purely affordance — the a11y
          // tree must say WHY it's disabled.
          child: Semantics(
            button: true,
            enabled: _canSubmit,
            label: l10n.receiveRequestSwipeSemanticLabel,
            hint: _canSubmit
                ? l10n.receiveRequestSwipeHintReady
                : l10n.receiveRequestSwipeHintDisabled,
            child: AbsorbPointer(
              absorbing: !_canSubmit,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: _canSubmit ? 1 : 0.5,
                child: SwipeToPayButton(
                  key: _swipeKey,
                  label: l10n.receiveRequestSwipeLabel,
                  onCompleted: _onSwipeCompleted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestSectionLabel extends StatelessWidget {
  const _RequestSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label.toUpperCase(), style: AppTextStyles.trackedLabel);
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller, required this.onClear});

  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      // 56dp matches iOS HIG / Material 3 minimum tappable input height.
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.onBrandOutline),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.smartphone_rounded,
            color: AppColors.onBrandTertiary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              cursorColor: AppColors.actionPurple,
              style: AppTextStyles.numeric(AppTextStyles.label),
              // Spell example digits one-by-one so screen readers don't
              // read the placeholder as "two hundred thirty-three…".
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '+233 24 098 7631',
                hintStyle: TextStyle(
                  color: AppColors.onBrandHint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            Semantics(
              button: true,
              label: l10n.receiveRequestClearPhoneSemantic,
              child: GestureDetector(
                onTap: onClear,
                // Pad the hit-target out to 44dp without growing the
                // visible glyph — meets iOS HIG / Material 3 minimums
                // for users with motor impairments.
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.centerRight,
                  child: const Icon(
                    Icons.cancel_rounded,
                    color: AppColors.onBrandSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LookupStatusRow extends StatelessWidget {
  const _LookupStatusRow({required this.looking, required this.result});

  final bool looking;
  final RecipientLookupResult? result;

  @override
  Widget build(BuildContext context) {
    if (looking) {
      return Semantics(
        liveRegion: true,
        child: Row(
          children: const [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onBrand,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Checking MoneyA directory…',
              style: AppTextStyles.captionMuted,
            ),
          ],
        ),
      );
    }
    if (result is RecipientFound) {
      final name = (result! as RecipientFound).displayName;
      // Live region so screen readers announce the match without the
      // user having to navigate back to the row.
      return Semantics(
        liveRegion: true,
        label: 'Recipient found: $name on MoneyA',
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'MoneyA user — $name',
                style: const TextStyle(
                  color: AppColors.onBrand,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (result is RecipientNotFound) {
      final l10n = AppLocalizations.of(context);
      return Semantics(
        liveRegion: true,
        label: l10n.receiveRequestNotOnMoneyA,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.error_outline_rounded,
                color: AppColors.warning,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'This number isn’t on MoneyA yet — you can only request '
                'from people who already have a MoneyA account.',
                style: AppTextStyles.caption,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.currency,
    required this.controller,
    required this.onCurrencyTap,
  });

  final SupportedCurrency currency;
  final TextEditingController controller;
  final VoidCallback onCurrencyTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.onBrandOutline),
      ),
      child: Row(
        children: [
          // Currency picker pill — explicit semantics so screen-reader
          // users hear "Currency, Cedi, button. Double tap to change".
          Semantics(
            button: true,
            label: 'Currency: ${currency.name}',
            hint: l10n.receiveRequestCurrencyHint,
            child: GestureDetector(
              onTap: onCurrencyTap,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.actionPurple,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Text(
                      currency.code,
                      style: AppTextStyles.pillLabel.copyWith(
                        letterSpacing: 0.6,
                        fontFeatures: AppTextStyles.tabular,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.onBrand,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              cursorColor: AppColors.actionPurple,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.onBrand,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                // Tabular figures stop the amount from jiggling as the
                // user types — important for trust at the moment of
                // payment.
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: TextStyle(
                  color: AppColors.onBrandHint,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.onBrandOutline),
      ),
      child: TextField(
        controller: controller,
        cursorColor: AppColors.actionPurple,
        maxLines: 3,
        minLines: 2,
        // Sentence capitalization matches the conversational tone
        // expected for a note field.
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(
          color: AppColors.onBrand,
          fontSize: 14,
          height: 1.35,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: l10n.receiveRequestNoteHint,
          hintStyle: const TextStyle(color: AppColors.onBrandHint),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared action pill (Copy / Share / Save)
// ---------------------------------------------------------------------------

/// Generic 56dp pill used by Account + QR tabs. `filled=true` renders
/// the brand-purple pill (primary), `filled=false` the translucent
/// outline pill (secondary).
///
/// Accessibility:
/// * Always exposes a [Semantics] node with `button: true` and
///   `enabled: onTap != null` so screen readers correctly announce
///   disabled state.
/// * Uses [semanticLabel] when the visible label alone is ambiguous
///   (e.g. "Copy" → "Copy account number 240 987 631").
/// * When [busy] is true the pill announces itself as "loading" and
///   becomes inert — it stays visible (preserves layout) but rejects
///   pointer + a11y activation to prevent double-fire of share/save.
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
    this.semanticLabel,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final bool filled;

  /// Pass `null` to render the pill in a disabled state (used while a
  /// QR-share/save capture is in flight to prevent double-taps).
  final VoidCallback? onTap;

  /// Optional override for the screen-reader label. Falls back to
  /// [label] when null.
  final String? semanticLabel;

  /// True while an async action triggered by this pill is running.
  /// Renders a spinner in place of the leading icon and announces
  /// "loading" to assistive tech.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final disabled = onTap == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel ?? label,
      hint: busy ? l10n.receiveRequestBusyHint : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          // Keep an explicit focus highlight for hardware-keyboard /
          // switch-control users — Flutter's default is invisible on
          // the brand gradient.
          focusColor: AppColors.onBrandOutline,
          highlightColor: AppColors.onBrandOutline,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: disabled ? 0.55 : 1.0,
            child: Container(
              // 56dp comfortably exceeds the 44dp iOS HIG / 48dp
              // Material 3 minimum tap target for primary CTAs.
              height: 56,
              decoration: BoxDecoration(
                color: filled
                    ? AppColors.actionPurple
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(28),
                border: filled
                    ? null
                    : Border.all(color: AppColors.onBrandOutline),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onBrand,
                      ),
                    )
                  else
                    Icon(icon, color: AppColors.onBrand, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.onBrand,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Request-sent outcome screen
// ---------------------------------------------------------------------------

/// Lightweight wrapper around [TransferOutcomeScaffold] for the
/// payment-request success state.
class _RequestSentScreen extends StatelessWidget {
  const _RequestSentScreen({
    required this.recipientName,
    required this.currencyCode,
    required this.amount,
  });

  final String recipientName;
  final String currencyCode;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Terminal outcome — back must not return to the request form
    // (re-submission risk). Predictive back is a no-op here; the
    // user exits via the primary CTA. See flutter-navigation §4/§5.
    return PopScope(
      canPop: false,
      child: TransferOutcomeScaffold(
        glyphColor: AppColors.success,
        glyphIcon: Icons.send_rounded,
        title: l10n.receiveRequestOutcomeTitle,
        body: TransferOutcomeBody(
          spans: [
            TransferOutcomeBody.muted(l10n.receiveRequestOutcomeBodyPrefix),
            TransferOutcomeBody.bold(recipientName),
            TransferOutcomeBody.muted(l10n.receiveRequestOutcomeBodyMiddle),
            TransferOutcomeBody.bold('$currencyCode $amount'),
            TransferOutcomeBody.muted(l10n.receiveRequestOutcomeBodySuffix),
          ],
        ),
        primaryLabel: l10n.receiveRequestOutcomePrimary,
        onPrimary: () {
          // Pop back to the root (HomeShell). With GetX the global
          // navigator is stable; no need to capture state ahead of
          // time the way Navigator.of(context) once required.
          Get.until((r) => r.isFirst);
        },
        secondaryLabel: l10n.receiveRequestOutcomeSecondary,
        onSecondary: () {
          // Hand the request summary off to the platform share sheet so
          // the user can also nudge the recipient via WhatsApp/SMS in
          // case the in-app notification gets missed.
          Share.share(
            l10n.receiveRequestShareBody(recipientName, currencyCode, amount),
            subject: l10n.receiveRequestShareSubject,
          );
        },
      ),
    );
  }
}
