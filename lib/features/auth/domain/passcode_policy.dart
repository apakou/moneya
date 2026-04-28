/// Validation rules for user-chosen passcodes.
///
/// Rules (per fintech-security skill):
/// - Exactly 6 digits.
/// - Reject all-same-digit (`000000`, `111111`, ...).
/// - Reject strictly ascending or descending sequences (`123456`, `987654`).
class PasscodePolicy {
  const PasscodePolicy._();

  static const int length = 6;

  /// Returns `null` if [code] is acceptable, otherwise a short user-facing
  /// reason string suitable for inline error copy.
  static String? validate(String code) {
    if (code.length != length) return 'Use $length digits.';
    if (!RegExp(r'^\d+$').hasMatch(code)) return 'Digits only.';
    if (_allSame(code)) return 'Avoid repeating digits.';
    if (_isSequential(code, step: 1) || _isSequential(code, step: -1)) {
      return 'Avoid sequential digits.';
    }
    return null;
  }

  static bool _allSame(String s) {
    final first = s[0];
    for (var i = 1; i < s.length; i++) {
      if (s[i] != first) return false;
    }
    return true;
  }

  static bool _isSequential(String s, {required int step}) {
    for (var i = 1; i < s.length; i++) {
      final prev = int.parse(s[i - 1]);
      final curr = int.parse(s[i]);
      if (curr - prev != step) return false;
    }
    return true;
  }
}
