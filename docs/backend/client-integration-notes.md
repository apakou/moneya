# MoneyA — Client Integration Notes (Flutter)

**Status:** Living document. Source of truth for *how the Flutter client wires up to the existing OpenAPI contract*.
**Audience:** Flutter engineers implementing W1–W3.
**Scope:** Maps `docs/backend/openapi.yaml` operations to Flutter call sites, surfaces deltas, and locks integration decisions.

---

## 0. Source of truth

The API contract is **`docs/backend/openapi.yaml`** (OpenAPI 3.1). This file does **not** restate the contract. It records:

1. Which OpenAPI operation each Flutter screen / repository calls.
2. Client-side conventions for headers, sessions, step-up, idempotency, errors.
3. Deltas where the existing backend docs and the agreed client architecture disagree.
4. Open questions awaiting backend confirmation.

If the OpenAPI spec changes, this file is updated in the same PR.

---

## 1. Client architecture deltas

The backend `architecture.md` (line 82) assumes the Flutter client uses **Riverpod 2 + dio**. The agreed direction is **all-in GetX**:

| Concern | architecture.md | This client |
|---|---|---|
| State mgmt | Riverpod 2 | **GetX 4.x** (`GetxService` for singletons, `GetxController` per feature) |
| HTTP | dio | **dio 5.x** (unchanged) |
| Navigation | (unspecified) | `Get.to/back/offAll` everywhere (no `Navigator.pop`) |
| DI | (unspecified) | `Get.put`/`Get.find` (no `get_it`/`riverpod`) |

No Riverpod dependency or `// TODO(riverpod)` markers remain in the
codebase. If a code reviewer suggests reintroducing `flutter_riverpod` /
`riverpod_annotation` / `riverpod_generator`, push back: state management
is GetX everywhere, by decision recorded in this row.

---

## 2. Required request headers (every call)

| Header | When | Source (client) |
|---|---|---|
| `Authorization: Bearer <access_token>` | All authed endpoints | `SessionController.currentAccessToken` |
| `Idempotency-Key: <uuid v4>` | Every state-mutating money endpoint | `IdempotencyInterceptor` auto-generates per request when `Options.extra['idempotent'] == true` |
| `X-Txn-Token: <step-up token>` | Every money-moving endpoint | `StepUpController.fresh()` (see §5) |
| `traceparent: <W3C>` | All calls | `TraceInterceptor` (generate per request; PostHog session id woven in) |
| `Accept-Language: fr` \| `en` | All calls | Sourced from `LocaleController.current.languageCode` |
| `X-Device-Id: <uuid>` | All calls | `SessionController.deviceId` (persisted in secure storage; generated on first launch) |
| `X-App-Version: <semver>` | All calls | `package_info_plus` |
| `X-Platform: ios` \| `android` | All calls | `Platform.operatingSystem` |

Interceptor order (top of chain runs first on request, last on response):

```
LoggingInterceptor          # PII-redacted request/response logs
└─ AuthInterceptor          # adds Authorization; refreshes on 401
   └─ IdempotencyInterceptor # adds Idempotency-Key when flagged
      └─ TraceInterceptor    # adds traceparent + X-Device-Id + X-App-Version + X-Platform + Accept-Language
         └─ ErrorMappingInterceptor # DioException → ApiError subclasses
```

`X-Txn-Token` is **not** auto-attached by an interceptor. Call sites obtain it explicitly via `StepUpController` (§5) and pass it in `Options.extra['txnToken']`, which `AuthInterceptor` reads and attaches.

---

## 3. Session model

```
AuthSession {
  accessToken: String           // RS256 JWT, 15-min TTL
  refreshToken: String          // rotating; replaced on every /v1/auth/refresh
  expiresAt: DateTime           // accessToken expiry (now + expires_in)
  userId: String                // uuid
  phone: String                 // E.164
  countryIso2: String           // 'SN', 'CI', ...
  kycTier: KycTier              // TIER_0 | TIER_1 | TIER_2
  deviceId: String              // uuid, persisted across logouts
  fullName: String?
  photoUrl: String?
}
```

