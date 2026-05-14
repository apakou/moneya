import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/session/auth_session.dart';

void main() {
  group('KycTier', () {
    test('round-trips known wire values', () {
      expect(KycTier.fromWire('TIER_0'), KycTier.tier0);
      expect(KycTier.fromWire('TIER_1'), KycTier.tier1);
      expect(KycTier.fromWire('TIER_2'), KycTier.tier2);
    });

    test('falls back to tier0 on unknown wire', () {
      expect(KycTier.fromWire('TIER_99'), KycTier.tier0);
      expect(KycTier.fromWire(''), KycTier.tier0);
    });
  });

  group('AuthSession', () {
    final base = AuthSession(
      accessToken: 'access-abc',
      refreshToken: 'refresh-xyz',
      expiresAt: DateTime.utc(2026, 5, 14, 12, 0, 0),
      userId: 'user-1',
      phone: '+221770000000',
      countryIso2: 'SN',
      kycTier: KycTier.tier1,
      fullName: 'Aminata Diallo',
    );

    test('encode → decode is identity', () {
      final decoded = AuthSession.decode(base.encode());
      expect(decoded, equals(base));
    });

    test('omits null optional fields from JSON', () {
      final minimal = AuthSession(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.utc(2026, 1, 1),
        userId: 'u',
        phone: '+221770000000',
        countryIso2: 'SN',
        kycTier: KycTier.tier0,
      );
      final json = minimal.toJson();
      expect(json.containsKey('full_name'), isFalse);
      expect(json.containsKey('photo_url'), isFalse);
    });

    test('isExpired reflects clock', () {
      final past = base.copyWith(
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final future = base.copyWith(
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(past.isExpired, isTrue);
      expect(future.isExpired, isFalse);
    });

    test('isNearExpiry uses the supplied window', () {
      final soon = base.copyWith(
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );
      expect(soon.isNearExpiry(window: const Duration(seconds: 60)), isTrue);
      expect(soon.isNearExpiry(window: const Duration(seconds: 10)), isFalse);
    });

    test('copyWith preserves fields not overridden', () {
      final next = base.copyWith(accessToken: 'new-access');
      expect(next.accessToken, 'new-access');
      expect(next.refreshToken, base.refreshToken);
      expect(next.userId, base.userId);
      expect(next.kycTier, base.kycTier);
    });

    test('value equality across distinct instances', () {
      final twin = AuthSession.fromJson(base.toJson());
      expect(twin, equals(base));
      expect(twin.hashCode, base.hashCode);
    });
  });
}
