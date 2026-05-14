/// Small helpers for redacting personally-identifying or security-sensitive
/// strings before they reach logs, breadcrumbs, or analytics events.
///
/// The rules here are intentionally conservative: when in doubt, redact. The
/// network/auth code paths funnel through these helpers so a single audit
/// surface covers every log line that touches phones, tokens, codes, or money
/// amounts.
///
/// None of these helpers throw on malformed input — they return the safest
/// possible string and let the caller proceed. Logging must never be the
/// reason a request fails.
library;

/// Mask an E.164 phone number into the shape `+221 ** ** ** 42`.
///
/// Keeps the leading `+` and the country dial prefix (digits up to the third
/// character) visible, plus the last two digits. Everything else becomes `*`.
/// Falls back to `'***'` if the input is too short to mask meaningfully.
String maskPhone(String? e164) {
  if (e164 == null || e164.length < 6) return '***';
  final stripped = e164.trim();
  if (stripped.length < 6) return '***';
  // Keep "+XXX" prefix + last two digits.
  final prefixEnd = stripped.startsWith('+') ? 4 : 3;
  if (stripped.length <= prefixEnd + 2) return '***';
  final prefix = stripped.substring(0, prefixEnd);
  final tail = stripped.substring(stripped.length - 2);
  return '$prefix ** ** ** $tail';
}

/// Mask a bearer token / JWT / opaque secret into the shape `eyJh…ab12`.
///
/// Useful for breadcrumbs that need to correlate sessions across logs without
/// exposing the token itself.
String maskToken(String? token) {
  if (token == null) return '***';
  final t = token.trim();
  if (t.length < 12) return '***';
  return '${t.substring(0, 4)}…${t.substring(t.length - 4)}';
}

/// Always return `***` for one-time codes, passcodes, PINs, OTP digits.
/// These are short enough that any partial reveal weakens the secret.
String maskSecret(Object? _) => '***';

/// Mask an email into the shape `j***@example.com`.
String maskEmail(String? email) {
  if (email == null) return '***';
  final at = email.indexOf('@');
  if (at <= 0 || at == email.length - 1) return '***';
  final first = email.substring(0, 1);
  final domain = email.substring(at);
  return '$first***$domain';
}

/// Redact known PII keys inside an arbitrary map (request body, response
/// body, query string parsed to a map). Recursively descends into nested
/// maps and lists. The returned map is a fresh copy — the input is never
/// mutated.
///
/// Keys are matched case-insensitively against [_piiKeys].
Map<String, Object?> redactMap(Map<String, Object?> input) {
  final out = <String, Object?>{};
  input.forEach((k, v) {
    final lower = k.toLowerCase();
    if (_piiKeys.contains(lower)) {
      out[k] = '***';
    } else if (_phoneKeys.contains(lower) && v is String) {
      out[k] = maskPhone(v);
    } else if (_tokenKeys.contains(lower) && v is String) {
      out[k] = maskToken(v);
    } else if (v is Map<String, Object?>) {
      out[k] = redactMap(v);
    } else if (v is List) {
      out[k] = v
          .map((e) => e is Map<String, Object?> ? redactMap(e) : e)
          .toList(growable: false);
    } else {
      out[k] = v;
    }
  });
  return out;
}

/// Redact header maps. `Authorization`, `Cookie`, `X-Txn-Token`, etc. are
/// dropped to `***`.
Map<String, Object?> redactHeaders(Map<String, Object?> headers) {
  final out = <String, Object?>{};
  headers.forEach((k, v) {
    final lower = k.toLowerCase();
    if (_sensitiveHeaders.contains(lower)) {
      out[k] = '***';
    } else {
      out[k] = v;
    }
  });
  return out;
}

const Set<String> _piiKeys = {
  'passcode',
  'current_passcode',
  'code',
  'otp',
  'pin',
  'password',
  'refresh_token',
  'access_token',
  'txn_token',
  'idempotency_key',
  'secret',
};

const Set<String> _phoneKeys = {
  'phone',
  'msisdn',
  'recipient_phone',
  'payer_msisdn',
  'payee_msisdn',
  'from_phone',
};

const Set<String> _tokenKeys = {
  'token',
  'bearer',
  'jwt',
};

const Set<String> _sensitiveHeaders = {
  'authorization',
  'cookie',
  'set-cookie',
  'x-txn-token',
  'idempotency-key',
};
