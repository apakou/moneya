# MoneyA — Webhook Contracts

> ⚠️ **Partially superseded.** MoneyA now settles on **Stellar** with **pooled custody**, and the API is **fiat-only** — users must never learn that stablecoins are used. Solana / Privy / SPL parts of this document no longer apply. See [`stellar-mvp-plan.md`](./stellar-mvp-plan.md) §1.1 and **Appendix B** for exactly what changed.

> **Status:** v1 (Phase 1 / Supabase deployment)
> **Owner:** Backend
> **Companion docs:** [`architecture.md`](./architecture.md) §3, [`openapi.yaml`](./openapi.yaml) `/webhooks/*`, [`transfer-state-machine.md`](./transfer-state-machine.md), [`ledger.md`](./ledger.md)

This document specifies how MoneyA receives, verifies, dedupes, and
processes inbound webhooks from third parties. **Every webhook handler in
the codebase MUST implement the steps in §2 in the order given.**
Deviations break replay safety and audit guarantees.

---

## Table of contents

1. [Providers & event taxonomy](#1-providers--event-taxonomy)
2. [Universal handler pipeline](#2-universal-handler-pipeline)
3. [Signature verification per provider](#3-signature-verification-per-provider)
4. [Dedupe & idempotency](#4-dedupe--idempotency)
5. [Yellow Card webhook](#5-yellow-card-webhook)
6. [Smile ID webhook](#6-smile-id-webhook)
7. [Privy webhook](#7-privy-webhook)
8. [Twilio Verify (status callback, optional)](#8-twilio-verify-status-callback-optional)
9. [Retry semantics & backpressure](#9-retry-semantics--backpressure)
10. [Replay tooling](#10-replay-tooling)
11. [Security & secret rotation](#11-security--secret-rotation)
12. [Observability](#12-observability)
13. [Testing & local development](#13-testing--local-development)
14. [Open questions](#14-open-questions)

---

## 1. Providers & event taxonomy

Phase 1 inbound webhook providers:

| Provider | Endpoint | Verification | Events of interest |
|----------|----------|--------------|---------------------|
| Yellow Card | `POST /webhooks/yellow-card` | HMAC-SHA256 over raw body | `collection.completed`, `collection.failed`, `payout.processing`, `payout.settled`, `payout.failed` |
| Smile ID | `POST /webhooks/smile-id` | RSA signature over canonical JSON | `job.result` (APPROVED / REJECTED / MANUAL_REVIEW) |
| Privy | `POST /webhooks/privy` | HMAC-SHA256 over raw body | `wallet.created`, `wallet.transaction_signed`, `wallet.policy_violation` |
| Twilio Verify | (optional, see §8) | HMAC-SHA1 over canonical URL+params | OTP delivery callbacks (informational) |

Phase 1 outbound webhooks: **none**. We do not yet expose webhooks to
merchant integrators. Phase 2 may add merchant payout webhooks.

### 1.1 What fires for which transfer state transition

Cross-reference with `transfer-state-machine.md`:

| Provider event | Drives FSM transition |
|----------------|------------------------|
| YC `collection.completed` | `onramp.AWAITING_PAYMENT → COLLECTED` |
| YC `collection.failed` | `onramp.AWAITING_PAYMENT → FAILED` |
| YC `payout.settled` | `offramp.PROCESSING → SETTLED` |
| YC `payout.failed` | `offramp.PROCESSING → FAILED` (initiates refund) |
| Smile `APPROVED` | `kyc.PENDING → APPROVED` (provisions wallet) |
| Smile `REJECTED` | `kyc.PENDING → REJECTED` |
| Smile `MANUAL_REVIEW` | Stays `PENDING`; flags `requires_manual_review = true` |
| Privy `wallet.created` | Idempotent confirmation; updates `wallets.address` if not set |
| Privy `wallet.transaction_signed` | Informational; correlates with our outbound `sign` call |
| Privy `wallet.policy_violation` | P0 alert; halts further signing for that wallet |

---

## 2. Universal handler pipeline

**Every** inbound webhook handler executes these 8 steps in order.
Failure at any step before step 6 returns the noted HTTP status; failure
at step 6 or later returns 200 (the work is queued).

```
1. Capture raw body                  → in-memory bytes (do NOT parse JSON yet)
2. Verify signature                  → 400 on failure (NOT 401, see §3.1)
3. Parse JSON                        → 400 on failure
4. Extract event_id                  → 400 if missing
5. Insert audit.webhook_events       → ON CONFLICT DO NOTHING; if conflict → return 200 (replay)
6. Enqueue handler job (pg-boss/SQS) → with raw payload + provider tag
7. Return 200                        → response body: { received: true }
8. (async) Worker picks up job, runs FSM transition, updates audit row
```

### 2.1 Why raw body before parse

Signature verification operates on the raw byte stream. Parsing first
and re-serialising changes whitespace/key-ordering and breaks the HMAC.
NestJS interceptor:

```ts
@Controller('/webhooks')
export class WebhooksController {
  @Post('yellow-card')
  async handleYc(
    @RawBody() raw: Buffer,                // ← express.raw() middleware on this route
    @Headers('x-yc-signature') sig: string,
  ) {
    if (!verifyYcSignature(raw, sig)) throw new BadRequestException('bad sig');
    const event = JSON.parse(raw.toString('utf8'));
    return this.webhookService.ingest('yellow_card', event, raw);
  }
}
```

> **Configuration trap:** Express's default JSON middleware MUST be
> disabled on `/webhooks/*` so `RawBody` works. NestJS:
> `app.use('/webhooks', express.raw({ type: 'application/json', limit: '512kb' }))`
> registered **before** `useGlobalPipes`.

### 2.2 200-after-enqueue rule

The handler returns 200 as soon as the row is written to
`audit.webhook_events` and the job is enqueued. The actual FSM transition
happens in a worker. Reasons:

- Provider timeouts are typically 5–10s. Privy / YC / Smile retry on
  any non-2xx including timeouts. We must answer fast.
- If the worker fails, we have the raw payload persisted and can replay.
- Ordering: providers may deliver out-of-order. The worker queue is
  serialised per `(provider, ref_id)` to enforce in-order processing.

### 2.3 Status code semantics

| Code | Meaning | Provider behaviour |
|------|---------|---------------------|
| 200 | Accepted (idempotent). Includes both fresh and replay events. | No retry. |
| 400 | Signature invalid OR malformed body. | Some providers retry, some don't. We log P1; assume malicious or misconfigured. |
| 401 | (Reserved) — we never return 401 on webhook routes. | n/a |
| 413 | Body too large (> 512 KB). | Provider should not retry. |
| 500 | Internal error before enqueue (e.g., DB down). | Provider retries with backoff. |
| 503 | Maintenance window. | Provider retries. |

> **We never use 4xx other than 400/413 on webhook routes.** This
> simplifies provider-side runbooks.

---

## 3. Signature verification per provider

### 3.1 Why 400 not 401 on bad sig

401 implies "missing/expired credentials" and providers may retry with
the same payload. 400 means "your payload is broken; don't retry until
you fix it." A bad signature is a payload-integrity issue. Returning 400
also avoids leaking the existence of the route to scanners.

### 3.2 Yellow Card: HMAC-SHA256

```
signature_header = X-YC-Signature: t=<unix_ts>,v1=<hex_hmac>

To verify:
  signed_payload = <unix_ts> + "." + <raw_body_utf8>
  expected = hex(HMAC-SHA256(YC_WEBHOOK_SECRET, signed_payload))
  constant_time_eq(expected, v1)

Reject if:
  - header missing or malformed
  - |unix_ts - now()| > 300 seconds  (prevents replay of stale events)
  - signature mismatch
```

Implementation:

```ts
function verifyYcSignature(raw: Buffer, header: string): boolean {
  const parts = Object.fromEntries(
    header.split(',').map(p => p.split('=', 2)) as [string, string][]
  );
  const ts = parseInt(parts.t, 10);
  if (isNaN(ts) || Math.abs(Date.now() / 1000 - ts) > 300) return false;
  const signed = `${parts.t}.${raw.toString('utf8')}`;
  const expected = createHmac('sha256', process.env.YC_WEBHOOK_SECRET!)
    .update(signed)
    .digest('hex');
  return timingSafeEqual(Buffer.from(expected), Buffer.from(parts.v1));
}
```

### 3.3 Smile ID: RSA signature

Smile ID signs the **canonical JSON** (sorted keys, no whitespace) of the
payload with their RSA private key; we verify with their public key
(rotated quarterly, fetched from their docs portal at start-up and
cached).

```
signature_header = X-Smile-Signature: <base64_rsa_signature>

To verify:
  canonical = canonicalJSON(parsed_body)        // RFC 8785 (JCS)
  decoded_sig = base64.decode(header)
  RSA.verify(SMILE_PUBLIC_KEY, sha256(canonical), decoded_sig)
```

> **Implementation note:** the canonical JSON requirement means we DO
> have to parse the body before verifying — but we lock the canonical
> form so re-serialisation is deterministic. Use a vetted JCS library
> (`@webrecorder/canonicalize-rfc8785` or equivalent), not a hand-roll.

> **Trade-off vs Yellow Card style:** RSA-over-canonical is more brittle
> than HMAC-over-raw (any JCS implementation drift between Smile and us
> breaks verification). We accept this for Smile because that's their
> contract; for our own future outbound webhooks we'll prefer HMAC-over-raw.

### 3.4 Privy: HMAC-SHA256

```
signature_header = Privy-Signature: <hex_hmac_sha256>

To verify:
  expected = hex(HMAC-SHA256(PRIVY_WEBHOOK_SECRET, raw_body))
  constant_time_eq(expected, header)
```

No timestamp. Privy relies on TLS + secret rotation for replay defence.
We add our own dedupe via `event_id` (§4).

### 3.5 Local secret storage

| Secret | Storage | Rotation cadence |
|--------|---------|-------------------|
| `YC_WEBHOOK_SECRET` | Supabase Vault (Phase 1) → AWS Secrets Manager (Phase 2) | 90 days |
| `SMILE_PUBLIC_KEY` | Cached in process memory at boot from Smile's portal API | At their cadence (~quarterly) |
| `PRIVY_WEBHOOK_SECRET` | Same as YC | 90 days |

Rotation drill: §11.

---

## 4. Dedupe & idempotency

### 4.1 The dedupe table

`audit.webhook_events` (already in `migrations/0001_init.sql`):

```sql
CREATE TABLE IF NOT EXISTS audit.webhook_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider        TEXT NOT NULL,         -- 'yellow_card' | 'smile_id' | 'privy'
    event_id        TEXT NOT NULL,         -- provider-supplied
    event_type      TEXT,
    raw_payload     JSONB NOT NULL,
    headers         JSONB NOT NULL,        -- captured headers for forensics
    received_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at    TIMESTAMPTZ,           -- set when worker completes
    processing_error TEXT,                 -- if last attempt failed
    UNIQUE (provider, event_id)
);
```

### 4.2 Insert semantics

```sql
INSERT INTO audit.webhook_events (provider, event_id, event_type, raw_payload, headers)
VALUES ($1, $2, $3, $4::jsonb, $5::jsonb)
ON CONFLICT (provider, event_id) DO NOTHING
RETURNING id;
```

If `RETURNING id` is empty → already seen → return 200 immediately,
**do not enqueue**, **do not invoke FSM**.

### 4.3 What if event_id is missing?

| Provider | event_id field | Fallback |
|----------|----------------|----------|
| YC | `event_id` (always present) | n/a |
| Smile | `event_id` (always present per their v2 API) | If absent → use `job_id + result + occurred_at` SHA256 |
| Privy | `event_id` (always present) | n/a |
| Twilio | `MessageSid` | Use as event_id |

Returning 400 on missing `event_id` is acceptable for production — the
provider has a contract violation and should not retry blindly.

### 4.4 Why `(provider, event_id)` and not just `event_id`

Different providers may collide on event ID format (e.g., both might use
short random strings). Compositing by provider keeps things tidy and
prevents cross-provider confusion in audit queries.

### 4.5 Out-of-order delivery

A common case: YC sends `payout.processing` and `payout.settled` within
50ms; we receive `settled` first.

**Handling:** the FSM is forward-only. The handler for `payout.settled`
attempts the transition `offramp.PROCESSING → SETTLED`. If the row is
already `PROCESSING` (it should be, since we created it that way at
order-time), the transition succeeds. If `payout.processing` arrives
afterward, the FSM rejects the redundant transition (no-op) — the row
is already past that state. Both webhooks are recorded in
`audit.webhook_events`; only the meaningful one drives the row.

> **Guarantee:** every webhook is **acknowledged** (200) and **persisted**
> (audit row), regardless of whether it advances the FSM.

### 4.6 Per-(provider, ref) serialisation

Multiple workers consuming from pg-boss/SQS could otherwise process two
events for the same order in parallel. To prevent races:

```sql
-- Inside the worker, before applying:
SELECT pg_advisory_xact_lock(
    hashtext('webhook:' || $provider || ':' || $ref_id)
);
```

This serialises per logical resource without blocking unrelated work.

---

## 5. Yellow Card webhook

### 5.1 Endpoint & headers

```
POST /webhooks/yellow-card
Content-Type: application/json
X-YC-Signature: t=<ts>,v1=<hex>
```

### 5.2 Event types

#### 5.2.1 `collection.completed`

```json
{
  "event_id": "evt_2P9k3...wQ",
  "event_type": "collection.completed",
  "occurred_at": "2026-05-01T17:23:14Z",
  "data": {
    "order_id": "yc_ord_a1b2c3d4",
    "provider_reference": "wave_txn_993f",
    "settled_amount_fiat": "25000.00",
    "settled_currency": "XOF"
  }
}
```

**Worker action:**
1. Look up `app.onramp_orders WHERE yc_order_id = $1`.
2. If not found, retry lookup up to 5s @ 100ms (handles race where
   webhook beats the API response — see state-machine.md §11.4).
3. If still not found, log warning, mark webhook event `processed_at`
   with `processing_error='order_not_found'`, return.
4. If found and status = `AWAITING_PAYMENT` → drive transition
   `AWAITING_PAYMENT → COLLECTED`, set `next_action_at = now()` to
   trigger immediate USDC credit by main worker.
5. Verify `settled_amount_fiat` matches the quoted amount within 0.01
   fiat tolerance. Mismatch → P1 alert + manual review (do NOT credit
   USDC).

#### 5.2.2 `collection.failed`

```json
{
  "event_id": "evt_2P9k4...xQ",
  "event_type": "collection.failed",
  "occurred_at": "2026-05-01T17:23:14Z",
  "data": {
    "order_id": "yc_ord_a1b2c3d4",
    "failure_reason": "insufficient_funds_at_msisdn"
  }
}
```

**Worker action:** drive `AWAITING_PAYMENT → FAILED` with
`failure_reason='PROVIDER_REJECTED'`; reverse SUSPENSE pre-hold (no
ledger entries to reverse if `COLLECTED` never fired); push notification
"Top-up failed".

#### 5.2.3 `payout.processing`

Acknowledgement that YC has begun the payout. Informational; we already
moved the row to `PROCESSING` at order creation. Worker no-ops the FSM
but updates `offramp_orders.yc_processing_ack_at = occurred_at`.

#### 5.2.4 `payout.settled`

```json
{
  "event_id": "evt_2P9k5...yQ",
  "event_type": "payout.settled",
  "occurred_at": "2026-05-01T17:25:48Z",
  "data": {
    "order_id": "yc_ord_a1b2c3d4",
    "provider_reference": "mpesa_b2c_8821xx",
    "settled_amount_fiat": "10000.00",
    "settled_currency": "KES"
  }
}
```

**Worker action:**
1. Drive `offramp.PROCESSING → SETTLED`.
2. Post ledger journals per `ledger.md` §4.3.3 (per-order
   `YC_PAYABLE → SUSPENSE`).
3. Notify user: "Cash-out complete".

#### 5.2.5 `payout.failed`

```json
{
  "event_id": "evt_2P9k6...zQ",
  "event_type": "payout.failed",
  "occurred_at": "2026-05-01T17:25:48Z",
  "data": {
    "order_id": "yc_ord_a1b2c3d4",
    "failure_reason": "msisdn_not_registered"
  }
}
```

**Worker action:**
1. Drive `offramp.PROCESSING → FAILED` (`PROVIDER_REJECTED`).
2. Trigger refund job: enqueue Privy.sign(SPL hot → user, `amount_usdc`).
3. On confirm → `FAILED → REFUNDED`; post ledger reversal journals
   (`ledger.md` §4.3.4).
4. Notify user: "Cash-out failed; funds returned to your USDC balance."

### 5.3 YC-specific edge cases

- **Duplicate `payout.settled` after `payout.failed`** (YC bug we've
  observed in their sandbox): row is in `FAILED`. Settled webhook is a
  no-op transition (terminal-state-locked). Audit row written; P1 alert
  raised because YC may have actually paid out and we already refunded
  → potential double-spend by user. Manual reconciliation.
- **Late `collection.completed` after `EXPIRED`**: row is in `EXPIRED`.
  Treat as if user paid after window. P2 alert; ops team contacts user
  to either credit USDC late or refund fiat via YC. Default action:
  ops decides; do not auto-process.

---

## 6. Smile ID webhook

### 6.1 Endpoint & headers

```
POST /webhooks/smile-id
Content-Type: application/json
X-Smile-Signature: <base64>
```

### 6.2 Payload

```json
{
  "event_id": "smile_evt_8821xx",
  "job_id": "moneya_kyc_<submission_id>",
  "result": "APPROVED",
  "rejection_reason": null,
  "occurred_at": "2026-05-01T17:23:14Z"
}
```

`job_id` is the `submission_id` we passed at submit-time, prefixed
`moneya_kyc_` for clarity. Strip prefix on lookup.

### 6.3 Worker actions

| `result` | FSM transition | Side effects |
|----------|----------------|--------------|
| `APPROVED` | `kyc.PENDING → APPROVED` | Set `users.kyc_tier = 1`; trigger wallet provisioning (Privy.createWallet); push "KYC approved"; emit WSS `kyc.approved` |
| `REJECTED` | `kyc.PENDING → REJECTED` | Set `kyc_submissions.rejection_reason`; push "Verification needs another attempt"; allow user to re-submit |
| `MANUAL_REVIEW` | (no transition) | Set `kyc_submissions.requires_manual_review = true`; alert compliance ops; status remains `PENDING` user-side |

### 6.4 Wallet provisioning chain (after APPROVED)

The webhook handler does NOT directly call Privy. It enqueues a separate
`provision_wallet` job:

```
1. webhook handler:
   - update kyc_submissions.status = APPROVED
   - update users.kyc_tier = 1
   - enqueue { type: 'provision_wallet', user_id }
   - return 200

2. wallet-provision worker (separate queue):
   - check users.kyc_tier >= 1
   - check no existing wallets row for user
   - call Privy.createWallet({ chain: 'solana', owner: user_id })
   - persist wallets row
   - emit WSS event
   - push notification
```

This separation lets the wallet-provision worker retry independently if
Privy is down without re-running KYC logic.

### 6.5 Smile-specific edge cases

- **Late retry from Smile after our `processed_at` was set**: dedupe
  via `event_id` returns 200; no double provisioning.
- **`MANUAL_REVIEW` then later `APPROVED` (Smile's compliance team
  cleared)**: arrives as new `event_id`. Worker treats as fresh APPROVED;
  transitions row, provisions wallet (if not already). Idempotent.
- **`APPROVED` for a submission_id we don't know**: Smile sometimes
  sends events for jobs that errored on submit. Log warning, audit row,
  do not act.

---

## 7. Privy webhook

### 7.1 Purpose

Privy primarily responds synchronously to our API calls (sign,
createWallet). Webhooks are belt-and-suspenders + policy notifications.

### 7.2 Event types

#### 7.2.1 `wallet.created`

Fires on every successful wallet creation. We've already persisted the
wallet row from the synchronous response, so this is informational.

**Worker action:** if `wallets WHERE privy_wallet_id = $1` row exists
with matching `address` → no-op. If row exists with **mismatched**
`address` → P0 alert (massive divergence). If row absent → log warning,
insert with `created_via='webhook_recovery'` flag (rare; means the
synchronous response was lost).

#### 7.2.2 `wallet.transaction_signed`

Fires for every signing event. Useful for forensics / reconciliation;
not required for FSM operation.

**Worker action:** insert into `audit.privy_signings (privy_wallet_id,
signature, occurred_at, raw_payload)` for forensic queries.

#### 7.2.3 `wallet.policy_violation`

Privy's MPC custody enforces policies (max amount per tx, allowed
chains, etc.). A violation indicates either misuse or mis-configuration.

**Worker action:**
1. P0 alert — page on-call.
2. Set `wallets.suspended_at = now()` for that user.
3. Halt all queued signing jobs for that wallet.
4. Manual remediation required before unsuspending.

### 7.3 Privy-specific edge cases

- **Webhook fires before our DB sees the new wallet row**: handler
  retries lookup 5s @ 100ms (same as YC §5.2.1). If still missing →
  insert recovery row.
- **Out-of-order `transaction_signed` vs our own outbound signature
  return**: the audit table just records both; reconciliation joins on
  signature.

---

## 8. Twilio Verify (status callback, optional)

Twilio Verify exposes an optional **status callback** webhook for OTP
delivery events. Phase 1 we **do not enable** this — synchronous
`POST /v1/auth/otp` already returns enough state. Phase 2 may enable for
delivery analytics.

If enabled later: HMAC-SHA1 over canonical request URL + sorted form
params, header `X-Twilio-Signature`. Twilio's docs are authoritative.

---

## 9. Retry semantics & backpressure

### 9.1 What providers do

| Provider | Retry policy | Total window |
|----------|--------------|--------------|
| Yellow Card | Exponential, 5s base, factor 2, max 1h | 24 hours |
| Smile ID | Exponential, 30s base, factor 2 | 1 hour, 5 attempts |
| Privy | Exponential, 1s base, factor 2 | 30 minutes, 8 attempts |

### 9.2 What we do under load

If our webhook endpoint is healthy but slow (DB pressure, etc.), we
return 200 fast (per §2.2 the work is decoupled). The bottleneck is
worker throughput, not webhook ingestion.

If `audit.webhook_events` insert itself fails (DB down):

- Return 503.
- Provider will retry per §9.1.
- If down > 1 hour during business hours → P0 alert, escalate.
- We never miss webhooks within the provider's 24h window.

### 9.3 Worker queue backpressure

pg-boss queue depths monitored. If `webhook_processing` queue depth >
500 sustained for 5 min → P1 alert. Likely root cause: external
dependency slow (Privy, Solana RPC) blocking worker progress. Action:
spin up more workers; investigate root cause.

### 9.4 Poison pills

If a single audit row repeatedly fails worker processing (worker
exception caught, retry, fail, retry, fail...), pg-boss moves it to a
dead-letter queue after 5 attempts. The row is flagged
`audit.webhook_events.processing_error = '<last error>'`. Daily
cron alerts on rows older than 1h with non-null `processing_error` and
null `processed_at`.

---

## 10. Replay tooling

Operations need to be able to replay a webhook (e.g., bug fix in
handler; provider already delivered). One CLI command:

```
moneya-ops webhook replay <provider> <event_id>
```

Implementation:

```ts
async function replay(provider: string, eventId: string) {
  const row = await db.query(
    `SELECT raw_payload, headers FROM audit.webhook_events
      WHERE provider = $1 AND event_id = $2`,
    [provider, eventId],
  );
  if (!row) throw new Error('event not found');

  // Reset processing fields:
  await db.query(
    `UPDATE audit.webhook_events
        SET processed_at = NULL, processing_error = NULL
      WHERE provider = $1 AND event_id = $2`,
    [provider, eventId],
  );

  // Re-enqueue worker job:
  await pgBoss.send('webhook_processing', {
    provider,
    event_id: eventId,
    raw_payload: row.raw_payload,
    headers: row.headers,
    replay: true,
  });
}
```

The `replay: true` flag is logged in trace context and metrics so we can
distinguish replay-driven side effects from organic ones.

> ⚠️ **Replay is dangerous if the FSM has already moved past the event's
> implied state.** The worker should still be idempotent (per
> state-machine.md §9.3), but operators should confirm with `--dry-run`
> first:
>
> ```
> moneya-ops webhook replay <provider> <event_id> --dry-run
> ```
>
> Output: would-be transitions and ledger journals; no DB changes.

---

## 11. Security & secret rotation

### 11.1 Inbound TLS

All webhook routes are served over TLS 1.2+. Phase 1 (Supabase): TLS
terminates at Supabase Edge. Phase 2 (AWS): ALB with ACM cert.
No mTLS at Phase 1 (providers don't support it uniformly).

### 11.2 Secret rotation

Standard procedure (every 90 days, or on-demand on suspected leak):

1. Generate new secret in provider portal (YC, Privy admin UI).
2. Add new secret to Supabase Vault / AWS Secrets Manager as
   `<NAME>_NEXT`.
3. Deploy handler that accepts EITHER `<NAME>` or `<NAME>_NEXT` for
   verification (try both; use first match).
4. Wait 24 hours (provider warm-up); verify both signatures observed in
   logs.
5. Activate `<NAME>_NEXT` in provider portal as primary.
6. Wait 24 hours.
7. Remove old `<NAME>`; rename `<NAME>_NEXT` → `<NAME>`.
8. Deploy handler that verifies only `<NAME>` again.

This dual-acceptance window prevents a hard-cutover gap.

### 11.3 Audit log

`audit.audit_log` records every replay invocation, secret rotation, and
manual webhook event mutation, with operator identity (from admin
session JWT).

---

## 12. Observability

### 12.1 Required metrics

| Metric | Type | Labels |
|--------|------|--------|
| `webhook_received_total` | counter | `provider`, `event_type`, `verification_result` |
| `webhook_signature_failures_total` | counter | `provider` |
| `webhook_dedupe_hits_total` | counter | `provider` |
| `webhook_processing_duration_seconds` | histogram | `provider`, `event_type` |
| `webhook_processing_errors_total` | counter | `provider`, `event_type`, `error_kind` |
| `webhook_dlq_size` | gauge | `provider` |

### 12.2 Required alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| Signature failures | rate > 5/min for any provider | P1 (likely misconfigured secret OR attack) |
| Dedupe rate spike | > 50% of received over 5 min | P2 (provider replaying — investigate) |
| Processing errors | rate > 1/min | P1 |
| DLQ growing | size > 0 sustained > 1h | P1 |
| No webhooks from YC | gap > 30 min during business hours | P2 (YC may be down) |
| `wallet.policy_violation` | any | P0 |
| Mismatched amount on `collection.completed` | any | P1 |
| Privy address mismatch on `wallet.created` | any | P0 |

### 12.3 Tracing

Each webhook handler creates a root span `webhook.<provider>.<event_type>`
with attributes:

- `webhook.event_id`
- `webhook.signature_valid`
- `webhook.dedupe_hit`
- `webhook.ref_id` (after lookup)
- `webhook.replay` (boolean)

Worker span is a child created when the queue handler dequeues, linking
back via the dequeued message's `traceparent`.

---

## 13. Testing & local development

### 13.1 Local replay fixtures

`scripts/webhook-fixtures/` (to be added) holds canonical examples of
each event type as raw bytes + expected signature (using a dev secret).
Tests POST these to a running local server and assert:

- 200 returned
- `audit.webhook_events` row inserted
- FSM state advanced as expected
- Idempotent on second POST

### 13.2 Provider sandbox testing

| Provider | Sandbox availability | Notes |
|----------|----------------------|-------|
| Yellow Card | Yes (sandbox.yellowcard.io) | Provides webhook trigger UI |
| Smile ID | Yes (testapi.smileidentity.com) | Manual job triggering |
| Privy | Yes (dashboard test env) | Limited webhook events |

Each environment uses a separate webhook secret (`*_SANDBOX` suffix in
secrets manager). Local dev tunnels via ngrok / cloudflared.

### 13.3 Integration test pattern

```ts
describe('YC webhook: collection.completed', () => {
  it('drives onramp from AWAITING_PAYMENT to COMPLETED via worker', async () => {
    const order = await createOnrampOrder({ status: 'AWAITING_PAYMENT' });
    const payload = ycCollectionCompletedFixture(order.yc_order_id);
    const sig = signYc(payload, TEST_SECRET);
    const res = await request(app).post('/webhooks/yellow-card')
      .set('X-YC-Signature', sig)
      .set('Content-Type', 'application/json')
      .send(payload);
    expect(res.status).toBe(200);

    await waitForState(order.id, 'COMPLETED', { timeout: 5000 });

    const events = await db.query(
      'SELECT * FROM app.transfer_events WHERE transfer_id = $1', [order.transfer_id],
    );
    expect(events.map(e => e.to_status)).toContain('COMPLETED');

    const ledger = await ledgerJournalsFor(order.id);
    expect(ledger).toMatchSnapshot();   // assert journal templates §4.2
  });
});
```

---

## 14. Open questions

| # | Question | Owner | Decision deadline |
|---|----------|-------|--------------------|
| Q1 | Static IP allowlist for inbound webhooks (defense-in-depth on top of HMAC)? Phase 1 = no; Phase 2 = maybe via AWS WAF. | Backend | Phase 2 design |
| Q2 | Should we log raw payload as JSONB or as bytea (preserves byte-perfect copy for re-verification)? Currently JSONB; loses key-order. | Backend | Pre-launch |
| Q3 | `audit.webhook_events` retention — 1 year? 7 years? GDPR considerations for any payloads with PII (Smile result includes name match info). | Compliance | Pre-launch |
| Q4 | Outbound webhooks to merchants — Phase 2 design (signing scheme, retry contract, dashboard for log/replay). | Product | Phase 2 design |
| Q5 | Single shared `audit.webhook_events` table vs per-provider? Currently single. Per-provider would let us shard / partition independently. | Backend | If volume > 1M events/day |
| Q6 | Should `wallet.policy_violation` automatically suspend the user (not just the wallet)? Currently suspends wallet only. | Compliance | Phase 1 launch |
| Q7 | Twilio status callback — adopt at Phase 2 for delivery analytics? | Product | Phase 2 |

---

**End of webhook spec.** Companion docs to author next:
- `docs/backend/backlog.md` — Phase 1 ticketed implementation order with sizing and acceptance criteria
