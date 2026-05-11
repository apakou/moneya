import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/passcode_policy.dart';
import 'choose_kyc_document_screen.dart';

/// Whether the screen is asking the user to set a new passcode or to
/// re-enter it for confirmation.
enum PasscodeMode { set, confirm }

/// Set / confirm passcode screen.
///
/// Renders 6 masked digit boxes and a white "Next" pill. Validates the
/// passcode against [PasscodePolicy] (set mode) or against the originally
/// entered code (confirm mode).
class PasscodeScreen extends StatefulWidget {
  const PasscodeScreen({
    super.key,
    required this.mode,
    this.expectedCode,
  });

  static const String setRoutePath = '/auth/set-passcode';
  static const String confirmRoutePath = '/auth/confirm-passcode';

  final PasscodeMode mode;

  /// Required when [mode] is [PasscodeMode.confirm]; the passcode the user
  /// chose on the previous screen.
  final String? expectedCode;

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  String? _error;

  @override
  void initState() {
    super.initState();
    assert(
      widget.mode == PasscodeMode.set || widget.expectedCode != null,
      'expectedCode is required in confirm mode',
    );
    _controllers = List.generate(
      PasscodePolicy.length,
      (_) => TextEditingController(),
    );
    _focusNodes = List.generate(
      PasscodePolicy.length,
      (_) => FocusNode(),
    );
    for (final c in _controllers) {
      c.addListener(_onAnyChange);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.removeListener(_onAnyChange);
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onAnyChange() {
    if (_error != null) setState(() => _error = null);
    setState(() {}); // refresh Next button enabled state
  }

  String get _code => _controllers.map((c) => c.text).join();

  bool get _isComplete => _code.length == PasscodePolicy.length;

  void _onDigitChanged(int index, String value) {
    if (value.isEmpty) return;
    final digit = value.characters.last;
    _controllers[index].text = digit;
    _controllers[index].selection = TextSelection.collapsed(offset: 1);

    if (index < PasscodePolicy.length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
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

  void _onNext() {
    if (!_isComplete) return;
    final code = _code;
    final l10n = AppLocalizations.of(context);

    if (widget.mode == PasscodeMode.set) {
      final reason = _validateLocalized(code, l10n);
      if (reason != null) {
        setState(() => _error = reason);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PasscodeScreen(
            mode: PasscodeMode.confirm,
            expectedCode: code,
          ),
        ),
      );
      return;
    }

    // Confirm mode.
    if (code != widget.expectedCode) {
      setState(() {
        _error = l10n.passcodeMismatchError;
      });
      _clearAndRefocus();
      return;
    }
    // TODO: hash with Argon2id and POST to backend.
    _enrollBiometricThenAdvance();
  }

  /// Localized wrapper around [PasscodePolicy.validate]. Maps the policy's
  /// stable English reason strings to translated user-facing copy.
  static String? _validateLocalized(String code, AppLocalizations l10n) {
    final reason = PasscodePolicy.validate(code);
    if (reason == null) return null;
    if (reason.startsWith('Use ')) {
      return l10n.passcodeErrorWrongLength(PasscodePolicy.length);
    }
    if (reason == 'Digits only.') return l10n.passcodeErrorDigitsOnly;
    if (reason == 'Avoid repeating digits.') {
      return l10n.passcodeErrorRepeating;
    }
    if (reason == 'Avoid sequential digits.') {
      return l10n.passcodeErrorSequential;
    }
    return reason;
  }

  /// Offers to enroll biometric login. Silently skips if unavailable; treats
  /// success and user-cancel both as "advance" since biometric is optional.
  Future<void> _enrollBiometricThenAdvance() async {
    final l10n = AppLocalizations.of(context);
    final auth = LocalAuthentication();
    var enabled = false;
    try {
      final supported =
          await auth.isDeviceSupported() && await auth.canCheckBiometrics;
      if (supported) {
        final available = await auth.getAvailableBiometrics();
        if (available.isNotEmpty) {
          enabled = await auth.authenticate(
            localizedReason: l10n.passcodeBiometricReason,
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
            ),
          );
        }
      }
    } catch (_) {
      // Hardware/plugin error — treat as unavailable, just advance.
      enabled = false;
    }

    if (!mounted) return;
    // TODO: persist `enabled` flag to flutter_secure_storage.
    debugPrint('Biometric enrolled: $enabled');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const ChooseKycDocumentScreen(),
      ),
    );
  }

