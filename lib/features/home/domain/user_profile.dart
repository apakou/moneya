import '../../../core/session/auth_session.dart';

/// Lightweight user profile model used by the Profile / Edit-Profile
/// screens. Mock-era fields only; once the backend lands this becomes
/// a freezed `User` aggregate fetched via `usersMeProvider`.
class UserProfile {
  const UserProfile({
    required this.fullName,
    required this.phone,
    required this.email,
    required this.address,
    required this.dateOfBirth,
    required this.kycDocLabel,
    required this.phoneVerified,
    required this.emailVerified,
    required this.addressVerified,
    required this.dobVerified,
    required this.kycVerified,
  });

  final String fullName;
  final String phone;
  final String email;
  final String address;
  final String dateOfBirth;
  final String kycDocLabel;

  final bool phoneVerified;
  final bool emailVerified;
  final bool addressVerified;
  final bool dobVerified;
  final bool kycVerified;

  /// Profile from the signed-in session. Only what the server knows is filled in: the phone is verified
  /// (the one-time code proved it); email / address / date of birth are not collected yet, and the
  /// identity check is only "verified" once the account has moved past the first KYC tier.
  factory UserProfile.fromSession(AuthSession s) {
    final name = s.fullName?.trim();
    return UserProfile(
      fullName: (name == null || name.isEmpty) ? 'MoneyA' : name,
      phone: s.phone,
      email: '',
      address: '',
      dateOfBirth: '',
      kycDocLabel: '',
      phoneVerified: true,
      emailVerified: false,
      addressVerified: false,
      dobVerified: false,
      kycVerified: s.kycTier != KycTier.tier0,
    );
  }

  /// Two-letter initials for the avatar placeholder ("John Amoako" → "JA").
  String get initials {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  UserProfile copyWith({
    String? fullName,
    String? phone,
    String? email,
    String? address,
    String? dateOfBirth,
  }) {
    return UserProfile(
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      kycDocLabel: kycDocLabel,
      phoneVerified: phoneVerified,
      emailVerified: emailVerified,
      addressVerified: addressVerified,
      dobVerified: dobVerified,
      kycVerified: kycVerified,
    );
  }
}

/// Mock current user used until auth + backend lookup land.
const UserProfile kMockUser = UserProfile(
  fullName: 'John Amoako',
  phone: '(+233) 24 098 7631',
  email: 'test@gmail.com',
  address: '10 Jakarta Crescent, Accra Ghana',
  dateOfBirth: '10 April 2003',
  kycDocLabel: 'Ghana Card',
  phoneVerified: true,
  emailVerified: true,
  addressVerified: true,
  dobVerified: true,
  kycVerified: true,
);
