import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Cash App / Wise-style numeric keypad for entering a transfer amount.
///
/// The user taps the big amount card on the Transfer screen which opens
/// this sheet. The currency code is fixed (passed in) and only the
/// numeric portion is editable. We support a single decimal point and
/// up to 9 digits before the decimal — enough for any real-world fiat
/// transfer in the corridors we serve.
///
/// Returns the entered amount as a digits-only (with optional `.`)
/// string via `Navigator.pop`, or `null` if dismissed.
Future<String?> showAmountKeypadSheet({
  required BuildContext context,
  required String currencyCode,
  required String initialAmount,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => _AmountKeypadSheet(
      currencyCode: currencyCode,
      initialAmount: initialAmount,
    ),
  );
}

class _AmountKeypadSheet extends StatefulWidget {
  const _AmountKeypadSheet({
    required this.currencyCode,
    required this.initialAmount,
  });

  final String currencyCode;
  final String initialAmount;

  @override
  State<_AmountKeypadSheet> createState() => _AmountKeypadSheetState();
}

class _AmountKeypadSheetState extends State<_AmountKeypadSheet> {
  // Max integer digits we accept; arbitrary but big enough for any
  // realistic cross-border transfer in the corridors we serve.
  static const int _maxIntegerDigits = 9;

  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialAmount.isEmpty ? '0' : widget.initialAmount;
  }

  void _onDigit(String d) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_value == '0') {
        _value = d;
        return;
      }
      final dotIndex = _value.indexOf('.');
      if (dotIndex == -1) {
        if (_value.length >= _maxIntegerDigits) return;
        _value = '$_value$d';
      } else {
        // Cap at 2 decimal places.
        final decimals = _value.length - dotIndex - 1;
        if (decimals >= 2) return;
        _value = '$_value$d';
      }
    });
  }

  void _onDot() {
    HapticFeedback.selectionClick();
    if (_value.contains('.')) return;
    setState(() => _value = '$_value.');
  }

  void _onBackspace() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_value.length <= 1) {
        _value = '0';
      } else {
        _value = _value.substring(0, _value.length - 1);
      }
    });
  }

  void _onConfirm() {
    // Strip a trailing dot so callers don't have to deal with "100.".
    final cleaned = _value.endsWith('.')
        ? _value.substring(0, _value.length - 1)
        : _value;
    Navigator.of(context).pop(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A0220),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, right: 8),
                    child: Text(
                      widget.currencyCode,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _value,
                        style: AppTextStyles.heroAmountKeypad,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _Keypad(
                onDigit: _onDigit,
                onDot: _onDot,
                onBackspace: _onBackspace,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.actionPurple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context).amountKeypadDoneCta,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onDot,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDot;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _KeypadKey(label: d, onTap: () => onDigit(d));
    return Column(
      children: [
        Row(children: [digit('1'), digit('2'), digit('3')]),
        const SizedBox(height: 8),
        Row(children: [digit('4'), digit('5'), digit('6')]),
        const SizedBox(height: 8),
        Row(children: [digit('7'), digit('8'), digit('9')]),
        const SizedBox(height: 8),
        Row(
          children: [
            _KeypadKey(label: '.', onTap: onDot),
            digit('0'),
            _KeypadKey(
              icon: Icons.backspace_rounded,
              onTap: onBackspace,
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({this.label, this.icon, required this.onTap})
      : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 56,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: icon != null
                  ? Icon(icon, color: Colors.white, size: 24)
                  : Text(
                      label!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
