---
name: fintech-security
description: Security patterns for MoneyA — passcode handling, biometric authentication (local_auth), flutter_secure_storage usage, idempotency keys, FX quote locking, AML red flags, PII redaction in logs, certificate pinning, and root/jailbreak detection. USE WHEN the user mentions passcode, PIN, biometric, fingerprint, Face ID, secure storage, encryption, idempotency, AML, fraud, logging, TLS, certificate pinning, root detection, or any "is this safe" question. DO NOT USE FOR on-chain key management (see usdc-stablecoin-ops custody section).
---

# Fintech Security Patterns

## Passcode

- 6 digits minimum; block common patterns (`123456`, `000000`, birthdate-shaped, ascending/descending).
- Hash client-side with Argon2id (`cryptography` or `argon2` package) before sending — server never sees raw passcode.
  - Params: memoryCost=64MB, timeCost=3, parallelism=1 (adjust on low-end devices).
- Salt = server-provided, user-scoped, stored with user record.
- **Rate limit**: 5 attempts → 1min lockout, 10 → 15min, 15 → account frozen pending support.
- Rotate passcode every 365d or on suspicious activity.

## Biometrics (`local_auth`)

```dart
final auth = LocalAuthentication();
final canCheck = await auth.canCheckBiometrics && await auth.isDeviceSupported();
final available = await auth.getAvailableBiometrics();
final ok = await auth.authenticate(
  localizedReason: 'Confirm transfer',
  options: const AuthenticationOptions(
    biometricOnly: true,        // critical: don't accept device PIN as fallback
    stickyAuth: true,
    sensitiveTransaction: true,
  ),
);
```

Rules:
- Biometric unlocks an **encryption key stored in Android Keystore / iOS Keychain**, which decrypts a short-lived session token.
- Biometric ALONE is never sufficient for transfers above a user-configurable threshold → always require passcode for large amounts.
- On biometric enrollment change (new fingerprint added), invalidate the stored key and re-prompt for passcode.
- iOS: check `BiometricType.face` vs `.fingerprint` to show the right icon.

## Secure storage

Use `flutter_secure_storage` for:
- Session token (short-lived, ≤ 1h)
- Refresh token (rotating)
- Passcode-derived encryption key (never the passcode itself)
- User preferences that leak PII if observed

```dart
const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);
```

NEVER store in `SharedPreferences`: tokens, phone numbers, balance, transaction details.

## Idempotency

Every mutating request gets an `Idempotency-Key: <uuid-v4>` header generated client-side BEFORE the user confirms. The same key is sent on every retry within 24h. Backend returns the same response for the same key.

```
POST /transfers
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

Generate the key when the user opens the confirmation screen, not at swipe — so that accidental double-swipes collapse to one transfer.

## FX quote locking

```
1. GET /fx/quote?from=XOF&to=NGN&amount=10000
   → { quote_id, rate, expires_at (now+30s), fee_minor }
2. [User reviews, may take time]
3. POST /transfers { quote_id, idempotency_key, ... }
   → If quote expired: 409 QUOTE_EXPIRED → client re-quotes and re-shows
```

Quote is bound to (corridor, amount, user_id). Not transferable.

## Request signing

For sensitive endpoints (transfer, offramp), client signs the request body with HMAC using a per-device secret provisioned at app install:

```
X-Device-Id: <uuid>
X-Signature: HMAC-SHA256(device_secret, timestamp + method + path + sha256(body))
X-Timestamp: <unix-seconds>
```

Server rejects `abs(now - timestamp) > 120s`. Prevents replay from a compromised network.

## Certificate pinning

Pin the backend API cert using `dio_certificate_pinning` or `http_certificate_pinning`. Pin BOTH:
- Current leaf cert SHA-256
- Next rotation cert SHA-256 (backup)

Rotate pins via a remote config channel that is itself pinned. Monitor for pin-failure spikes — indicates MITM attempt OR impending cert expiry.

## Root / jailbreak detection

Use `flutter_jailbreak_detection`. Policy:
- **Detection ≠ block**. Many legitimate African users root for battery mods.
- On detection: require additional KYC step + cap daily transfer limit by 50%.
- Log for fraud analytics.

## Logging — PII redaction

Mandatory redaction for all log levels shipping to backend (Sentry, Datadog):

| Field | Treatment |
|---|---|
| Phone number | Mask middle: `+221**1234567` |
| Amount | Log order of magnitude only: `~10000 XOF` |
| Recipient name | `[REDACTED_NAME]` |
| Passcode | Never log, even hashed |
| OTP | Never log |
| Bearer / refresh tokens | `Bearer ey***` |
| Full names in errors | Replace with user_id |

Implement a `SafeLogger` wrapper; make direct `print`/`log` a lint error via `avoid_print`.

## AML red flags (client-side signals to send to backend)

Client collects, backend decides:
- Device changed within 24h of high-value transfer
- New recipient, amount > $200 equivalent, first transfer of the day
- Copy-pasted recipient phone (vs contact picked)
- Voice confidence < 0.7 but user still confirmed
- Multiple cancelled transfers in short window
- User location country differs from account country

## Screen security

- `FLAG_SECURE` on Android for all screens showing balance, passcode, transfer details — prevents screenshots AND prevents app appearing in recent-apps preview.
- iOS: swap to a blank/logo overlay on `applicationWillResignActive`.
- Disable accessibility overlays (`AccessibilityManager`) on passcode entry — prevents malicious keyboards/overlays.

## Dependency hygiene

- `flutter pub outdated` in CI weekly.
- Run `validate_cves` (or equivalent) on pubspec.lock before each release.
- Pin exact versions for crypto/auth packages; use carets for UI packages.

## Release hardening

- Strip Dart symbols in release builds (`--obfuscate --split-debug-info=...`).
- Disable Flutter DevTools in release.
- Android: enable R8 minification + resource shrinking.
- iOS: enable Bitcode replacement (App Store signing).
- Ship debug symbols to Sentry privately for crash symbolication.
