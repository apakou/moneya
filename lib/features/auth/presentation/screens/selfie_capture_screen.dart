import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../home/presentation/screens/home_shell.dart';
import '../widgets/camera_shutter_button.dart';

/// Selfie capture screen.
///
/// Front-facing camera with an oval mask overlay matching the mock. Liveness
/// detection (blink, head turn) is intentionally NOT implemented here — that
/// will be delegated to a vendor SDK (Smile ID / Onfido / Sumsub) in a later
/// iteration. This screen captures a single still selfie which is sufficient
/// scaffolding for the rest of the onboarding flow.
class SelfieCaptureScreen extends StatefulWidget {
  const SelfieCaptureScreen({super.key});

  static const String routePath = '/auth/kyc/selfie';

  @override
  State<SelfieCaptureScreen> createState() => _SelfieCaptureScreenState();
}

class _SelfieCaptureScreenState extends State<SelfieCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
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
      // Prefer front camera for the selfie; fall back to whatever is
      // available so we don't dead-end on devices without a front cam.
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _status = _CameraStatus.ready);
    } catch (e) {
      debugPrint('Selfie camera init failed: $e');
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
      // TODO: upload `file.path` to the KYC backend along with the
      // previously captured document images, under one idempotency key.
      debugPrint('Captured selfie: ${file.path}');
      if (!mounted) return;

      // Switch to processing state BEFORE disposing the controller so the
      // next build doesn't try to render a dead CameraPreview.
      final toDispose = c;
      _controller = null;
      setState(() {
        _isCapturing = false;
        _status = _CameraStatus.processing;
      });
      await toDispose.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      _onSubmitted();
    } catch (e) {
      debugPrint('Selfie capture failed: $e');
      if (!mounted) return;
      setState(() => _isCapturing = false);
    }
  }

  void _onSubmitted() {
    // KYC selfie captured. In a later iteration this will route through
    // an "under review" screen while the backend confirms the upload;
    // for now we land directly on the home screen and clear the entire
    // onboarding stack so back-navigation can't return here.
    debugPrint('KYC selfie submitted; navigating to home.');
    if (!mounted) return;
    Get.offAll<void>(() => const HomeShell());
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
            // Layer 1: live front-camera preview filling the entire screen.
            // Mirrored horizontally so the user sees themselves naturally.
            _PreviewLayer(status: _status, controller: _controller),
            // Layer 2: brand-gradient overlay with an oval cut-out, plus
            // the white oval stroke and the instruction line.
            _OvalMaskOverlay(
              instruction: l10n.kycSelfieInstruction,
            ),
            // Layer 3: error / permission states (the cut-out is empty when
            // we don't have a preview, which is fine; the message floats on
            // top).
            if (_status == _CameraStatus.denied ||
                _status == _CameraStatus.unavailable)
              _CameraMessage(
                status: _status,
                onRetry: _bootstrap,
                onOpenSettings: openAppSettings,
              ),
            // Layer 4: processing spinner overlay.
            if (_status == _CameraStatus.processing)
              const _ProcessingOverlay(),
            // Layer 5: back chevron.
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: BackChevronButton(
                  onTap: Get.back,
                  tooltip: l10n.commonBack,
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 22,
                ),
              ),
            ),
            // Layer 6: shutter button.
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

/// Full-screen mirrored front-camera preview, or a black fill when no
/// preview is available.
class _PreviewLayer extends StatelessWidget {
  const _PreviewLayer({required this.status, required this.controller});

  final _CameraStatus status;
  final CameraController? controller;

  @override
  Widget build(BuildContext context) {
    if (status != _CameraStatus.ready ||
        controller == null ||
        !controller!.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final c = controller!;
    return Transform(
      alignment: Alignment.center,
      // Mirror horizontally so the selfie preview matches what users
      // expect from a front-facing camera ("mirror image").
      transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: c.value.previewSize?.height ?? 0,
          height: c.value.previewSize?.width ?? 0,
          child: CameraPreview(c),
        ),
      ),
    );
  }
}

/// Paints the brand gradient over the entire screen with an oval window
/// punched out through the middle, then strokes the oval in white. Also
/// renders the instruction label below the oval.
class _OvalMaskOverlay extends StatelessWidget {
  const _OvalMaskOverlay({required this.instruction});

  final String instruction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Oval geometry: centered horizontally, vertically biased toward
        // the upper half (matches the mock). Width = 72% of screen, height
        // = 1.5 × width (tall vertical oval).
        final ovalWidth = constraints.maxWidth * 0.72;
        final ovalHeight = ovalWidth * 1.5;
        final ovalCenter = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight * 0.45,
        );
        final ovalRect = Rect.fromCenter(
          center: ovalCenter,
          width: ovalWidth,
          height: ovalHeight,
        );

        // Position the instruction text just below the oval.
        final instructionTop = ovalCenter.dy + ovalHeight / 2 + 32;

        return Stack(
          children: [
            // Punched-out gradient overlay + oval stroke.
            IgnorePointer(
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _OvalPunchPainter(ovalRect: ovalRect),
              ),
            ),
            // Instruction label.
            Positioned(
              left: 24,
              right: 24,
              top: instructionTop,
              child: Text(
                instruction,
                textAlign: TextAlign.center,
                style: AppTextStyles.subsectionTitle.copyWith(height: 1.3),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OvalPunchPainter extends CustomPainter {
  const _OvalPunchPainter({required this.ovalRect});

  final Rect ovalRect;

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final fullPath = Path()..addRect(fullRect);
    final ovalPath = Path()..addOval(ovalRect);
    final masked = Path.combine(PathOperation.difference, fullPath, ovalPath);

    // Paint the brand gradient through the masked path, leaving the oval
    // window transparent so the camera preview shows through.
    final gradientShader = AppColors.brandGradient.createShader(fullRect);
    final fillPaint = Paint()
      ..shader = gradientShader
      ..style = PaintingStyle.fill;
    canvas.drawPath(masked, fillPaint);

    // Stroke the oval in white (2dp).
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawOval(ovalRect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _OvalPunchPainter old) =>
      old.ovalRect != ovalRect;
}

/// Centered semi-translucent processing spinner overlay.
class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: Colors.transparent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.kycCaptureProcessing,
              style: AppTextStyles.subsectionTitle,
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.status,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final _CameraStatus status;
  final VoidCallback onRetry;
  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDenied = status == _CameraStatus.denied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDenied ? Icons.lock_outline_rounded : Icons.videocam_off_outlined,
              color: AppColors.onBrand,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              isDenied
                  ? l10n.kycCameraDeniedMessage
                  : l10n.kycCameraUnavailableMessage,
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  isDenied ? onOpenSettings() : onRetry(),
              style: TextButton.styleFrom(foregroundColor: AppColors.onBrand),
              child: Text(
                isDenied ? l10n.kycCameraOpenSettings : l10n.kycCameraTryAgain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
