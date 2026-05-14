import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/network/api_error.dart';
import '../../../../core/network/api_result.dart';
import '../../../../core/session/step_up_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/safe_pop.dart';
import '../../../auth/domain/passcode_policy.dart';
import '../../data/transaction_auth_outcome.dart';

/// Show the transaction step-up passcode sheet and return the resulting
/// [TransactionAuthOutcome].
///
/// Behaviour:
/// * The sheet calls [StepUpController.fresh] with the entered passcode.
/// * On success → pops with [TransactionAuthAuthorised] carrying the
///   minted `X-Txn-Token`.
/// * On wrong passcode ([AuthError]) → stays open, shows remaining
///   attempts, lets the user re-enter. After [maxAttempts] consecutive
///   wrong entries the sheet pops with [TransactionAuthLockedOut].
/// * On server-side lockout ([AuthError] with status 423) → pops
///   immediately with [TransactionAuthLockedOut].
/// * On any other [ApiError] (network drop, 5xx, malformed body) →
///   pops with [TransactionAuthNetworkError].
/// * On dismiss (drag-down / tap outside / back) → pops with
///   [TransactionAuthCancelled].
///
/// The actual passcode is sent plaintext over TLS; the server hashes
/// it with Argon2id (see `client-integration-notes.md` §3 and the
/// fintech-security skill). The sheet never persists the digits — they
/// only live in the [TextEditingController]s for the lifetime of the
/// modal, and the controllers are disposed when it closes.
///
/// [stepUp] override exists for widget tests; production callers omit
/// it and the sheet resolves the singleton via `Get.find`.
Future<TransactionAuthOutcome> showTransactionPasscodeSheet({
  required BuildContext context,
  int maxAttempts = 3,
  StepUpController? stepUp,
}) async {
  final outcome = await showModalBottomSheet<TransactionAuthOutcome>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TransactionPasscodeSheet(
      maxAttempts: maxAttempts,
      stepUp: stepUp ?? Get.find<StepUpController>(),
    ),
  );
  return outcome ?? const TransactionAuthCancelled();
}

class _TransactionPasscodeSheet extends StatefulWidget {
  const _TransactionPasscodeSheet({
    required this.maxAttempts,
    required this.stepUp,
  });

  final int maxAttempts;
  final StepUpController stepUp;

  @override
  State<_TransactionPasscodeSheet> createState() =>
      _TransactionPasscodeSheetState();
}

class _TransactionPasscodeSheetState
    extends State<_TransactionPasscodeSheet> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  String? _error;
  int _attempts = 0;
  bool _submitting = false;

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

  /// Submit the entered digits to `/v1/auth/step-up` via
  /// [StepUpController]. Pops the sheet on terminal outcomes; clears
  /// and re-focuses on retryable wrong-passcode errors.
  Future<void> _onSubmit() async {
    if (!_isComplete || _submitting) return;
    setState(() => _submitting = true);

    final result = await widget.stepUp.fresh(passcode: _code);
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        _popWith(TransactionAuthAuthorised(value));
        return;
      case Failure(:final error):
        if (error is AuthError) {
          // 423 / server-side lockout: pop immediately. 401 / wrong
          // passcode: in-place retry up to [maxAttempts]; after that
          // we surface a generic lockout so the caller can prompt
          // the user to wait and retry.
          if (error.statusCode == 423) {
            _popWith(TransactionAuthLockedOut(
              error.detail ?? error.title,
            ));
            return;
          }
          _attempts += 1;
          if (_attempts >= widget.maxAttempts) {
            _popWith(TransactionAuthLockedOut(
              error.detail ?? error.title,
            ));
            return;
          }
          final remaining = widget.maxAttempts - _attempts;
          setState(() {
            _submitting = false;
            _error = remaining == 1
                ? 'Wrong passcode. 1 attempt left.'
                : 'Wrong passcode. $remaining attempts left.';
          });
          _clearAndRefocus();
          return;
        }
        // Any other ApiError (network, 5xx, unknown) — let the caller
        // surface it and the user retry by re-swiping.
        _popWith(TransactionAuthNetworkError(error));
    }
  }

  void _popWith(TransactionAuthOutcome outcome) {
    popAfterFrame<TransactionAuthOutcome>(context, outcome);
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
                enabled: !_submitting,
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
                  enabled: _isComplete && !_submitting,
                  loading: _submitting,
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
    required this.enabled,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(int index, String value) onChanged;
  final KeyEventResult Function(int index, FocusNode node, KeyEvent event)
      onKey;
  final bool enabled;

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
              enabled: enabled,
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
    required this.enabled,
    required this.onChanged,
    required this.onKey,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(FocusNode node, KeyEvent event) onKey;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: onKey,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
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
  const _ConfirmButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
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
          child: loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                )
              : Text(
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
