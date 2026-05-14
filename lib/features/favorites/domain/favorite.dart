import 'package:flutter/foundation.dart';

import '../../auth/domain/supported_country.dart';

/// A saved recipient the user has sent money to before.
///
/// ## Identity
///
/// Identity is the pair `(country, nationalPhone)`. Two favourites
/// are considered the same person iff their country *and* national
/// digits match — provider (Wave vs Orange vs MTN) is **not** part
/// of identity because the same person can collect funds on more
/// than one wallet attached to the same MSISDN. The displayed name
/// is mutable metadata; replacing a favourite (re-adding under a
/// different name) updates the name in place.
///
/// ## Why not E.164 as the sole key
///
/// The recipient screens across the app pass `(country,
/// nationalPhone)` rather than a normalized E.164 string —
/// `phone_numbers_parser` strips the leading `0` lazily at format
/// time, and the local digits are what the keypad echoes back to
/// the user. Keying on E.164 would force a conversion at every
/// touchpoint; keying on the pair the rest of the app already
/// uses keeps the seams aligned. The [e164] getter is provided
/// for serialization / logging once we land a backend.
///
/// ## Why this isn't `freezed`
///
/// The project hasn't adopted `freezed` yet (see
/// `transfer_recipient_prefill.dart` for the same hand-rolled
/// pattern). When we introduce code-gen across the codebase,
/// migrate this class in the same sweep — no behavior change.
@immutable
class Favorite {
  const Favorite({
    required this.country,
    required this.nationalPhone,
    required this.displayName,
    required this.addedAt,
  });

  /// Origin country of the recipient. Used both for the dial code
  /// (when building E.164) and for the country chip when the
  /// favourite is tapped to prefill the Transfer screen.
  final SupportedCountry country;

  /// National-significant digits only. Leading `0` is preserved (it
  /// is stripped by `phone_numbers_parser` when the country is set),
  /// no dial code, no spaces. Matches the convention used by
  /// `TransferRecipientPrefill.nationalPhone`, the home favourites
  /// strip, and the transfer screen's recipient phone controller.
  final String nationalPhone;

  /// User-facing name. Either typed by the user on the transfer
  /// screen or — preferred — the canonical name returned by
  /// [RecipientLookupService] when the directory found a match.
  final String displayName;

  /// Wall-clock time the favourite was first added. Used to sort
  /// the list newest-first (so the most-recently-added favourite
  /// is visible at the top of the Profile > Favourites screen and
  /// in the leftmost slot of the home strip).
  final DateTime addedAt;

  /// E.164 representation of [country] + [nationalPhone] (with the
  /// leading `+` per spec, dial code prefixed, leading national `0`
  /// stripped). Provided as a stable key for backend persistence +
  /// analytics once those exist.
  String get e164 {
    final national = nationalPhone.startsWith('0')
        ? nationalPhone.substring(1)
        : nationalPhone;
    return '+${country.dialCode}$national';
  }

  /// Identity tuple. Use as the equality / map key everywhere
  /// instead of `==` if you need to ignore [displayName] /
  /// [addedAt] (e.g. "is this person already favourited?" —
  /// see [FavoritesService.contains]).
  String get identityKey => '${country.isoCode}|$nationalPhone';

  /// Returns a copy with selected fields replaced. Used by the
  /// service when the user re-adds the same `(country, phone)`
  /// pair with a different display name — we keep the original
  /// [addedAt] for stable ordering.
  Favorite copyWith({
    SupportedCountry? country,
    String? nationalPhone,
    String? displayName,
    DateTime? addedAt,
  }) {
    return Favorite(
      country: country ?? this.country,
      nationalPhone: nationalPhone ?? this.nationalPhone,
      displayName: displayName ?? this.displayName,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Favorite &&
        other.country == country &&
        other.nationalPhone == nationalPhone &&
        other.displayName == displayName &&
        other.addedAt == addedAt;
  }

  @override
  int get hashCode => Object.hash(country, nationalPhone, displayName, addedAt);

  @override
  String toString() =>
      'Favorite(${country.isoCode}, $nationalPhone, "$displayName")';
}
