import 'dart:async';

import '../domain/recipient_lookup.dart';

/// Stub recipient-lookup service.
///
/// Simulates a 600ms backend round-trip and returns either
/// [RecipientFound] or [RecipientNotFound] based on a hardcoded list of
/// "known" numbers. Replace this with a real HTTP call (dio) hitting
/// `GET /v1/users/lookup?phone=…` once the backend is wired.
///
/// Numbers are normalized to digits-only before comparing, so callers
/// can pass user-typed strings with spaces or the dial-code prefix.
class RecipientLookupService {
  const RecipientLookupService();

  /// Hardcoded directory of MoneyA users. Keyed by digits-only phone
  /// number (without the `+` or any spaces). The dial code is included
  /// because real lookups will also be rooted at E.164.
  static const Map<String, String> _knownDirectory = {
    // Côte d'Ivoire (+225) — sample numbers used in the mock.
    '22598766265': 'Xavier Brahman',
    '22598001234': 'Aminata Koffi',
    // Ghana (+233)
    '233244112233': 'Kojo Mensah',
    // Senegal (+221)
    '221770000001': 'Fatou Diop',
    // Nigeria (+234)
    '234803111222': 'Chinedu Okafor',
  };

  /// Looks up [rawPhone] (free-form digits, optionally with the dial
  /// code prefix). Returns [RecipientFound] when the number is in the
  /// stub directory, otherwise [RecipientNotFound].
  Future<RecipientLookupResult> lookup(String rawPhone) async {
    final normalized = _digitsOnly(rawPhone);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final name = _knownDirectory[normalized];
    if (name != null) {
      return RecipientFound(displayName: name);
    }
    return const RecipientNotFound();
  }

  static String _digitsOnly(String input) =>
      input.replaceAll(RegExp(r'\D'), '');
}
