import '../../../core/session/auth_session.dart';

/// `OtpRequestResponse` (openapi.yaml). The code itself never comes back.
class OtpRequested {
  const OtpRequested({required this.retryAfterSeconds, this.maskedDestination});

  final int retryAfterSeconds;
  final String? maskedDestination;

  factory OtpRequested.fromJson(Map<String, Object?> json) {
    final retry = json['retry_after_seconds'];
    if (retry is! int) {
      throw const FormatException('otp response missing retry_after_seconds');
    }
    return OtpRequested(
      retryAfterSeconds: retry,
      maskedDestination: json['masked_destination'] as String?,
    );
  }
}

/// Result of a successful OTP verification: the new [session] plus whether the
/// user already has a passcode (`AuthTokens.passcode_set`) — a first login must
/// create one, a returning user must not be asked to "set" it again.
class LoginResult {
  const LoginResult({required this.session, required this.passcodeSet});

  final AuthSession session;
  final bool passcodeSet;

  /// Parses `AuthTokens`. [now] is injectable for deterministic tests.
  factory LoginResult.fromJson(Map<String, Object?> json, {DateTime? now}) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final expiresIn = json['expires_in'];
    final user = json['user'];
    final passcodeSet = json['passcode_set'];
    if (access is! String ||
        refresh is! String ||
        expiresIn is! int ||
        user is! Map ||
        passcodeSet is! bool) {
      throw const FormatException('auth tokens response is malformed');
    }
    return LoginResult(
      passcodeSet: passcodeSet,
      session: AuthSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: (now ?? DateTime.now()).add(Duration(seconds: expiresIn)),
        userId: user['id']! as String,
        phone: user['phone']! as String,
        countryIso2: user['country']! as String,
        kycTier: KycTier.fromWire(user['kyc_tier']! as String),
        fullName: user['full_name'] as String?,
        photoUrl: user['photo_url'] as String?,
      ),
    );
  }
}
