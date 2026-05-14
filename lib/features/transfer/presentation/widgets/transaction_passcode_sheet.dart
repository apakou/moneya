import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/safe_pop.dart';
import '../../../auth/domain/passcode_policy.dart';

/// Show the transaction step-up passcode sheet and return whether the
/// user authenticated.
///
/// * `true`  — passcode matched the expected value.
/// * `false` — user exhausted [maxAttempts] (3) wrong entries; the
///   caller should soft-fail.
/// * `null`  — user dismissed the sheet (cancelled).
///
/// **Stub authentication.** The "correct" passcode is hardcoded to
/// `123456` until we wire `flutter_secure_storage` + Argon2id hashing.
/// The fintech-security skill explicitly forbids storing the raw
/// passcode anywhere — once the backend lands we'll send the entered
/// digits + server salt through Argon2id and POST the hash to a
/// `/auth/verify-passcode` endpoint that returns a short-lived
/// transaction-confirm token.
Future<bool?> showTransactionPasscodeSheet({
  required BuildContext context,
  int maxAttempts = 3,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TransactionPasscodeSheet(maxAttempts: maxAttempts),
  );
}

class _TransactionPasscodeSheet extends StatefulWidget {
  const _TransactionPasscodeSheet({required this.maxAttempts});

  final int maxAttempts;

  @override
  State<_TransactionPasscodeSheet> createState() =>
      _TransactionPasscodeSheetState();
}

class _TransactionPasscodeSheetState
    extends State<_TransactionPasscodeSheet> {
  static const String _expectedCode = '123456';

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  String? _error;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
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
    setState(() {});
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
      _onSubmit();
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

  void _clearAndRefocus() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
  }

  void _onSubmit() {
    if (!_isComplete) return;
    if (_code == _expectedCode) {
      popAfterFrame<bool>(context, true);
      return;
    }
    _attempts += 1;
    if (_attempts >= widget.maxAttempts) {
      popAfterFrame<bool>(context, false);
      return;
    }
    final remaining = widget.maxAttempts - _attempts;
    setState(() {
      _error = remaining == 1
          ? 'Wrong passcode. 1 attempt left.'
          : 'Wrong passcode. $remaining attempts left.';
    });
    _clearAndRefocus();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Confirm with passcode',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your ${PasscodePolicy.length}-digit passcode to '
                'authorise this transfer.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              _PasscodeBoxes(
                controllers: _controllers,
                focusNodes: _focusNodes,
                onChanged: _onDigitChanged,
                onKey: _onKey,
              ),
              const SizedBox(height: 12),
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
                          style: const TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: _ConfirmButton(
                  enabled: _isComplete,
                  onPressed: _onSubmit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            width: 44,
            height: 52,
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
        cursorColor: Colors.white,
        enableIMEPersonalizedLearning: false,
        enableSuggestions: false,
        autocorrect: false,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: onChanged,
        decoration: InputDecoration(
          counterText: '',
          hintText: '*',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.40),
            fontSize: 22,
            fontWeight: FontWeight.w700,
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

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? Colors.white : Colors.white.withValues(alpha: 0.50);
    final fg = enabled
        ? AppColors.actionPurple
        : AppColors.actionPurple.withValues(alpha: 0.55);
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled ? onPressed : null,
        child: Center(
          child: Text(
            'Confirm',
            style: TextStyle(
              color: fg,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