Persisted as JSON in `flutter_secure_storage` under key `session.v1`. `deviceId` is persisted **separately** under `device.id` so it survives logout (a logged-out device is still the same device).

### Lifecycle
- **Cold start:** `SessionController.bootstrap()` runs before `runApp` via `Get.putAsync`. Reads `session.v1` and `device.id`. If `session.v1` is missing, mints a new `deviceId` (if absent) and leaves session null. If present but `expiresAt < now + 60s`, attempts a single refresh.
- **Refresh:** Single-flight (mutex via `Completer`). On 401 from any endpoint, `AuthInterceptor` calls `/v1/auth/refresh`. On refresh failure (401 again or network), clears session, navigates to `AuthLanding`.
- **Logout:** `SessionController.clear()` wipes `session.v1` only. Calls `DELETE /v1/devices/{id}` best-effort. Keeps `device.id`.

---

## 4. Passcode

- **No client-side hashing.** Passcode (6 digits) is sent **plaintext over TLS** to `POST /v1/auth/passcode` and `POST /v1/auth/step-up`. Backend hashes server-side with Argon2id (per `openapi.yaml` line 180 and `architecture.md`).
- **No `argon2` Dart dep.**
- Passcode stays in memory only as long as the entry sheet is open; cleared on dispose. Never logged, never written to disk.
- Lockout (5 failed attempts) is **server-enforced** for 15 minutes; the backend answers `429` with `code: PASSCODE_LOCKED` / `OTP_LOCKED` and a `Retry-After` header; the client shows a localized "Try again in N minutes".

---

## 5. Step-up tokens (`X-Txn-Token`)

Every money-moving endpoint requires a fresh `X-Txn-Token` from `POST /v1/auth/step-up`.

### `StepUpController` (GetxService, singleton)

```
StepUpController extends GetxService {
  Future<String> fresh({Duration maxAge = const Duration(seconds: 50)})

  // Returns a token guaranteed to be valid for ~10s from now.
  //
  // 1. If a cached token exists and is < maxAge old, return it.
  // 2. Else: open TransactionPasscodeSheet (modal bottom sheet).
  //    - On submit, POST /v1/auth/step-up with the passcode.
  //    - Cache the returned token + expires_at.
  //    - Return the token.
  // 3. If the sheet is dismissed, throw StepUpCancelledException.
}
```

### Call-site pattern (in repositories)

```dart
final txnToken = await stepUp.fresh();
final resp = await api.post(
  '/v1/transfers',
  data: body,
  options: Options(extra: {
    'idempotent': true,
    'txnToken': txnToken,
  }),
);
```

### Endpoints that require step-up

