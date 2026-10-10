import 'package:flutter/foundation.dart';

/// Data-transfer objects for the `POST /v1/transfers` endpoint.
///
/// Mirrors the OpenAPI schemas `TransferRequest` and `Transfer`
/// (see `docs/backend/openapi.yaml` §components/schemas, lines
/// 1542–1619). Hand-rolled `fromJson`/`toJson` to stay consistent
/// with the rest of the codebase, which has not adopted
/// `freezed`/`json_serializable` yet.
///
/// ## Money & phone shape
///
/// - `Money` is a decimal string with up to 6 dp, validated server-
///   side by the regex `^[0-9]+(\.[0-9]{1,6})?$`. The DTO keeps it
///   as a `String` so we never inherit float-rounding drift. Display
///   layers format; this layer transports.
/// - `Phone` is E.164 (`+ccc...`), validated server-side. Callers
///   are responsible for E.164-formatting before constructing
///   [TransferRequest]; this DTO does no normalization.
///
/// ## Why not enums for failure_reason
///
/// The OpenAPI enum is fixed (`INSUFFICIENT_FUNDS`,
/// `COMPLIANCE_BLOCK`, `SERVICE_UNAVAILABLE`,
/// `PROVIDER_REJECTED`, `QUOTE_EXPIRED`, `VELOCITY_LIMIT`), but
/// adding a new value server-side mustn't crash older clients.
/// [TransferFailureReason.fromWire] maps unknown values to
/// [TransferFailureReason.unknown] so deserialization is
/// future-proof. Same logic applies to [TransferStatus] /
/// [TransferKind] / [ClaimStatus].

// ---------------------------------------------------------------------------
// Request
// ---------------------------------------------------------------------------

/// Body of `POST /v1/transfers`.
///
/// `recipient_phone` must already be E.164 — callers compose this
/// from `(country, nationalPhone)` via the same code path used in
/// `Favorite.e164`. `amount` is the gross amount in `currency` (the
/// sender's balance currency, ISO 4217; string, ≤6 dp). The contract is
/// fiat-only: no settlement-asset amounts or chain details ever cross
/// this boundary (docs/backend/stellar-mvp-plan.md §1.1). `note` is
/// optional, 140 chars max.
/// `save_recipient` defaults to `false`; when `true` the server
/// adds the recipient to the user's saved-recipients list in the
/// same transaction.
@immutable
class TransferRequest {
  const TransferRequest({
    required this.recipientPhone,
    required this.amount,
    required this.currency,
    this.note,
    this.saveRecipient = false,
  });

  final String recipientPhone;
  final String amount;
  final String currency;
  final String? note;
  final bool saveRecipient;

  Map<String, Object?> toJson() => {
        'recipient_phone': recipientPhone,
        'amount': amount,
        'currency': currency,
        if (note != null) 'note': note,
        if (saveRecipient) 'save_recipient': true,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferRequest &&
          other.recipientPhone == recipientPhone &&
          other.amount == amount &&
          other.currency == currency &&
          other.note == note &&
          other.saveRecipient == saveRecipient;

  @override
  int get hashCode =>
      Object.hash(recipientPhone, amount, currency, note, saveRecipient);

  @override
  String toString() =>
      'TransferRequest(recipient_phone=$recipientPhone, '
      'amount=$amount, currency=$currency, '
      'note=${note == null ? "null" : "<${note!.length} chars>"}, '
      'save_recipient=$saveRecipient)';
}

// ---------------------------------------------------------------------------
// Response
// ---------------------------------------------------------------------------

/// Response body returned by `POST /v1/transfers` (`202 Accepted`).
///
/// Status semantics — wire to terminal screens:
/// - `COMPLETED` → `PaymentSuccessScreen` (settled).
/// - `PROCESSING` → `PaymentPendingScreen` (settling).
/// - `AWAITING_CLAIM` → `PaymentPendingScreen` (recipient is off-
///   network; an escrow + SMS claim link was issued — see [claim]).
/// - `FAILED` → `PaymentFailedScreen` (use [failureReason]).
/// - `EXPIRED_REFUNDED` / `CANCELLED` → terminal; reached via
///   transaction history, not the create path.
@immutable
class Transfer {
  const Transfer({
    required this.id,
    required this.kind,
    required this.status,
    required this.amount,
    required this.fee,
    required this.currency,
    required this.createdAt,
    this.sender,
    this.recipient,
    this.note,
    this.failureReason,
    this.completedAt,
    this.claim,
  });

