# MoneyA — Double-Entry Ledger Specification

> ⚠️ **Partially superseded.** MoneyA now settles on **Stellar** with **pooled custody**, and the API is **fiat-only** — users must never learn that stablecoins are used. Solana / Privy / SPL parts of this document no longer apply. See [`stellar-mvp-plan.md`](./stellar-mvp-plan.md) §1.1 and **Appendix B** for exactly what changed.

> **Status:** v1 (Phase 1 / Supabase deployment)
> **Owner:** Backend
> **Companion docs:** [`architecture.md`](./architecture.md) §5, [`transfer-state-machine.md`](./transfer-state-machine.md), [`migrations/0001_init.sql`](./migrations/0001_init.sql) §LEDGER

This document is the **authoritative specification for every ledger entry
that MoneyA writes**. It is the second source of truth (after the chain
itself). Every backend code path that calls `INSERT INTO app.ledger_entries`
MUST conform to one of the journal templates listed in §4.

If the on-chain state and the ledger disagree, the chain is correct and
the ledger has a bug — but in practice the daily reconciliation job (§7)
should catch any divergence within 24 hours.

---

## Table of contents

1. [Why double-entry, why now](#1-why-double-entry-why-now)
2. [Account taxonomy](#2-account-taxonomy)
3. [Sign convention & domain model](#3-sign-convention--domain-model)
4. [Journal templates per flow](#4-journal-templates-per-flow)
5. [Posting rules & atomicity](#5-posting-rules--atomicity)
6. [Balance derivation](#6-balance-derivation)
7. [Reconciliation](#7-reconciliation)
8. [Invariants & DB-level enforcement](#8-invariants--db-level-enforcement)
9. [Worked examples](#9-worked-examples)
10. [Reporting queries](#10-reporting-queries)
11. [Phase 2 considerations](#11-phase-2-considerations)
12. [Open questions](#12-open-questions)

---

## 1. Why double-entry, why now

A naive implementation tracks balance as `wallets.balance` and mutates it.
That's wrong for three reasons:

1. **Multi-leg transfers are not atomic with on-chain state.** A P2P
   transfer involves a sender debit, a recipient credit, and a fee
   credit. If we mutate three balance columns and crash mid-flight, we
   lose money or create money.
2. **Auditability.** Regulators (BCEAO, CBN) and partners (Yellow Card,
   Privy) require a per-transaction audit trail with immutable history.
3. **Reconciliation.** With three external sources of truth (Solana,
   Yellow Card, Privy custody), we need an internal ledger that we can
   diff against each of them daily.

A double-entry ledger gives us all three: every business event is one
**journal** with ≥ 2 **entries** that sum to zero, posted atomically,
append-only.

The trade-off is a small write amplification (3-4 entries per transfer
instead of 1 balance UPDATE). Acceptable.

---

## 2. Account taxonomy

Source: `app.ledger_account_kind` enum, `migrations/0001_init.sql:133-142`.

| Kind | Owner | Cardinality | Purpose |
|------|-------|-------------|---------|
| `USER_WALLET` | `users.id` | 1 per (user, currency) | Customer's spendable USDC. Should match on-chain Privy wallet balance ± in-flight escrow. |
| `MONEYA_HOT_WALLET` | NULL | 1 global (Phase 1) | Aggregate hot wallet on Solana. Source of funds for onramp credits, sink for offramp debits. |
| `MONEYA_ESCROW` | NULL | 1 global (Phase 1) | Holds unclaimed-transfer funds during the 7-day claim window. Backed by a separate Privy wallet. |
| `YC_RECEIVABLE` | NULL | 1 global | Yellow Card owes us this amount. Increases when fiat is collected from a user; decreases when YC mints USDC into our hot wallet. |
| `YC_PAYABLE` | NULL | 1 global | We owe Yellow Card this amount. Increases when YC pays out fiat to a user on our behalf; decreases when we settle USDC to YC. |
| `FEE_REVENUE` | NULL | 1 global | MoneyA's accumulated fee income. Phase 1: P2P fees, onramp/offramp spread. |
| `SUSPENSE` | NULL | 1 global | In-flight buffer. Used when the timing of two related ledger events spans a window > a few seconds. Always returns to zero. |

### 2.1 Per-user account creation

A `USER_WALLET` row is inserted **at wallet provisioning** (after KYC
tier 1 approval, see `architecture.md` §4.1). Composite uniqueness
`(kind, user_id, currency)` enforced at DB level — re-provisioning is
idempotent.

### 2.2 Why a single hot wallet & escrow at Phase 1

Sharding adds operational complexity (gas, key rotation, signer ACLs)
that pays off only at volume. Phase 1: $0–$50K daily volume; one wallet
each is fine. Phase 2 trigger: > $250K daily or single-wallet exposure
exceeds $100K → shard by corridor.

### 2.3 Account naming convention

```
{KIND}:{user_id|GLOBAL}:{currency}

Examples:
  USER_WALLET:7c9e5...d3a:USDC
  MONEYA_HOT_WALLET:GLOBAL:USDC
  YC_PAYABLE:GLOBAL:USDC
```

---

## 3. Sign convention & domain model

### 3.1 Sign convention

`app.ledger_entries.amount_usdc` is **signed**:

- **Positive (`+X`)** = credit to the account (account balance goes up)
- **Negative (`−X`)** = debit from the account (account balance goes down)

This is non-standard accounting (which traditionally uses separate
debit/credit columns), but it is operationally simpler in SQL: balance
is `SUM(amount_usdc) WHERE account_id = $1`.

> ⚠️ **All entries in a journal MUST sum to zero**, enforced by the
> deferred constraint trigger `app.ledger_journal_balance_check`.
> Application code MUST wrap multi-leg inserts in a single transaction.

### 3.2 Currency

Phase 1: all entries are `USDC`. The `currency` column is on every entry
to support future multi-currency expansion (e.g., direct fiat-denominated
ledger arms in Phase 2). Mixing currencies inside a single journal is
**forbidden** (each currency must balance to zero independently).

### 3.3 Precision

`numeric(20,6)` everywhere. 6 decimals matches USDC's on-chain decimals.
20 total digits = max 14 integer digits = 99 trillion USDC, ample.

### 3.4 Reference fields

Every entry MUST have:

- `journal_id` (UUID): groups the entries that belong to one business event
- `ref_type` (TEXT): `'TRANSFER'` | `'ONRAMP_ORDER'` | `'OFFRAMP_ORDER'`
  | `'CLAIM_REFUND'` | `'RECONCILIATION_ADJ'`
- `ref_id` (UUID): primary key of the referenced row
- `memo` (TEXT, optional): human-readable explanation, especially for
  `RECONCILIATION_ADJ` entries

---

## 4. Journal templates per flow

Each template lists every entry of one journal. Sums per currency MUST be
zero. **A template is the canonical recipe — backend code must implement
exactly these entries for the corresponding state transition.**

Notation: `[KIND:owner]` means the account; entries are written
`+amount` (credit) or `-amount` (debit).

### 4.1 P2P transfer (PROCESSING → COMPLETED)

**Trigger:** Solana confirms `sender_wallet → recipient_wallet` SPL transfer.
**Journal:** 1 journal, 3 entries.
**Reference:** `ref_type='TRANSFER'`, `ref_id=transfer.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `USER_WALLET:sender` | `−(amount + fee)` | `P2P send to <recipient_phone>` |
| 2 | `USER_WALLET:recipient` | `+amount` | `P2P recv from <sender_phone>` |
| 3 | `FEE_REVENUE:GLOBAL` | `+fee` | `P2P fee, transfer <id>` |

**Sum:** `-(amount+fee) + amount + fee = 0` ✓

If `fee = 0`, omit entry #3 (a 2-entry journal is fine).

### 4.2 Onramp (mobile money → USDC)

The onramp settles in two stages: fiat collection (YC webhook) and USDC
credit (Solana confirmation). Each stage is its own journal.

#### 4.2.1 Stage A: order created

**Trigger:** `POST /v1/onramp/orders` succeeds (YC returns `checkoutUrl`).
**Journal:** off-balance pre-hold. **No ledger entries written.**

The pre-hold lives in `app.escrow_holds` not the ledger, because nothing
has settled yet. (The state machine doc §5.2 mentions a "SUSPENSE
pre-hold" — that's a logical concept, not a ledger entry. Clarified
here.)

#### 4.2.2 Stage B: YC webhook `COLLECTED` → row in `app.transfers` of kind `ONRAMP`

**Trigger:** YC webhook handler verifies and dedupes.
**Journal:** 1 journal, 2 entries.
**Reference:** `ref_type='ONRAMP_ORDER'`, `ref_id=onramp_order.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `YC_RECEIVABLE:GLOBAL` | `+amount_usdc` | `YC collected <fiat_amount> <fiat_ccy>, order <id>` |
| 2 | `SUSPENSE:GLOBAL` | `−amount_usdc` | `Onramp pending USDC mint, order <id>` |

**Sum:** `+amount − amount = 0` ✓

> Why these accounts: YC has the user's fiat (asset for us → +receivable).
> The matching credit is `SUSPENSE` (negative because we treat suspense
> as a temporary holding bucket — it'll go positive when the credit lands
> in 4.2.3).

#### 4.2.3 Stage C: USDC credit confirmed on-chain

**Trigger:** Solana confirms `MONEYA_HOT_WALLET → user_wallet` SPL.
**Journal:** 1 journal, 4 entries (3 if no fee).
**Reference:** `ref_type='ONRAMP_ORDER'`, `ref_id=onramp_order.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `SUSPENSE:GLOBAL` | `+amount_usdc` | `Onramp credit landed, order <id>` |
| 2 | `MONEYA_HOT_WALLET:GLOBAL` | `−amount_usdc` | `Hot → user <user_id>, order <id>` |
| 3 | `USER_WALLET:user` | `+(amount_usdc − fee)` | `Top-up <fiat_amount> <fiat_ccy>` |
| 4 | `FEE_REVENUE:GLOBAL` | `+fee` | `Onramp fee, order <id>` |

**Sum:** `+amount − amount − (amount−fee) + fee = ... ` wait, let me recompute:
`+amount + (−amount) + (−(amount−fee)) + (+fee) = 0` — actually let me redo.

Re-derivation:
- Entry 1 = `+amount` (SUSPENSE credit, returning to zero)
- Entry 2 = `−amount` (hot wallet debit)
- Entry 3 = `+(amount−fee)` (user wallet credit)
- Entry 4 = `+fee` (fee revenue credit)

Sum = `+amount − amount + (amount−fee) + fee = +amount` ❌

That doesn't balance. The issue: SUSPENSE was credited with `−amount`
in 4.2.2 (so SUSPENSE balance was `-amount`), and now I want SUSPENSE
back to zero. To zero out SUSPENSE I need to **credit** it `+amount`,
which I did in entry 1. But then I'm adding `+amount` to the journal
without offsetting it.

Correct decomposition: the SUSPENSE round-trip and the YC_RECEIVABLE
clear are **separate** events (the on-chain credit clears YC_RECEIVABLE,
not SUSPENSE — YC has settled the underlying fiat to us by sending USDC
through the YC→hot wallet flow). Re-issuing:

**Stage C corrected — 4 entries:**

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `YC_RECEIVABLE:GLOBAL` | `−amount_usdc` | `YC settled, order <id>` |
| 2 | `SUSPENSE:GLOBAL` | `+amount_usdc` | `Onramp settled, order <id>` |

→ Journal X (clears YC receivable & SUSPENSE). Sum = 0 ✓

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 3 | `MONEYA_HOT_WALLET:GLOBAL` | `−amount_usdc` | `Hot → user, order <id>` |
| 4 | `USER_WALLET:user` | `+(amount−fee)` | `Top-up credited` |
| 5 | `FEE_REVENUE:GLOBAL` | `+fee` | `Onramp fee` |

→ Journal Y (hot wallet → user + fee). Sum = `−amount + amount−fee + fee = 0` ✓

> **Decision (DEC-LED-1):** **Two separate journals at stage C** —
> one to clear the receivable/suspense pair, one to record the
> on-chain credit. Cleaner reconciliation: journal X reconciles
> against YC's settlement report; journal Y reconciles against the
> on-chain SPL signature.

#### 4.2.4 Onramp failed before USDC credit

**Trigger:** webhook says REJECTED, or operator marks failed during
remediation.
**Journal:** 1 journal, 2 entries (reverses 4.2.2 if it occurred).
**Reference:** `ref_type='ONRAMP_ORDER'`, `ref_id=onramp_order.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `YC_RECEIVABLE:GLOBAL` | `−amount_usdc` | `Onramp reversed, order <id>` |
| 2 | `SUSPENSE:GLOBAL` | `+amount_usdc` | `Onramp reversed, order <id>` |

(If the webhook never reached `COLLECTED`, no ledger entry was made →
no reversal needed.)

### 4.3 Offramp (USDC → mobile money)

#### 4.3.1 Stage A: SPL `user_wallet → hot_wallet` confirmed + YC.payout submitted

**Trigger:** offramp service has both Solana confirmation **and**
successful YC.payout response.
**Journal:** 1 journal, 4 entries (3 if no fee).
**Reference:** `ref_type='OFFRAMP_ORDER'`, `ref_id=offramp_order.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `USER_WALLET:user` | `−amount_usdc` | `Offramp <fiat_amount> <fiat_ccy>` |
| 2 | `MONEYA_HOT_WALLET:GLOBAL` | `+(amount−fee)` | `User → hot, order <id>` |
| 3 | `FEE_REVENUE:GLOBAL` | `+fee` | `Offramp fee` |
| 4 | (skip if amount=net) | — | — |

Sum: `−amount + (amount−fee) + fee = 0` ✓

> Note: the user is debited the gross `amount_usdc`. The hot wallet
> receives the net (gross − fee). The fee was carved out at the
> ledger boundary, not on-chain — on-chain, the full `amount_usdc`
> moves user→hot.
>
> ⚠️ **Inconsistency check:** if on-chain shows `+amount` to hot and
> ledger shows `+(amount−fee)`, hot wallet's ledger ≠ on-chain by exactly
> the fee. **Resolution:** fees are accumulated in the hot wallet
> on-chain too — entry #2 should match the on-chain delta. Revised:

**Revised Stage A — 3 entries:**

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `USER_WALLET:user` | `−amount_usdc` | `Offramp <fiat_amount> <fiat_ccy>` |
| 2 | `MONEYA_HOT_WALLET:GLOBAL` | `+amount_usdc` | `User → hot, order <id>` |
| 3 | (no fee leg here — fee is collected via the hot/payable spread, see Stage B) | — | — |

Sum: `−amount + amount = 0` ✓

#### 4.3.2 Stage A.5: YC.payout submitted (we now owe YC fiat)

**Trigger:** YC.payout returns `{ status: PROCESSING, orderId }`.
**Journal:** 1 journal, 2 entries.
**Reference:** `ref_type='OFFRAMP_ORDER'`, `ref_id=offramp_order.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `MONEYA_HOT_WALLET:GLOBAL` | `−(amount−fee)` | `Pledge USDC to YC, order <id>` |
| 2 | `YC_PAYABLE:GLOBAL` | `+(amount−fee)` | `Owe YC for payout, order <id>` |

Sum = 0 ✓. Fee stays in hot wallet (USDC), captured to revenue at
journal Y below.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 3 | (separate journal Z) `MONEYA_HOT_WALLET:GLOBAL` | `−fee` | `Capture offramp fee` |
| 4 | `FEE_REVENUE:GLOBAL` | `+fee` | `Offramp fee, order <id>` |

> **Decision (DEC-LED-2):** offramp fee is captured at Stage A.5 (when
> the user-side balance has settled) via a separate fee-capture journal
> Z. This keeps the SPL-confirmed journal A clean (matches on-chain 1:1)
> and the YC pledge journal A.5 clean (matches YC's order amount 1:1).

#### 4.3.3 Stage B: YC webhook `SETTLED`

**Trigger:** YC webhook says payout settled to user's MoMo.
**Journal:** 1 journal, 2 entries.
**Reference:** `ref_type='OFFRAMP_ORDER'`, `ref_id=offramp_order.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `YC_PAYABLE:GLOBAL` | `−(amount−fee)` | `YC settled to user, order <id>` |
| 2 | `MONEYA_HOT_WALLET:GLOBAL` | `+(amount−fee)` | `YC remits USDC, order <id>` |

> Wait — this is where the actual on-chain settlement between YC and
> MoneyA happens. In practice, YC settles USDC into our hot wallet
> on a batch schedule (daily or weekly), not per-order. So entry #2
> doesn't match a single SPL transaction; it's an accounting allocation.

**Revised:** entry #2 stays in `YC_PAYABLE` until batch settlement.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `YC_PAYABLE:GLOBAL` | `−(amount−fee)` | `YC delivered fiat to user, order <id>` |
| 2 | `SUSPENSE:GLOBAL` | `+(amount−fee)` | `Awaiting YC USDC batch settlement` |

Then on YC's batch USDC settlement (out-of-band, daily ops job):

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `SUSPENSE:GLOBAL` | `−batch_total` | `YC batch settlement <date>` |
| 2 | `MONEYA_HOT_WALLET:GLOBAL` | `+batch_total` | `YC USDC received <signature>` |

> **Decision (DEC-LED-3):** offramp settlement is a **3-stage ledger
> event** to model the YC batch settlement reality. Stage B (per-order)
> moves YC_PAYABLE → SUSPENSE; Stage C (batch) moves SUSPENSE →
> HOT_WALLET on the actual on-chain receipt.

#### 4.3.4 Offramp failed (YC `REJECTED` after payout submission)

**Trigger:** YC webhook `{ status: REJECTED }` after we already moved
the user's USDC to hot.
**Journal:** 2 journals — refund + reverse the YC pledge.
**Reference:** `ref_type='OFFRAMP_ORDER'`, `ref_id=offramp_order.id`.

Journal R1 (reverse YC pledge):

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `YC_PAYABLE:GLOBAL` | `−(amount−fee)` | `YC rejected, no payout` |
| 2 | `MONEYA_HOT_WALLET:GLOBAL` | `+(amount−fee)` | `Pledge released, order <id>` |

Journal R2 (refund SPL hot → user, after on-chain confirmation):

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `MONEYA_HOT_WALLET:GLOBAL` | `−amount_usdc` | `Refund offramp, order <id>` |
| 2 | `USER_WALLET:user` | `+amount_usdc` | `Offramp refund` |

Plus journal R3 (reverse fee capture if Stage A.5's fee journal Z fired):

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `FEE_REVENUE:GLOBAL` | `−fee` | `Reverse offramp fee, order <id>` |
| 2 | `MONEYA_HOT_WALLET:GLOBAL` | `+fee` | `Refund fee` |

### 4.4 Unclaimed transfer

#### 4.4.1 Stage A: PROCESSING → AWAITING_CLAIM (sender → escrow on-chain confirmed)

**Trigger:** Solana confirms `sender_wallet → MONEYA_ESCROW_WALLET`.
**Journal:** 1 journal, 2 entries.
**Reference:** `ref_type='TRANSFER'`, `ref_id=transfer.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `USER_WALLET:sender` | `−(amount + fee)` | `Unclaimed send to <phone>` |
| 2 | `MONEYA_ESCROW:GLOBAL` | `+(amount + fee)` | `Escrow hold, transfer <id>` |

Sum = 0 ✓

> Why hold the fee in escrow too: if the recipient never claims, we refund
> the **full** amount + fee to the sender. We only keep the fee on
> successful redemption (Stage B). Aligns with consumer fairness and
> regulator expectations.

#### 4.4.2 Stage B: AWAITING_CLAIM → COMPLETED (recipient redeemed)

**Trigger:** Solana confirms `MONEYA_ESCROW_WALLET → recipient_wallet`.
**Journal:** 1 journal, 3 entries.
**Reference:** `ref_type='TRANSFER'`, `ref_id=transfer.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `MONEYA_ESCROW:GLOBAL` | `−(amount + fee)` | `Escrow released, transfer <id>` |
| 2 | `USER_WALLET:recipient` | `+amount` | `P2P recv (claimed)` |
| 3 | `FEE_REVENUE:GLOBAL` | `+fee` | `P2P fee (claim redeemed)` |

Sum = `−(amount+fee) + amount + fee = 0` ✓

#### 4.4.3 Stage B′: AWAITING_CLAIM → EXPIRED_REFUNDED (7-day TTL)

**Trigger:** Solana confirms `MONEYA_ESCROW_WALLET → sender_wallet`.
**Journal:** 1 journal, 2 entries.
**Reference:** `ref_type='CLAIM_REFUND'`, `ref_id=transfer.id`.

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `MONEYA_ESCROW:GLOBAL` | `−(amount + fee)` | `Escrow expired, transfer <id>` |
| 2 | `USER_WALLET:sender` | `+(amount + fee)` | `Unclaimed refund, full incl fee` |

Sum = 0 ✓ — sender gets fee back.

#### 4.4.4 Stage B″: AWAITING_CLAIM → CANCELLED (sender cancelled)

Same as 4.4.3 but `ref_type='CLAIM_REFUND'`, memo notes manual cancel.

### 4.5 Reconciliation adjustment (operator-initiated)

**Trigger:** daily reconciliation (§7) finds a discrepancy and an
operator approves a correcting entry via the admin tool.
**Journal:** N entries depending on root cause.
**Reference:** `ref_type='RECONCILIATION_ADJ'`, `ref_id=incident_id`.

Two-account form (most common — discrepancy localised to one user vs
hot wallet):

| # | Account | Amount | Memo |
|---|---------|--------|------|
| 1 | `USER_WALLET:user` (or other) | `±delta` | `Recon adj <ticket>: <reason>` |
| 2 | `SUSPENSE:GLOBAL` | `∓delta` | `Recon adj <ticket>` |

Then a follow-up journal posts SUSPENSE → wherever the offsetting reality
landed (e.g., write-off to FEE_REVENUE if fees were over-counted).

Every reconciliation adjustment requires:
- 2-person sign-off (recorded in `audit.audit_log`)
- Linked incident ticket ID
- Memo describing root cause
- A retro action item (so the same recon doesn't recur)

---

## 5. Posting rules & atomicity

### 5.1 Single-transaction rule

All entries of a journal MUST be inserted inside one DB transaction.
The deferred constraint trigger
`app.ledger_journal_balance_check` validates `SUM(amount_usdc) = 0` per
`journal_id` at COMMIT. If imbalanced, the entire transaction rolls
back.

### 5.2 Posting order (within a transaction)

The application code SHOULD:

1. Generate `journal_id` (UUIDv4) at the start of the business operation.
2. Compute all entries from the journal template.
3. Insert all entries in the same `INSERT ... VALUES (...), (...), ...`
   statement (or a single multi-row insert).
4. Commit.

Avoid interleaving non-ledger writes and ledger inserts inside the same
transaction unless they are **strictly required** to be atomic with the
ledger post. Examples that ARE required:
- Updating `transfers.status` to terminal at the same instant the journal
  posts (so a reader can never observe `COMPLETED` without the matching
  ledger entries, or vice versa).
- Releasing an `escrow_holds` row on terminal transition.

### 5.3 Idempotency

`(ref_type, ref_id, journal_id)` is the natural dedupe key. The
service layer derives `journal_id` deterministically from the business
event when possible (e.g.,
`uuid_v5(namespace=NS_LEDGER, name='TRANSFER:'||transfer_id||':SETTLE')`).
This way, a worker re-running the same step writes the same journal_id
and triggers a unique-violation, preventing double-posting.

> **Action item for migration `0002_state_machine.sql`:** add unique
> index `(journal_id)` on the first entry per journal — or simpler,
> add a `app.posted_journals(journal_id PK, ref_type, ref_id, posted_at)`
> tracking table inserted-once per journal.

---

## 6. Balance derivation

### 6.1 Authoritative balance query

```sql
SELECT COALESCE(SUM(e.amount_usdc), 0) AS balance
  FROM app.ledger_entries e
  JOIN app.ledger_accounts a ON a.id = e.account_id
 WHERE a.kind = 'USER_WALLET'
   AND a.user_id = $1
   AND a.currency = 'USDC';
```

Backed by the convenience view `app.v_user_balances`
(`migrations/0001_init.sql:825-833`).

### 6.2 Available balance

`available = ledger_balance − active_escrow_holds`:

```sql
CREATE OR REPLACE FUNCTION app.user_available_balance(
    p_user_id UUID,
    p_currency TEXT DEFAULT 'USDC'
) RETURNS NUMERIC(20, 6)
LANGUAGE SQL STABLE AS $$
    SELECT
        COALESCE(b.balance, 0) -
        COALESCE((SELECT SUM(amount_usdc)
                    FROM app.escrow_holds
                   WHERE user_id = p_user_id
                     AND released_at IS NULL), 0)
    FROM app.v_user_balances b
    WHERE b.user_id = p_user_id
      AND b.currency = p_currency;
$$;
```

> **Action item for `0002_state_machine.sql`:** add this function
> alongside the transition allowlist trigger.

### 6.3 Caching policy

Balances are **never cached** at Phase 1. Every read goes to the ledger.
If read traffic outpaces this at Phase 2:
- Add `wallets.cached_balance` updated by trigger on
  `ledger_entries` insert.
- Or maintain a denormalised `app.account_balances` row per account,
  updated atomically.

But not before observed contention.

### 6.4 Negative-balance guard

A user's `USER_WALLET` ledger balance MUST NEVER be negative. Service
code enforces this at the pre-condition layer (transfer-state-machine.md
§4.2 #7); a periodic monitor query alerts P0 if it ever happens:

```sql
SELECT user_id, balance
  FROM app.v_user_balances
 WHERE balance < 0;
```

---

## 7. Reconciliation

Daily, against three sources of truth.

### 7.1 Solana on-chain vs ledger

For each `USER_WALLET` and `MONEYA_HOT_WALLET` and `MONEYA_ESCROW`:

```
on_chain_balance = getTokenAccountBalance(privy_address, USDC_mint)
ledger_balance   = SUM(ledger_entries.amount_usdc) for that account
```

Tolerance: 0 USDC. Any non-zero delta is a P1 alert.

For `USER_WALLET`, factor in active escrow:
```
expected_on_chain = ledger_balance  (escrow lives in MONEYA_ESCROW account, not user)
```

### 7.2 Yellow Card receivable / payable

Daily YC settlement report (CSV via SFTP at end of business day, T+1):

```
yc_collected_today = sum of fiat collected, converted to USDC at quote rate
yc_paid_out_today  = sum of fiat paid out

Expected:
  YC_RECEIVABLE delta today = +yc_collected_today − yc_settled_to_us
  YC_PAYABLE    delta today = +yc_paid_out_today  − yc_settled_to_yc
```

Mismatch > 0.1 USDC → P1 alert + ticket to ops.

### 7.3 Privy custody attestation

Privy provides an attestation API (`GET /v1/wallets/:id/balance`).
Daily compare ledger USER_WALLET balance vs Privy attestation. Mismatch →
P0 (could indicate Privy-side issue or our ledger drift).

### 7.4 Reconciliation job

Runs at 02:00 UTC daily (off-peak for African corridors):

1. Snapshot all account balances from ledger.
2. Fetch on-chain balances (Solana RPC).
3. Fetch YC settlement report.
4. Fetch Privy attestations.
5. Compute deltas.
6. Insert results into `audit.reconciliation_runs` (table to add in
   migration `0003_reconciliation.sql`).
7. Alert on any non-zero delta.

---

## 8. Invariants & DB-level enforcement

| ID | Invariant | Where enforced |
|----|-----------|----------------|
| L1 | Every journal sums to zero per currency. | `app.ledger_journal_balance_check` deferred trigger. |
| L2 | Ledger entries are append-only. | `app.deny_modification` BEFORE UPDATE OR DELETE trigger. |
| L3 | One USER_WALLET account per (user, currency). | `UNIQUE (kind, user_id, currency)` constraint. |
| L4 | Account `kind` is immutable post-insert. | App-level guard; consider DB trigger in `0002`. |
| L5 | `amount_usdc` precision matches numeric(20,6). | DB column type. |
| L6 | `currency` consistent within a journal. | App-level; consider trigger that rejects mixed-currency journals. |
| L7 | Every journal references a real business entity (`ref_id` exists in `ref_type`'s table). | App-level; consider per-`ref_type` FK. |
| L8 | A user's balance never goes negative. | App-level pre-condition + monitoring query. |

> **Migration `0002_state_machine.sql` — DONE** (see `docs/backend/migrations/0002_state_machine.sql`,
> tests in `migrations/tests/0002_ledger.test.sql`). Delivered: transition allowlist trigger,
> `app.user_available_balance(uuid, text)` (holds now carry a `currency`), `app.posted_journals`
> dedupe (entries must reference a registered journal), `transfers.parent_transfer_id`,
> `kind` immutability (L4), `app.v_ledger_imbalance`.
>
> **ADR 0001 D7 changes L1/L6:** user accounts are fiat-denominated; a journal may span
> currencies (conversion through `FX_POSITION` accounts) and must balance **per currency**;
> every entry's currency must equal its account's currency. The `'USDC'` column defaults are
> dropped — callers state the currency. `amount_usdc` is a historical column name: it holds an
> amount in the row's `currency`.

---

## 9. Worked examples

### 9.1 Alice sends Bob 100 USDC, fee 0.50 USDC

State: both already have `USER_WALLET` accounts with positive balances.

```
journal_id = J1
ref_type   = TRANSFER, ref_id = T1

Entry 1: USER_WALLET:alice           amount = -100.50
Entry 2: USER_WALLET:bob             amount = +100.00
Entry 3: FEE_REVENUE:GLOBAL          amount =   +0.50

SUM = -100.50 + 100.00 + 0.50 = 0.00 ✓
```

After commit:
- Alice's ledger balance: was 500.00 → now 399.50
- Bob's ledger balance: was 0.00 → now 100.00
- FEE_REVENUE: +0.50

### 9.2 Cécile tops up 25,000 XOF (~40.50 USDC, fee 0.40 USDC)

#### Journal J2 (YC webhook COLLECTED, ref ONRAMP_ORDER O1)

```
Entry 1: YC_RECEIVABLE:GLOBAL        amount = +40.50
Entry 2: SUSPENSE:GLOBAL             amount = -40.50
SUM = 0 ✓
```

#### Journal J3 (USDC credit confirmed, ref ONRAMP_ORDER O1)

```
Entry 1: YC_RECEIVABLE:GLOBAL        amount = -40.50
Entry 2: SUSPENSE:GLOBAL             amount = +40.50
SUM = 0 ✓
```

#### Journal J4 (hot wallet → user + fee, ref ONRAMP_ORDER O1)

```
Entry 1: MONEYA_HOT_WALLET:GLOBAL    amount = -40.50
Entry 2: USER_WALLET:cecile          amount = +40.10
Entry 3: FEE_REVENUE:GLOBAL          amount =  +0.40
SUM = 0 ✓
```

After all three commit:
- YC_RECEIVABLE: net 0 (cleared)
- SUSPENSE: net 0 (round-tripped)
- MONEYA_HOT_WALLET: −40.50
- Cécile: +40.10
- FEE_REVENUE: +0.40

### 9.3 Diallo sends 50 USDC to a non-MoneyA phone (+221 77...), fee 0.30, recipient never claims

#### Journal J5 (Stage A: escrow lock, ref TRANSFER T2)

```
Entry 1: USER_WALLET:diallo          amount = -50.30
Entry 2: MONEYA_ESCROW:GLOBAL        amount = +50.30
SUM = 0 ✓
```

#### Journal J6 (Stage B′: 7-day expiry refund, ref CLAIM_REFUND T2)

```
Entry 1: MONEYA_ESCROW:GLOBAL        amount = -50.30
Entry 2: USER_WALLET:diallo          amount = +50.30
SUM = 0 ✓
```

After J6: Diallo is whole; MoneyA earned 0 (correct — no service was
delivered).

---

## 10. Reporting queries

### 10.1 Daily fee revenue

```sql
SELECT date_trunc('day', posted_at) AS day,
       SUM(amount_usdc) AS fee_revenue_usdc
  FROM app.ledger_entries e
  JOIN app.ledger_accounts a ON a.id = e.account_id
 WHERE a.kind = 'FEE_REVENUE'
   AND e.posted_at >= now() - interval '30 days'
 GROUP BY 1
 ORDER BY 1 DESC;
```

### 10.2 In-flight obligations (ought to be small)

```sql
SELECT a.kind,
       COALESCE(SUM(e.amount_usdc), 0) AS balance
  FROM app.ledger_accounts a
  LEFT JOIN app.ledger_entries e ON e.account_id = a.id
 WHERE a.kind IN ('SUSPENSE', 'YC_RECEIVABLE', 'YC_PAYABLE',
                  'MONEYA_ESCROW')
 GROUP BY a.kind;
```

`SUSPENSE` should round-trip to 0 within minutes. `YC_RECEIVABLE` and
`YC_PAYABLE` clear daily on YC batch settlement. `MONEYA_ESCROW` should
be ≤ 7-day rolling unclaimed transfer volume.

### 10.3 Top users by volume (for compliance)

```sql
SELECT a.user_id,
       SUM(ABS(e.amount_usdc)) AS volume_usdc_30d
  FROM app.ledger_entries e
  JOIN app.ledger_accounts a ON a.id = e.account_id
 WHERE a.kind = 'USER_WALLET'
   AND e.posted_at >= now() - interval '30 days'
 GROUP BY a.user_id
 ORDER BY 2 DESC
 LIMIT 100;
```

### 10.4 Imbalance check (monitoring)

```sql
-- Should always return zero rows. Alert P0 if not.
CREATE OR REPLACE VIEW app.v_ledger_imbalance AS
SELECT journal_id,
       currency,
       SUM(amount_usdc) AS imbalance
  FROM app.ledger_entries
 GROUP BY journal_id, currency
HAVING SUM(amount_usdc) <> 0;
```

(Add to `0002_state_machine.sql` alongside the trigger.)

---

## 11. Phase 2 considerations

| Concern | Phase 1 | Phase 2 |
|---------|---------|---------|
| Multi-currency | USDC only | Add fiat-denominated USER_WALLET arms (XOF/NGN) for direct fiat balances; mixed-currency rules |
| Hot wallet sharding | Single global | Per-corridor (one per region/currency) |
| Escrow sharding | Single global | Per-currency or per-tier escrow |
| Balance cache | None | Denormalised `account_balances` updated by trigger |
| Ledger partitioning | Single table | Time-partition by `posted_at` (monthly), retain 7 yrs |
| Reconciliation cadence | Daily T+1 | Hourly intra-day for critical accounts (HOT_WALLET, ESCROW) |
| Cold storage | Hot wallet only | Sweep > $50K to cold; per-sweep ledger entries between HOT_WALLET and (new) `MONEYA_COLD_WALLET` account |
| Multi-region failover | Single AZ | Active-active across `af-south-1` + `eu-west-1` with conflict-free ledger via journal_id sharding |

---

## 12. Open questions

| # | Question | Owner | Decision deadline |
|---|----------|-------|--------------------|
| Q1 | Should we accrue fees per-journal or capture them at end-of-day in a single sweep? Current design: per-journal. | Finance | Phase 1 launch |
| Q2 | YC batch settlement cadence — daily, T+1, T+2? Affects `YC_RECEIVABLE` / `YC_PAYABLE` aging. | Partnerships | Pre-launch (depends on YC contract) |
| Q3 | Fee schedule per corridor — flat? percentage? hybrid? Currently mocked at 0.5% capped. | Product | Phase 1 launch |
| Q4 | Reconciliation tolerance — strict 0 or accept rounding drift up to 0.000001 USDC due to float-vs-decimal in YC reports? | Backend | Phase 1 launch |
| Q5 | Should reconciliation adjustments require 1-person or 2-person sign-off? Current = 2. | Compliance | Phase 1 launch |
| Q6 | Phase 2 multi-currency: model XOF/NGN as separate `currency` values per account, or as separate account `kind`s? | Backend | Phase 2 design |
| Q7 | Negative balance handling — block at service layer + monitor, or also enforce via DB CHECK (would prevent provisioning user_wallet at 0)? | Backend | Phase 1 launch |
| Q8 | Idempotent journal_id derivation — UUIDv5 hash of business event vs random UUIDv4 + dedupe table? Current = UUIDv5 + tracking table. | Backend | Phase 1 implementation |

---

**End of ledger spec.** Companion docs to author next:
- `docs/backend/webhooks.md` — provider-specific contract details (HMAC, dedupe, replay tooling)
- `docs/backend/backlog.md` — Phase 1 ticketed implementation order