- `POST /v1/transfers`
- `POST /v1/onramp/orders`
- `POST /v1/offramp/orders`
- `POST /v1/transfers/{id}/cancel` *(spec doesn't currently require it — see §11 open question Q3)*
- `POST /v1/payment-requests` *(spec doesn't currently require it — see §11 open question Q3)*
- `POST /v1/claims/{token}/redeem` *(spec doesn't currently require it — see §11)*

---

## 6. Idempotency

`IdempotencyInterceptor` auto-attaches `Idempotency-Key: <uuid v4>` when the caller sets `Options.extra['idempotent'] == true`. The key is generated **once per logical operation**, not per retry — callers that retry must reuse the same key:

```dart
final key = const Uuid().v4();
ApiResult<Transfer> attempt() => api.post(
  '/v1/transfers',
  data: body,
  options: Options(extra: {
    'idempotent': true,
    'idempotencyKey': key,        // explicit reuse on retry
    'txnToken': txnToken,
  }),
);
```

If `idempotencyKey` is provided, the interceptor uses it verbatim. If only `idempotent: true` is set, the interceptor mints one fresh UUID per request (suitable for one-shot calls; **not** suitable for retry-after-network-error).

Per spec: server stores `(user_id, route, key) → response` for 24h. Replays return the original status + body.

---

## 7. Error envelope

All errors are `application/problem+json` (RFC 7807). `ErrorMappingInterceptor` converts to:

```dart
sealed class ApiError implements Exception {
  String get code;       // machine-readable, e.g. 'WALLET_INSUFFICIENT_FUNDS'
  String get title;      // human-readable, server-localized
  String? get detail;
  String? get traceId;
}

class NetworkError extends ApiError {}      // no response (timeout, DNS, offline)
class AuthError extends ApiError {}         // 401, 423
class ValidationError extends ApiError {}   // 400, 422
class ConflictError extends ApiError {}     // 409, 410
class PaymentError extends ApiError {}      // 402, 403 (compliance)
class RateLimitError extends ApiError {}    // 429 (carries Retry-After seconds)
class ServerError extends ApiError {}       // 5xx
class UnknownError extends ApiError {}      // anything else
```

Callers receive `ApiResult<T> = Success<T> | Failure(ApiError)`. **No raw `DioException` ever crosses the network-layer boundary.** Repositories return `ApiResult`; controllers map to UI state.

### Stable error codes the client must recognise

| Code | Surface as |
|---|---|
| `OTP_INVALID` (401) | "Wrong code. Try again." (incorrect-code sheet) |
| `OTP_LOCKED` (429, `Retry-After`) | "Too many wrong codes. Try again in N min." |
| `RATE_LIMITED` (429, `Retry-After`) | "Too many requests. Try again in N min." |
| `SMS_UNAVAILABLE` (503) | "We could not send the code." |
| `UNAUTHORIZED` (401) | Bad/expired bearer → refresh once, then re-login. **The only 401 the client refreshes on.** |
| `REFRESH_INVALID` (401) | Force re-login (the refresh token was rotated away or reused) |
| `PASSCODE_INVALID` (401) | In-place retry in the passcode sheet. **Never auto-retried** (each try counts toward lockout) |
| `PASSCODE_LOCKED` (429, `Retry-After`) | Lockout message; pop the sheet |
| `PASSCODE_NOT_SET` (403) | Route to passcode creation |
| `PASSCODE_TOO_WEAK` (400) | "Choose a less predictable passcode." |
| `STEP_UP_REQUIRED` (401) / `TXN_TOKEN_CONSUMED` (409) | Run step-up again, then retry with the SAME Idempotency-Key |
| `IDEMPOTENCY_KEY_REQUIRED` (400) / `IDEMPOTENCY_KEY_REUSED` (422) | Client bug: mint one key per logical operation |
| `INSUFFICIENT_FUNDS` (402) | Block submit; show "Top up" CTA |
| `QUOTE_EXPIRED` (409) | Re-quote and show the new numbers; do **not** auto-retry the order |
| `AMOUNT_TOO_SMALL` / `UNSUPPORTED_CURRENCY` (400) | Inline amount error |
| `PROVIDER_UNAVAILABLE` (503) | "Payments are temporarily unavailable"; safe to retry the same key |
| `KYC_REQUIRED` | Route to KYC start (not implemented server-side yet) |
| `COMPLIANCE_BLOCK` | Generic block message (not implemented server-side yet) |
| `VELOCITY_LIMIT` | Show daily/weekly limit (not implemented server-side yet) |

This table is the backend's real behaviour as of the Stellar MVP (see `backend/apps/api/src/**`). The older `AUTH_*` / `WALLET_*` names from the first drafts are not sent.

---

## 8. Operation → call-site map

For every OpenAPI operation, the Flutter call site is named. "TBD" means W2/W3 will add it.

### Auth

| operationId | Caller | Notes |
|---|---|---|
| `requestOtp` | `AuthRepository.requestOtp(phone)` from `VerifyPhoneScreen` | Already wired to UI; currently mocked. |
| `verifyOtp` | `AuthRepository.verifyOtp(phone, code, deviceId)` from `VerifyPhoneScreen` | Returns `AuthTokens`. Client persists session, then routes by `kyc_tier`. |
| `refreshTokens` | `AuthInterceptor` on 401 only | Never called by UI directly. |
| `setPasscode` | `PasscodeScreen` (set + change flows) | Plaintext over TLS. |
| `stepUp` | `StepUpController.fresh()` | Sheet UI. |

### Users

| operationId | Caller |
|---|---|
| `getMe` | `SessionController.refreshProfile()` after login + on app resume |
| `updateMe` | TBD — Edit-Profile screen (W4, P2) |
| `deleteMe` | `ProfileScreen` → `_onDeleteAccount` (today a `debugPrint`) |

### KYC

| operationId | Caller |
|---|---|
| `getKycStatus` | `KycController` (post-submission polling fallback; primary path is WSS `kyc.*`) |
| `createKycSubmission` | `SelfieCaptureScreen` → `KycRepository.submit(...)` (W2) |

### Wallet

| operationId | Caller |
|---|---|
| `getWallet` | `WalletController` — on home enter, on resume, on transfer success, on currency switch. Server caches 30s; client also caches 30s before re-fetch. |

### Recipients

| operationId | Caller |
|---|---|
| `lookupRecipient` | Replaces `RecipientLookupService._knownDirectory` (W3) |
| `listSavedRecipients` | Server-side address book. Will back `FavoritesScreen` in W3. Until then `FavoritesService` (in-memory) stays. |
| `saveRecipient` | `AddToFavoritesCard` calls this in W3 alongside local `FavoritesService.add()`. |
| `deleteSavedRecipient` | `FavoritesScreen` swipe-dismiss in W3. |

### Onramp / Offramp

| operationId | Caller |
|---|---|
| `quoteOnramp` | `LoadMoneyController.quote()` |
| `createOnrampOrder` | `LoadMoneyController.submit()` (idempotent + step-up) |
| `getOnrampOrder` | Pending-state fallback when WSS missing |
| `quoteOfframp` | `WithdrawController.quote()` |
| `createOfframpOrder` | `WithdrawController.submit()` (idempotent + step-up) |
| `getOfframpOrder` | Pending-state fallback when WSS missing |

### Transfers

| operationId | Caller |
|---|---|
| `listTransfers` | `TransactionsController` — paged via Cursor. |
| `createTransfer` | `PaymentConfirmScreen._onConfirm` (idempotent + step-up) |
| `getTransfer` | `PaymentPendingScreen` polling fallback. Primary path: WSS `transfer.*`. |
| `cancelTransfer` | TBD — Unclaimed-transfer detail screen (W4) |

### PaymentRequests

| operationId | Caller |
|---|---|
| `listPaymentRequests` | TBD — Inbox screen (not in scope until W4) |
| `createPaymentRequest` | `ReceiveScreen` "Request" path |
| `getPaymentRequest` | Deep-link landing inside the app |
| `cancelPaymentRequest` | TBD |

### Claims

| operationId | Caller |
|---|---|
| `inspectClaim` | Deep-link landing screen for unclaimed transfers (W4); **unauthenticated** call. |
| `redeemClaim` | Claim-landing screen post-login (W4). |

### Devices

| operationId | Caller |
|---|---|
| `registerDevice` | After successful login + on FCM token refresh |
| `deleteDevice` | `SessionController.clear()` best-effort on logout |

### Notifications

| operationId | Caller |
|---|---|
| `listNotifications` | `NotificationsSheet` + future full-list screen |
| `markNotificationsRead` | On sheet open + per-row tap |

### Realtime

| operationId | Caller |
|---|---|
| `realtimeConnect` | `RealtimeService` (W3) — single WSS connection per app process. Routes events to feature controllers via a `Stream<RealtimeEvent>` exposed by `GetxService`. |

---

## 9. Realtime channel handling (preview, W3 work)

- Single WSS connection in `RealtimeService extends GetxService`.
- Auth: `?token=<accessToken>` on the upgrade URL.
- Reconnect: exponential backoff (1s, 2s, 5s, 15s, 60s capped).
- Heartbeat: server pings every 25s; client replies pong. Missed pong → reconnect.
- Token refresh: on 401-style close, refresh via `AuthInterceptor` path, reconnect.
- Event routing: parses `RealtimeEvent { channel, type, data }` and emits on a broadcast stream. Feature controllers subscribe to the channels they care about.

**Polling fallback** is mandatory for: transfer outcome (every 3s up to 60s if WSS not connected), onramp/offramp order status, KYC status.

---

## 10. Money formatting (client invariant)

- Server returns money as **decimal strings** with ≤6 dp (per `Money` schema).
- Client never parses to `double`. We use `Decimal` (package `decimal`) or `BigInt` minor units, never `double`.
- Display formatting via existing `MoneyFormat` util — extend to consume `String` directly.
- On submit, client sends back a string matching the same pattern.

---

## 11. Open questions (need backend confirmation)

**Q1. Stable error-code list.** OpenAPI shows `Problem.code` examples but no canonical enum. Client needs a frozen list (§7) so we can switch on `code` instead of `title` strings. Action: backend to publish `error-codes.md` or add an `enum` to `Problem.code`.

**Q2. `Idempotency-Key` storage scope.** Spec says "stored 24h". Confirm:
  - Replay returns **exact original status + body** (including headers like `Location`)?
  - Replay of an in-flight request: does the server block-and-wait or return `409`/`202` with a "still processing" marker?

**Q3. Step-up coverage.** Spec marks `TxnToken` parameter on onramp, offramp, transfers create. Does it also apply to:
  - `cancelTransfer`?
  - `createPaymentRequest`?
  - `redeemClaim`?
  Client default: **require step-up on all four** (safer). Backend to confirm.

**Q4. WSS auth refresh.** When the access token expires mid-WSS, does the server send a close frame with a specific code so the client can refresh + reconnect? Or does it accept a `{"type":"reauth", "token":"..."}` frame in-band?

**Q5. Device dedupe.** If a phone is re-registered on a new device, are previous device's push tokens revoked? Does `verifyOtp` issue a `device_id`-bound refresh token that invalidates older devices? Client UX for "logged in elsewhere" depends on this.

**Q6. KYC re-submission.** After a `REJECTED` submission, can the same user create a new `KycSubmission` (resubmit), or is there a cooldown? Client needs the rule to enable/disable the resubmit CTA.

**Q7. Onramp `payer_msisdn`.** Spec allows arbitrary phone. Confirm: must `payer_msisdn` match the authenticated user's verified phone? If not, what's the AML rule?

**Q8. Claim phone match.** Spec line 896 says "phone on the claim must match the caller's verified phone". Country is implicit — confirm matching is done on full E.164 (not the national-part only), to avoid cross-country collisions.

**Q9. `expires_in` jitter.** Refresh-token issued on `verifyOtp` — does its TTL "slide" on each refresh, or is it absolute from first issue? Affects how aggressively the client should pre-refresh.

**Q10. `Accept-Language` semantics.** Does the server localize `Problem.title` / `detail` based on `Accept-Language`, or are those always English? Client UI strings come from `app_localizations.dart`; server messages need to match the locale or be replaced by client-side mappings of `code`.

---

## 12. Local-only state (no API counterpart, yet)

These live entirely in the client for now; W3 may migrate some to server-side:

- **`FavoritesService`** (in-memory, P0 W1 — *will be replaced by server `SavedRecipient` in W3*).
- **Onboarding-complete flag** — `flutter_secure_storage` key `onboarding.complete`.
- **Biometric-enabled flag** — `flutter_secure_storage` key `biometric.enabled`.
- **Recent currency-switch preference** — `flutter_secure_storage` key `currency.preferred`.
- **Locale override** — `flutter_secure_storage` key `locale.override` (null = follow system).

`SharedPreferences` is **not** used for any of these — fintech preference is encrypted KV.

---

## 13. Build flavors → server mapping

| Flavor | `API_BASE_URL` | Sentry env | PostHog project |
|---|---|---|---|
| `dev` | `http://10.0.2.2:3000` (Android emu) / `http://localhost:3000` (iOS sim) | `development` | dev project |
| `staging` | `https://api.staging.moneya.app` | `staging` | staging project |
| `prod` | `https://api.moneya.app` | `production` | prod project |

`BYPASS_ONBOARDING` is honored only when `flavor != prod && kDebugMode`.

---

## 14. Document lifecycle

- This document is updated **in the same PR** as any change to `openapi.yaml` that affects the client.
- Section 11 (Open questions) is the working backlog — items move to confirmed sections (§§4–8) as backend answers land.
- W2 PRs MUST reference the operationId they're implementing in their description.

— Last updated: W1 PR1.
