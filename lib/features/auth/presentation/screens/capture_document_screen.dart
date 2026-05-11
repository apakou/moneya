import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/document_side.dart';
import '../../domain/kyc_document_type.dart';
import '../widgets/camera_shutter_button.dart';
import 'selfie_capture_screen.dart';

/// Localized instruction for capturing a given document side. The domain
/// enum's `.instruction` getter is English-only by design.
String documentSideInstruction(DocumentSide side, AppLocalizations l10n) {
  switch (side) {
    case DocumentSide.front:
      return l10n.kycCaptureFrontInstruction;
    case DocumentSide.back:
      return l10n.kycCaptureBackInstruction;
  }
}

/// Document capture screen.
///
/// Renders a live rear-camera preview clipped to a rounded "frame" cut-out
/// matching the mock; everything outside the frame is dimmed by the brand
/// gradient. After the user takes a picture, the screen advances to the next
/// step in the chain:
///   * National ID front  → National ID back
///   * National ID back   → Selfie
///   * Passport front     → Selfie
class CaptureDocumentScreen extends StatefulWidget {
  const CaptureDocumentScreen({
    super.key,
    required this.documentType,
    required this.side,
  });

  static const String routePath = '/auth/kyc/capture-document';

  final KycDocumentType documentType;
  final DocumentSide side;

  @override
  State<CaptureDocumentScreen> createState() => _CaptureDocumentScreenState();
}

class _CaptureDocumentScreenState extends State<CaptureDocumentScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  _CameraStatus _status = _CameraStatus.initializing;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    setState(() => _status = _CameraStatus.initializing);

    final granted = await _requestCameraPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _status = _CameraStatus.denied);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _status = _CameraStatus.unavailable);
        return;
      }
      // Prefer rear camera; fall back to first available.
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      _initFuture = controller.initialize();
      await _initFuture;
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _status = _CameraStatus.ready);
    } catch (e) {
      debugPrint('Camera init failed: $e');
      if (!mounted) return;
      setState(() => _status = _CameraStatus.unavailable);
    }
  }

  Future<bool> _requestCameraPermission() async {
    final current = await Permission.camera.status;
    if (current.isGranted) return true;
    if (current.isPermanentlyDenied) return false;
    final result = await Permission.camera.request();
    return result.isGranted;
  }

  Future<void> _onShutterPressed() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final file = await c.takePicture();
      // TODO: upload `file.path` (or its bytes) to the KYC backend with the
      // current session's idempotency key.
      debugPrint(
        'Captured ${widget.documentType.name} '
        '${widget.side.name}: ${file.path}',
      );
      if (!mounted) return;

      // Switch to the Processing state FIRST so the build no longer reads
      // the controller, then dispose it. Doing it the other way around
      // throws "buildPreview() was called on a disposed CameraController"
      // for one frame.
      final toDispose = c;
      _controller = null;
      setState(() {
        _isCapturing = false;
        _status = _CameraStatus.processing;
      });
      // Defer dispose past the current frame so any in-flight build that
      // already captured the old controller reference completes safely.
      await toDispose.dispose();

      // Stub for the real upload + OCR pipeline.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      _advance();
    } catch (e) {
      debugPrint('Capture failed: $e');
      if (!mounted) return;
      setState(() => _isCapturing = false);
    }
  }

  void _advance() {
    final nav = Navigator.of(context);
    if (widget.side == DocumentSide.front &&
        documentRequiresBackSide(widget.documentType)) {
      nav.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CaptureDocumentScreen(
            documentType: widget.documentType,
            side: DocumentSide.back,
          ),
        ),
      );
    } else {
      nav.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const SelfieCaptureScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Background gradient layer (visible outside the camera frame
            // and during init / error states).
            const DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.brandGradient),
            ),
            _CameraLayer(
              status: _status,
              controller: _controller,
              onRetry: _bootstrap,
              onOpenSettings: openAppSettings,
              instruction: documentSideInstruction(widget.side, l10n),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: BackChevronButton(
                  onTap: () => Navigator.of(context).maybePop(),
                  tooltip: l10n.commonBack,
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 22,
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                    child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _status == _CameraStatus.processing
                        ? const SizedBox(height: 72)
                        : CameraShutterButton(
                            enabled: _status == _CameraStatus.ready &&
                                !_isCapturing,
                            busy: _isCapturing,
                            onPressed: _onShutterPressed,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CameraStatus { initializing, ready, denied, unavailable, processing }

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// Renders the live preview clipped to a rounded rectangle frame, and the
/// instruction text below it. Falls back to messaging when the camera is
/// unavailable or permission denied.
class _CameraLayer extends StatelessWidget {
  const _CameraLayer({
    required this.status,
    required this.controller,
    required this.onRetry,
    required this.onOpenSettings,
    required this.instruction,
  });

  final _CameraStatus status;
  final CameraController? controller;
  final VoidCallback onRetry;
  final Future<bool> Function() onOpenSettings;
  final String instruction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 56, 24, 140),
        child: Column(
          children: [
            const Spacer(flex: 3),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: _previewContent(l10n),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              status == _CameraStatus.processing
                  ? 'Processing\u2026'
                  : instruction,
              textAlign: TextAlign.center,
              style: AppTextStyles.subsectionTitle.copyWith(height: 1.3),
            ),
            const Spacer(flex: 4),
          ],
        ),
      ),
    );
  }

  Widget _previewContent(AppLocalizations l10n) {
    switch (status) {
      case _CameraStatus.initializing:
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.onBrand,
            ),
          ),
        );
      case _CameraStatus.ready:
        final c = controller;
        if (c == null || !c.value.isInitialized) {
          return const SizedBox.shrink();
        }
        // Cover the frame: scale the preview so it always fills, cropping
        // overflow. Required because the camera's native aspect ratio rarely
        // matches our 4:3 frame exactly.
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.previewSize?.height ?? 0,
            height: c.value.previewSize?.width ?? 0,
            child: CameraPreview(c),
          ),
        );
      case _CameraStatus.denied:
        return _CameraMessage(
          icon: Icons.lock_outline_rounded,
          message: l10n.kycCameraDeniedMessage,
          actionLabel: l10n.kycCameraOpenSettings,
          onAction: onOpenSettings,
        );
      case _CameraStatus.unavailable:
        return _CameraMessage(
          icon: Icons.videocam_off_outlined,
          message: l10n.kycCameraUnavailableMessage,
          actionLabel: l10n.kycCameraTryAgain,
          onAction: () async {
            onRetry();
            return true;
          },
        );
      case _CameraStatus.processing:
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
              backgroundColor: Colors.transparent,
            ),
          ),
        );
    }
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final Future<bool> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.onBrand, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => onAction(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onBrand,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

// Shutter button extracted to widgets/camera_shutter_button.dart.