  final String id;
  final TransferKind kind;
  final TransferStatus status;
  final String amount;
  final String fee;
  final String currency;
  final DateTime createdAt;

  final TransferParty? sender;
  final TransferParty? recipient;
  final String? note;
  final TransferFailureReason? failureReason;
  final DateTime? completedAt;
  final ClaimSummary? claim;

  factory Transfer.fromJson(Map<String, Object?> json) {
    return Transfer(
      id: json['id']! as String,
      kind: TransferKind.fromWire(json['kind'] as String?),
      status: TransferStatus.fromWire(json['status'] as String?),
      amount: json['amount']! as String,
      fee: json['fee']! as String,
      currency: json['currency']! as String,
      createdAt: DateTime.parse(json['created_at']! as String),
      sender: _parseParty(json['sender']),
      recipient: _parseParty(json['recipient']),
      note: json['note'] as String?,
      failureReason:
          TransferFailureReason.fromWire(json['failure_reason'] as String?),
      completedAt: _parseDate(json['completed_at']),
      claim: _parseClaim(json['claim']),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.wire,
        'status': status.wire,
        'amount': amount,
        'fee': fee,
        'currency': currency,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (sender != null) 'sender': sender!.toJson(),
        if (recipient != null) 'recipient': recipient!.toJson(),
        if (note != null) 'note': note,
        if (failureReason != null) 'failure_reason': failureReason!.wire,
        if (completedAt != null)
          'completed_at': completedAt!.toUtc().toIso8601String(),
        if (claim != null) 'claim': claim!.toJson(),
      };

  static TransferParty? _parseParty(Object? raw) {
    if (raw is! Map) return null;
    return TransferParty.fromJson(raw.cast<String, Object?>());
  }

  static ClaimSummary? _parseClaim(Object? raw) {
    if (raw is! Map) return null;
    return ClaimSummary.fromJson(raw.cast<String, Object?>());
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transfer &&
          other.id == id &&
          other.kind == kind &&
          other.status == status &&
          other.amount == amount &&
          other.fee == fee &&
          other.currency == currency &&
          other.createdAt == createdAt &&
          other.sender == sender &&
          other.recipient == recipient &&
          other.note == note &&
          other.failureReason == failureReason &&
          other.completedAt == completedAt &&
          other.claim == claim;

  @override
  int get hashCode => Object.hashAll([
        id,
        kind,
        status,
        amount,
        fee,
        currency,
        createdAt,
        sender,
        recipient,
        note,
        failureReason,
        completedAt,
        claim,
      ]);

  @override
  String toString() => 'Transfer(id=$id, kind=$kind, status=$status, '
      'amount=$amount, fee=$fee, currency=$currency)';
}

@immutable
class TransferParty {
  const TransferParty({
    this.userId,
    required this.phone,
    this.displayName,
    this.photoUrl,
  });

  /// Server user id when the party is on-network; `null` for an
  /// off-network recipient (transfer goes to escrow + SMS claim).
  final String? userId;
  final String phone;
  final String? displayName;
  final String? photoUrl;

  factory TransferParty.fromJson(Map<String, Object?> json) => TransferParty(
        userId: json['user_id'] as String?,
        phone: json['phone']! as String,
        displayName: json['display_name'] as String?,
        photoUrl: json['photo_url'] as String?,
      );

  Map<String, Object?> toJson() => {
        if (userId != null) 'user_id': userId,
        'phone': phone,
        if (displayName != null) 'display_name': displayName,
        if (photoUrl != null) 'photo_url': photoUrl,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferParty &&
          other.userId == userId &&
          other.phone == phone &&
          other.displayName == displayName &&
          other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(userId, phone, displayName, photoUrl);
}

@immutable
class ClaimSummary {
  const ClaimSummary({
    required this.token,
    required this.status,
    required this.amount,
    required this.currency,
    required this.expiresAt,
    this.sender,
    this.note,
  });

  final String token;
  final ClaimStatus status;
  final String amount;
  final String currency;
  final DateTime expiresAt;
  final TransferParty? sender;
  final String? note;

  factory ClaimSummary.fromJson(Map<String, Object?> json) => ClaimSummary(
        token: json['token']! as String,
        status: ClaimStatus.fromWire(json['status'] as String?),
        amount: json['amount']! as String,
        currency: json['currency']! as String,
        expiresAt: DateTime.parse(json['expires_at']! as String),
        sender: Transfer._parseParty(json['sender']),
        note: json['note'] as String?,
      );

  Map<String, Object?> toJson() => {
        'token': token,
        'status': status.wire,
        'amount': amount,
        'currency': currency,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        if (sender != null) 'sender': sender!.toJson(),
        if (note != null) 'note': note,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClaimSummary &&
          other.token == token &&
          other.status == status &&
          other.amount == amount &&
          other.currency == currency &&
          other.expiresAt == expiresAt &&
          other.sender == sender &&
          other.note == note;

  @override
  int get hashCode =>
      Object.hash(token, status, amount, currency, expiresAt, sender, note);
}

// ---------------------------------------------------------------------------
// Enums (forward-compat: unknown wire values fall through to `unknown`)
// ---------------------------------------------------------------------------

enum TransferKind {
  sent('SENT'),
  received('RECEIVED'),
  onramp('ONRAMP'),
  offramp('OFFRAMP'),
  unknown('');

  const TransferKind(this.wire);
  final String wire;

  static TransferKind fromWire(String? raw) {
    if (raw == null) return TransferKind.unknown;
    for (final v in values) {
      if (v != TransferKind.unknown && v.wire == raw) return v;
    }
    return TransferKind.unknown;
  }
}

enum TransferStatus {
  processing('PROCESSING'),
  completed('COMPLETED'),
  failed('FAILED'),
  awaitingClaim('AWAITING_CLAIM'),
  expiredRefunded('EXPIRED_REFUNDED'),
  cancelled('CANCELLED'),
  unknown('');

  const TransferStatus(this.wire);
  final String wire;

  static TransferStatus fromWire(String? raw) {
    if (raw == null) return TransferStatus.unknown;
    for (final v in values) {
      if (v != TransferStatus.unknown && v.wire == raw) return v;
    }
    return TransferStatus.unknown;
  }

  /// `true` when the transfer is in a terminal-success or terminal-
  /// pending state that the create path should react to.
  bool get isSettledOk => this == TransferStatus.completed;

  /// `true` when the create response should route the user to the
  /// pending screen rather than success or failed.
  bool get isPendingLike =>
      this == TransferStatus.processing ||
      this == TransferStatus.awaitingClaim;
}

enum TransferFailureReason {
  insufficientFunds('INSUFFICIENT_FUNDS'),
  complianceBlock('COMPLIANCE_BLOCK'),
  serviceUnavailable('SERVICE_UNAVAILABLE'),
  providerRejected('PROVIDER_REJECTED'),
  quoteExpired('QUOTE_EXPIRED'),
  velocityLimit('VELOCITY_LIMIT'),
  unknown('');

  const TransferFailureReason(this.wire);
  final String wire;

  /// Returns `null` when [raw] is `null` so callers can distinguish
  /// "no failure" from "unknown failure code". Unrecognised non-
  /// null values map to [TransferFailureReason.unknown].
  static TransferFailureReason? fromWire(String? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v != TransferFailureReason.unknown && v.wire == raw) return v;
    }
    return TransferFailureReason.unknown;
  }
}

enum ClaimStatus {
  pending('PENDING'),
  redeemed('REDEEMED'),
  expired('EXPIRED'),
  cancelled('CANCELLED'),
  unknown('');

  const ClaimStatus(this.wire);
  final String wire;

  static ClaimStatus fromWire(String? raw) {
    if (raw == null) return ClaimStatus.unknown;
    for (final v in values) {
      if (v != ClaimStatus.unknown && v.wire == raw) return v;
    }
    return ClaimStatus.unknown;
  }
}