  void _clearAndRefocus() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSet = widget.mode == PasscodeMode.set;
    final title = isSet ? l10n.passcodeSetTitle : l10n.passcodeConfirmTitle;
    final subtitle = isSet
        ? l10n.passcodeSetSubtitle(PasscodePolicy.length)
        : l10n.passcodeConfirmSubtitle(PasscodePolicy.length);
    final ctaLabel = isSet ? l10n.passcodeNextCta : l10n.passcodeSaveCta;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        // TODO(security): set FLAG_SECURE on this screen so it doesn't appear
        // in screenshots / recent-apps previews. Requires a native plugin
        // (e.g. flutter_windowmanager or secure_application).
        resizeToAvoidBottomInset: true,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 4,
                  left: 4,
                  child: BackChevronButton(
                    onTap: () => Navigator.of(context).maybePop(),
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
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.heroAuth.copyWith(
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.onBrandMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _PasscodeBoxes(
                        controllers: _controllers,
                        focusNodes: _focusNodes,
                        onChanged: _onDigitChanged,
                        onKey: _onKey,
                      ),
                      const SizedBox(height: 16),
                      // Reserve a fixed slot for the inline error so the
                      // CTA doesn't jump when it appears.
                      SizedBox(
                        height: 20,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: _error == null
                              ? const SizedBox.shrink()
                              : Text(
                                  _error!,
                                  key: ValueKey<String>(_error!),
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.caption.copyWith(
                                    color: const Color(0xFFFF6B6B),
                                  ),
                                ),
                        ),
                      ),
                      const Spacer(flex: 1),
                      _NextButton(
                        label: ctaLabel,
                        enabled: _isComplete,
                        onPressed: _onNext,
                      ),
                      const Spacer(flex: 6),
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

/// Centered row of 6 small square passcode boxes (48dp, 8dp gaps).
class _PasscodeBoxes extends StatelessWidget {
  const _PasscodeBoxes({
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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(PasscodePolicy.length, (i) {
        return Padding(
          padding: EdgeInsets.only(
            right: i == PasscodePolicy.length - 1 ? 0 : 8,
          ),
          child: SizedBox(
            width: 48,
            height: 48,
            child: _PasscodeBox(
              controller: controllers[i],
              focusNode: focusNodes[i],
              onChanged: (v) => onChanged(i, v),
              onKey: (node, event) => onKey(i, node, event),
            ),
          ),
        );
      }),
    );
  }
}

class _PasscodeBox extends StatelessWidget {
  const _PasscodeBox({
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
        // Disable accessibility overlays on passcode entry per
        // fintech-security guidance (prevents malicious keyboards / overlays
        // from inspecting input).
        enableIMEPersonalizedLearning: false,
        enableSuggestions: false,
        autocorrect: false,
        style: AppTextStyles.numeric(AppTextStyles.sectionTitle),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: onChanged,
        decoration: InputDecoration(
          counterText: '',
          hintText: '*',
          hintStyle: AppTextStyles.sectionTitle.copyWith(
            color: Colors.white.withValues(alpha: 0.40),
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.32)),
          ),
        ),
      ),
    );
  }
}

/// White pill primary CTA with a purple label; dims when disabled.
class _NextButton extends StatelessWidget {
  const _NextButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? Colors.white : Colors.white.withValues(alpha: 0.50);
    final fg = enabled
        ? AppColors.actionPurple
        : AppColors.actionPurple.withValues(alpha: 0.55);

    return SizedBox(
      height: 56,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.subsectionTitle.copyWith(
                color: fg,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
