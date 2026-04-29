/// Notification kinds rendered in the notifications bottom-sheet.
///
/// Each kind drives its own icon + tinted disc in `_NotificationTile`.
/// When the backend lands, this enum should mirror the server-side
/// `notification_type` discriminator 1:1.
enum AppNotificationKind {
  /// Incoming money — green inbound arrow.
  moneyReceived,

  /// Outgoing money succeeded — purple outbound arrow.
  transferSent,

  /// Outgoing money failed — red error icon.
  transferFailed,

  /// KYC approved — green shield/check.
  kycApproved,

  /// Refer-and-earn / promotional content — purple gift icon.
  promo,

  /// Security alert (new device login, password change, etc.) — amber
  /// shield exclamation.
  securityAlert,
}

/// One row in the notifications sheet.
///
/// `id` is currently a deterministic mock string ("nf-001", …) — when
/// we wire the backend it will become the server's UUID and the model
/// should move to `freezed`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.when,
    required this.read,
  });

  final String id;
  final AppNotificationKind kind;
  final String title;
  final String body;
  final DateTime when;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        when: when,
        read: read ?? this.read,
      );
}
