import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/features/transfer/data/transfer_dtos.dart';

/// Golden JSON round-trip tests for the `/v1/transfers` DTOs.
///
/// Each `fromJson → toJson` round-trip asserts that:
/// 1. Every required field survives.
/// 2. Nullable fields are omitted from `toJson()` when null, so we
///    don't pollute the wire with `"failure_reason": null` etc. — the
///    server-side OpenAPI uses presence as the signal for "no value".
/// 3. Unknown wire enum values map to `.unknown` rather than throwing,
///    so a backend rollout that adds a new status code can't crash
///    deployed clients. This is the forward-compat contract recorded
///    in `transfer_dtos.dart` class docs.
void main() {
  group('TransferRequest', () {
    test('toJson omits null note + saveRecipient false default', () {
      const req = TransferRequest(
        recipientPhone: '+221770000099',
        amountUsdc: '10',
      );
      expect(req.toJson(), {
        'recipient_phone': '+221770000099',
        'amount_usdc': '10',
      });
    });

    test('toJson includes note and save_recipient=true when set', () {
      const req = TransferRequest(
        recipientPhone: '+221770000099',
        amountUsdc: '25.50',
        note: 'lunch',
        saveRecipient: true,
      );
      expect(req.toJson(), {
        'recipient_phone': '+221770000099',
        'amount_usdc': '25.50',
        'note': 'lunch',
        'save_recipient': true,
      });
    });
  });

  group('Transfer.fromJson minimal', () {
    test('only required fields → optional fields null', () {
      final json = jsonDecode('''
        {
          "id": "00000000-0000-4000-8000-000000000001",
          "kind": "SENT",
          "status": "COMPLETED",
          "amount_usdc": "10",
          "fee_usdc": "0.10",
          "created_at": "2026-05-15T10:00:00Z"
        }
      ''') as Map<String, Object?>;

      final t = Transfer.fromJson(json);

      expect(t.id, '00000000-0000-4000-8000-000000000001');
      expect(t.kind, TransferKind.sent);
      expect(t.status, TransferStatus.completed);
      expect(t.amountUsdc, '10');
      expect(t.feeUsdc, '0.10');
      expect(t.createdAt.toUtc().toIso8601String(), '2026-05-15T10:00:00.000Z');
      expect(t.sender, isNull);
      expect(t.recipient, isNull);
      expect(t.note, isNull);
      expect(t.solanaSignature, isNull);
      expect(t.failureReason, isNull);
      expect(t.completedAt, isNull);
      expect(t.claim, isNull);
    });

    test('toJson on minimal Transfer does not include null keys', () {
      final t = Transfer(
        id: 'abc',
        kind: TransferKind.sent,
        status: TransferStatus.completed,
        amountUsdc: '10',
        feeUsdc: '0',
        createdAt: DateTime.utc(2026, 5, 15, 10),
      );
      final out = t.toJson();
      expect(out.containsKey('failure_reason'), isFalse);
      expect(out.containsKey('claim'), isFalse);
      expect(out.containsKey('completed_at'), isFalse);
      expect(out.containsKey('sender'), isFalse);
      expect(out.containsKey('recipient'), isFalse);
    });
  });

  group('Transfer.fromJson full', () {
    test('FAILED with failure_reason, sender, recipient, completed_at', () {
      final json = jsonDecode('''
        {
          "id": "tid-1",
          "kind": "SENT",
          "status": "FAILED",
          "amount_usdc": "10",
          "fee_usdc": "0.10",
          "created_at": "2026-05-15T10:00:00Z",
          "completed_at": "2026-05-15T10:00:05Z",
          "failure_reason": "INSUFFICIENT_FUNDS",
          "note": "lunch",
          "solana_signature": "sig-1",
          "sender": {"user_id": "u-1", "phone": "+221770000000"},
          "recipient": {"phone": "+221770000099", "display_name": "Awa"}
        }
      ''') as Map<String, Object?>;

      final t = Transfer.fromJson(json);

      expect(t.status, TransferStatus.failed);
      expect(t.failureReason, TransferFailureReason.insufficientFunds);
      expect(t.completedAt, isNotNull);
      expect(t.sender?.userId, 'u-1');
      expect(t.recipient?.displayName, 'Awa');
      expect(t.note, 'lunch');
      expect(t.solanaSignature, 'sig-1');
    });

    test('AWAITING_CLAIM with embedded ClaimSummary', () {
      final json = jsonDecode('''
        {
          "id": "tid-2",
          "kind": "SENT",
          "status": "AWAITING_CLAIM",
          "amount_usdc": "10",
          "fee_usdc": "0.10",
          "created_at": "2026-05-15T10:00:00Z",
          "claim": {
            "token": "clm-tok-1",
            "status": "PENDING",
            "amount_usdc": "10",
            "expires_at": "2026-05-22T10:00:00Z"
          }
        }
      ''') as Map<String, Object?>;

      final t = Transfer.fromJson(json);

      expect(t.status, TransferStatus.awaitingClaim);
      expect(t.claim, isNotNull);
      expect(t.claim!.token, 'clm-tok-1');
      expect(t.claim!.status, ClaimStatus.pending);
    });

    test('round-trip: fromJson → toJson → fromJson preserves equality', () {
      final original = jsonDecode('''
        {
          "id": "tid-3",
          "kind": "RECEIVED",
          "status": "COMPLETED",
          "amount_usdc": "5.25",
          "fee_usdc": "0.05",
          "created_at": "2026-05-15T10:00:00.000Z",
          "completed_at": "2026-05-15T10:00:02.000Z",
          "sender": {"phone": "+221770000000"}
        }
      ''') as Map<String, Object?>;

      final t1 = Transfer.fromJson(original);
      final t2 = Transfer.fromJson(t1.toJson());

      expect(t2, equals(t1));
    });
  });

  group('forward-compat enum mapping', () {
    test('unknown TransferStatus wire value → TransferStatus.unknown', () {
      final json = {
        'id': 'x',
        'kind': 'SENT',
        'status': 'TIME_TRAVELLED',
        'amount_usdc': '1',
        'fee_usdc': '0',
        'created_at': '2026-05-15T10:00:00Z',
      };
      final t = Transfer.fromJson(json);
      expect(t.status, TransferStatus.unknown);
    });

    test('unknown failure_reason → TransferFailureReason.unknown '
        '(not null — null means no failure)', () {
      final json = {
        'id': 'x',
        'kind': 'SENT',
        'status': 'FAILED',
        'amount_usdc': '1',
        'fee_usdc': '0',
        'created_at': '2026-05-15T10:00:00Z',
        'failure_reason': 'ASTEROID_IMPACT',
      };
      final t = Transfer.fromJson(json);
      expect(t.failureReason, TransferFailureReason.unknown);
    });

    test('absent failure_reason → null (no failure)', () {
      final json = {
        'id': 'x',
        'kind': 'SENT',
        'status': 'COMPLETED',
        'amount_usdc': '1',
        'fee_usdc': '0',
        'created_at': '2026-05-15T10:00:00Z',
      };
      final t = Transfer.fromJson(json);
      expect(t.failureReason, isNull);
    });
  });
}
