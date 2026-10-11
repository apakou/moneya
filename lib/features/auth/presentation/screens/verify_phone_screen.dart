import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/network/api_result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../core/widgets/safe_pop.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../home/presentation/screens/home_shell.dart';
import '../../data/auth_flow.dart';
import '../auth_error_text.dart';
import 'passcode_screen.dart';

/// OTP verification screen.
///
/// Shows a 4-digit code entry with a 60s resend countdown. Auto-submits as
/// soon as the last digit is entered.
class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({
    super.key,
    required this.dialCode,
    required this.nationalNumber,
    required this.phoneE164,
  });

  static const String routePath = '/auth/verify-phone';
  static const String routeName = 'verify_phone';

  /// Country dial code without the leading `+`, e.g. `233`.
  final String dialCode;

  /// National-significant number (digits only or with spaces), used to derive
  /// the masked tail shown in the subtitle.
  final String nationalNumber;

  /// Full number in E.164 (`+233201234567`) the code was sent to.
  final String phoneE164;

  /// Matches `OtpVerifyRequest.code` (`^[0-9]{6}$`) in `openapi.yaml`.
  static const int codeLength = 6;
  static const int resendSeconds = 60;

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  Timer? _ticker;
  int _remaining = VerifyPhoneScreen.resendSeconds;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      VerifyPhoneScreen.codeLength,
      (_) => TextEditingController(),
    );
    _focusNodes = List.generate(
      VerifyPhoneScreen.codeLength,
      (_) => FocusNode(),
    );
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _ticker?.cancel();
    setState(() => _remaining = VerifyPhoneScreen.resendSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  void _onDigitChanged(int index, String value) {
    if (value.isEmpty) return;
    // Take only the last typed character (handles paste / IME quirks).
    final digit = value.characters.last;
    _controllers[index].text = digit;
    _controllers[index].selection = TextSelection.collapsed(offset: 1);

    if (index < VerifyPhoneScreen.codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
      _maybeSubmit();
    }
  }

  KeyEventResult _onKey(int index, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _maybeSubmit() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length != VerifyPhoneScreen.codeLength || _verifying) return;
    setState(() => _verifying = true);
    final result = await Get.find<AuthFlow>().verifyCode(widget.phoneE164, code);
    if (!mounted) return;
    setState(() => _verifying = false);

    switch (result) {
      case Success(:final value):
        // `Get.off`/`offAll` (not `to`) so a verified phone screen is never
        // re-enterable: the code is single-use. See flutter-navigation §4.
        if (value.passcodeSet) {
          // Returning user: the passcode already exists, go straight in.
          Get.offAll<void>(() => const HomeShell());
        } else {
          Get.off<void>(() => const PasscodeScreen(mode: PasscodeMode.set));
        }
      case Failure(:final error):
        if (error.code == 'OTP_INVALID') {
          await _showIncorrectCodeSheet();
          return;
        }
        _clearBoxes();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authErrorText(AppLocalizations.of(context), error))),
        );
    }
  }

  void _clearBoxes() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
  }

  Future<void> _showIncorrectCodeSheet() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2A2A2A),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const _IncorrectCodeSheet(),
    );
    if (!mounted) return;
    // Clear boxes and refocus first slot for a fresh retry.
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
  }

  Future<void> _requestCodeAgain() async {
    if (_remaining > 0) return;
    _clearBoxes();
    final result = await Get.find<AuthFlow>().requestCode(widget.phoneE164);
    if (!mounted) return;
    switch (result) {
      case Success():
        _startCountdown();
      case Failure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authErrorText(AppLocalizations.of(context), error))),
        );
    }
  }

  /// Returns the last 4 digits of the national number, falling back to the
  /// whole string if shorter.
  String get _maskedTail {
    final digits = widget.nationalNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return digits;
    return digits.substring(digits.length - 4);
  }

  String get _formattedTimer {
    final secs = _remaining.toString().padLeft(2, '0');
    return '00:$secs';
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
        resizeToAvoidBottomInset: true,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Stack(
              children: [
                // Back chevron (top-left).
                Positioned(
                  top: 4,
                  left: 4,
                  child: BackChevronButton(
                    onTap: Get.back,
                    tooltip: l10n.commonBack,
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 20,
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(flex: 4),

                      // --- Header ---
                      Text(
                        l10n.verifyPhoneTitle,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.heroAuth.copyWith(
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.verifyPhoneSubtitle(
                          VerifyPhoneScreen.codeLength,
                          widget.dialCode,
                          _maskedTail,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.onBrandMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // --- OTP boxes ---
                      _OtpBoxes(
                        controllers: _controllers,
                        focusNodes: _focusNodes,
                        onChanged: _onDigitChanged,
                        onKey: _onKey,
                      ),

                      const SizedBox(height: 24),

                      // --- Resend ---
                      _ResendRow(
                        canResend: _remaining == 0,
                        timerText: _formattedTimer,
                        onTap: _requestCodeAgain,
                      ),

                      const Spacer(flex: 7),
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
// Pieces
// ---------------------------------------------------------------------------

/// Row of [VerifyPhoneScreen.codeLength] single-digit boxes spaced evenly.
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
    required this.onKey,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(int index, String value) onChanged;
  final KeyEventResult Function(int index, FocusNode node, KeyEvent event)
  onKey;

  /// Preferred box size / gap; shrinks (never overflows) on narrow phones.
  static const double _maxBox = 56;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    const n = VerifyPhoneScreen.codeLength;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxWidth - _gap * (n - 1)) / n;
        final box = fit.clamp(36.0, _maxBox);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(n, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i == n - 1 ? 0 : _gap),
              child: SizedBox(
                width: box,
                height: box + 12,
                child: _OtpBox(
                  controller: controllers[i],
                  focusNode: focusNodes[i],
                  onChanged: (v) => onChanged(i, v),
                  onKey: (node, event) => onKey(i, node, event),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onKey,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(FocusNode node, KeyEvent event) onKey;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: onKey,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        obscureText: true,
        obscuringCharacter: '*',
        cursorColor: AppColors.onBrand,
        style: AppTextStyles.numeric(AppTextStyles.identityName),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        decoration: InputDecoration(
          counterText: '',
          hintText: '*',
          hintStyle: AppTextStyles.identityName.copyWith(
            color: Colors.white.withValues(alpha: 0.40),
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: EdgeInsets.symmetric(vertical: 20),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.32)),
          ),
        ),
      ),
    );
  }
}

/// "Didn't received the code ?" + "Request code again 00:59s" rich text.
class _ResendRow extends StatelessWidget {
  const _ResendRow({
    required this.canResend,
    required this.timerText,
    required this.onTap,
  });

  final bool canResend;
  final String timerText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const muted = TextStyle(
      color: AppColors.onBrandMuted,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
    );
    final linkStyle = AppTextStyles.bodyLink.copyWith(
      color: canResend ? AppColors.actionPurple : AppColors.onBrandMuted,
    );

    return Column(
      children: [
        Text(
          l10n.verifyPhoneResendPrompt,
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 2),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canResend ? onTap : null,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: l10n.verifyPhoneResendLink, style: linkStyle),
                if (!canResend) ...[
                  const TextSpan(text: ' ', style: muted),
                  TextSpan(
                    text: timerText,
                    style: AppTextStyles.bodyLink.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: AppTextStyles.tabular,
                    ),
                  ),
                ],
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet shown when the entered OTP is wrong.
///
/// Dark surface, large red ✕, "Incorrect code entered" title, muted body,
/// and a white "Got it" pill that pops the sheet.
class _IncorrectCodeSheet extends StatelessWidget {
  const _IncorrectCodeSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Center(
              child: Icon(
                Icons.close_rounded,
                color: Color(0xFFFF3B30),
                size: 56,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.verifyPhoneIncorrectTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.sectionTitle.copyWith(
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.verifyPhoneIncorrectBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.onBrandMuted,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 28),
            _GotItButton(onPressed: () => popAfterFrame(context)),
          ],
        ),
      ),
    );
  }
}

/// White pill button with a purple "Got it" label. Used only inside the
/// incorrect-code sheet (matches the design mock).
class _GotItButton extends StatelessWidget {
  const _GotItButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.white,
        shape: const StadiumBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Center(
            child: Text(
              l10n.verifyPhoneGotIt,
              style: AppTextStyles.subsectionTitle.copyWith(
                color: AppColors.actionPurple,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
