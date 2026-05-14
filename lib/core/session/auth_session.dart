import 'dart:convert';

/// KYC tier mirroring `openapi.yaml#KycTier`.
enum KycTier {
  tier0('TIER_0'),
  tier1('TIER_1'),
  tier2('TIER_2');

  const KycTier(this.wire);
  final String wire;

  static KycTier fromWire(String value) {
    return KycTier.values.firstWhere(
      (t) => t.wire == value,
      orElse: () => KycTier.tier0,
    );
  }
}

/// Immutable session record persisted to secure storage under
/// [SecureStorageKeys.session].
///
/// `deviceId` is **not** stored here — it lives under a separate key so it
/// survives logout. See `SessionStore` for the persistence boundary.
///
/// Equality is intentionally based on all fields so tests can assert
/// round-trip identity.
class AuthSession {
  AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.phone,
    required this.countryIso2,
    required this.kycTier,
    this.fullName,
    this.photoUrl,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String phone;
  final String countryIso2;
  final KycTier kycTier;
  final String? fullName;
  final String? photoUrl;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool isNearExpiry({Duration window = const Duration(seconds: 60)}) =>
      DateTime.now().add(window).isAfter(expiresAt);

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? userId,
    String? phone,
    String? countryIso2,
    KycTier? kycTier,
    String? fullName,
    String? photoUrl,
  }) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      userId: userId ?? this.userId,
      phone: phone ?? this.phone,
      countryIso2: countryIso2 ?? this.countryIso2,
      kycTier: kycTier ?? this.kycTier,
      fullName: fullName ?? this.fullName,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'user_id': userId,
        'phone': phone,
        'country_iso2': countryIso2,
        'kyc_tier': kycTier.wire,
        if (fullName != null) 'full_name': fullName,
        if (photoUrl != null) 'photo_url': photoUrl,
      };

  String encode() => jsonEncode(toJson());

  static AuthSession decode(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return AuthSession.fromJson(json);
  }

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      accessToken: json['access_token']! as String,
      refreshToken: json['refresh_token']! as String,
      expiresAt: DateTime.parse(json['expires_at']! as String),
      userId: json['user_id']! as String,
      phone: json['phone']! as String,
      countryIso2: json['country_iso2']! as String,
      kycTier: KycTier.fromWire(json['kyc_tier']! as String),
      fullName: json['full_name'] as String?,
      photoUrl: json['photo_url'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthSession &&
        other.accessToken == accessToken &&
        other.refreshToken == refreshToken &&
        other.expiresAt == expiresAt &&
        other.userId == userId &&
        other.phone == phone &&
        other.countryIso2 == countryIso2 &&
        other.kycTier == kycTier &&
        other.fullName == fullName &&
        other.photoUrl == photoUrl;
  }

  @override
  int get hashCode => Object.hash(
        accessToken,
        refreshToken,
        expiresAt,
        userId,
        phone,
        countryIso2,
        kycTier,
        fullName,
        photoUrl,
      );

  @override
  String toString() =>
      'AuthSession(userId=$userId, kycTier=$kycTier, expiresAt=$expiresAt)';
}
