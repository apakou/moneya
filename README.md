# MoneyA

**Say it. We send it.** MoneyA moves money **easily and cheaply between francophone and anglophone Africa**: a sender in Abidjan, Lomé or Dakar pays in CFA francs from their mobile money, and the recipient in Accra, Lagos or Nairobi receives cedis, naira or shillings on theirs. The app speaks French and English, and **USDC on Stellar** does the cross-currency settlement behind the scenes.

> **Status: pre-launch.** The app, the API, the ledger and the top-up / cash-out flows work end to end against a *simulated* payment provider and a local database. The pieces a cross-currency transfer is built from exist (per-currency ledger, FX accounts, cross-currency quotes), but **the cross-border send itself is not built yet**. The Stellar settlement layer is built and unit-tested but **has not been run against testnet or mainnet**, and no real payment provider is connected. This README says plainly what is done, what is not, and what we are asking Stellar for. Last verified: 2026-10-11.

---

## Contents

1. [The problem and our approach](#1-the-problem-and-our-approach)
2. [What already exists](#2-what-already-exists)
3. [What does not exist yet](#3-what-does-not-exist-yet)
4. [How it works](#4-how-it-works)
5. [The goal](#5-the-goal)
6. [Our ask from Stellar](#6-our-ask-from-stellar)
7. [Roadmap](#7-roadmap)
8. [Risks](#8-risks)
9. [Run it](#9-run-it)
10. [Repository map and documentation](#10-repository-map-and-documentation)

---

## 1. The problem and our approach

**The problem.** Africa's francophone and anglophone countries sit side by side but are poorly connected financially:

- The francophone zones share the **CFA franc** (XOF in West Africa, XAF in Central Africa); the anglophone markets each have their own currency (GHS, NGN, KES, …).
- **Mobile-money networks rarely interoperate across borders.** A Wave or Orange Money user in Côte d'Ivoire cannot simply pay an MTN MoMo user in Ghana.
- Money between the two worlds usually travels through **intermediaries and a hub currency (USD or EUR)**, which means several fees, a double conversion and slow settlement.
- There is a **language barrier**: most money apps are built for one language and one market.

For traders, families and small businesses on corridors like Côte d'Ivoire ⇄ Ghana, Togo ⇄ Ghana or Benin ⇄ Nigeria, this makes a simple payment slow, costly and confusing.

**MoneyA's approach.**

- **One cross-currency bridge.** Money leaves the sender's mobile money in their currency, is settled in USDC on Stellar, and arrives in the recipient's mobile money in theirs. Instead of a chain of banks and correspondents, there is one fast, auditable settlement leg and two local cash-in/cash-out legs.
- **Mobile-money native and bilingual.** People pay in and out of the accounts they already use, in French or English.
- **Users never see crypto.** They see their own currency, the exact amount the recipient gets and one all-in fee. There is no wallet, address, gas fee or stablecoin anywhere in the UI, the API, the notifications or the receipts. This is enforced by automated checks, not by convention.
- **Pooled custody, per-user ledger.** Users hold balances in a double-entry ledger in their own currency; the chain is only touched when money enters or leaves the system. Rates and fees are locked in a quote before the user confirms.
- **Phone-first.** Sign-up is phone number + one-time code + passcode (biometrics optional). Voice-first sending ("say it, we send it") is the longer-term vision; it is not built yet.

**Markets in the code today:** Ghana (GHS), Nigeria (NGN), Kenya (KES), the WAEMU countries (XOF: Togo, Senegal, Côte d'Ivoire, Mali, Burkina Faso, Benin) and the CEMAC zone (XAF). **Proposed first corridor pair:** Ghana (GHS) ⇄ Côte d'Ivoire / Togo (XOF) — neighbouring markets with heavy trade, one English-speaking and one French-speaking. *To be confirmed by the team; ADR 0001 currently names Ghana alone as the first market.*

---

## 2. What already exists

Everything below was built and run in this repository. "Tests" are automated tests in the repo; "device" means exercised by hand on a physical Pixel 7 against a local API and PostgreSQL.

### Mobile app (Flutter, English and French)

| Area | What works | Evidence |
|------|------------|----------|
| Onboarding, splash, language | Onboarding pages, EN/FR switch, persisted preferences | device |
| Sign-up and login | Phone number + country picker, one-time code (6 digits), passcode set and confirm, optional biometrics, returning users go straight in, separate Login screen | tests + device |
| Home | Real balance from the server in the selected currency (total across currencies, shown with "≈" when converted), recent transactions, currency switcher (XOF, XAF, NGN, GHS, KES), pull-to-refresh | tests + device |
| Transactions | Full history from the API with paging, filters (sent, received, succeeded, pending, failed), month grouping, detail screen with fee, total, method and reference | tests + device |
| Top-up (Load money) | Pick provider, amount, mobile-money number → live quote with all-in fee and a countdown → step-up with passcode → order → status tracking → balance updates | tests + device (simulated provider) |
| Cash-out (Withdraw) | Same quote/step-up/order/status flow, insufficient-balance guard | tests (device for top-up only) |
| Profile, favorites, notifications sheet | UI in place; profile reads the signed-in session | tests |
| Quality | `flutter analyze` clean, **214 automated tests**, a copy linter that fails the build if user-facing text or assets mention stablecoins or crypto | CI definition |

### Backend (NestJS, TypeScript, PostgreSQL)

| Area | What works | Evidence |
|------|------------|----------|
| Auth | Phone one-time codes (hashed, rate-limited, lockout), short-lived JWT access tokens, rotating refresh tokens with reuse detection, Argon2id passcode with lockout, single-use step-up token bound to user and device for every money movement | tests on real PostgreSQL, including race tests |
| Ledger | Double-entry ledger with database-enforced balance, idempotent journals, no-overdraw under concurrency (10 parallel spends from 100 → exactly 3 succeed), per-currency accounts, FX accounts for conversions | tests on real PostgreSQL |
| Top-up and cash-out | Quotes (fee rounds up, settlement rounds down, per-currency precision), orders with `Idempotency-Key` replay, signature-verified provider webhooks with dedupe, a polling resumer for lost webhooks, failed payout → exactly one refund | tests on real PostgreSQL |
| Account API | `GET /v1/users/me`, `GET /v1/wallet` (balance, spendable balance, currency equivalent), `GET /v1/transactions` (keyset pagination) | tests on real PostgreSQL + device |
| Cross-currency building blocks | Per-currency user balances; FX accounts in the ledger so cross-currency journals still balance; quote math that prices a payout in a *different* currency than the one held (for example 100 GHS → 3,812 XOF at the sample rates, fee rounded up and payout rounded down to the destination's precision); the API accepts a separate `payout_currency`; balances can be viewed as an equivalent in any supported currency | unit tests for the quote and conversion math; the ledger tests on PostgreSQL |
| Stablecoin invisibility | Every API response is checked in tests and (outside production) at runtime for chain vocabulary, Stellar addresses and transaction hashes; the OpenAPI contract is linted for the same | tests |
| Database | 7 append-only migrations, a SQL test suite for the ledger, a Supabase project with the schema applied (staging) | tests + owner-reported |
| Quality | **171 automated tests**, lint and typecheck clean | local run |

### Stellar layer (`@moneya/chain`)

A `ChainAdapter` interface and a `StellarAdapter` built on `@stellar/stellar-sdk`: building and signing payments, deterministic transaction hashes computed before submission, time bounds, memos, fee-bump envelopes, 6-decimal ledger ↔ 7-decimal Stellar amount conversion, address validation and failover configuration. Also a database schema for chain accounts, persisted transactions (hash and signed envelope stored *before* submit), stream cursors and inbound deposits with dedupe. 61 tests run against the real Stellar SDK offline (real keys, real signatures and hashes).

### Design documentation

A full architecture, a ledger specification, a transfer state machine, a webhook design, an ADR for pooled custody and a ticketed plan with acceptance criteria live in [`docs/backend`](docs/backend). The plan's status table is the most detailed and honest record of what is verified and what is not.

---

## 3. What does not exist yet

We would rather say this up front than have a reviewer discover it:

| Gap | Detail |
|-----|--------|
| **Stellar network half is unproven** | Submit, confirm, deposit-stream and fee-bump code exists but has **not been run against testnet or mainnet**. The testnet spike script is written (`pnpm stl00`) and is the first thing the grant work does. |
| **No real payment provider** | Top-ups and cash-outs run against a deterministic simulator. Yellow Card is the intended primary provider, but its Stellar support and corridor coverage is **not yet confirmed in writing**; a licensed SEP-24 anchor is the fallback. |
| **No treasury, signer or deposit detection in production** | Treasury account setup, a KMS/HSM-backed signer, the submit worker and the inbound-deposit matcher are specified and ticketed, not built. In production the API refuses to start the simulator, so top-ups cannot complete there yet. |
| **The cross-border send is not built** | This is the core of the product. The send flow in the app exists as screens only; the backend has no endpoint that takes a sender's CFA balance and pays a recipient's mobile money in cedis, naira or shillings. The app's cash-out always uses the same currency in and out, and our HTTP tests only exercise same-currency orders; the cross-currency quote and ledger pieces are unit-tested but **not yet exercised end to end**. Our design record (ADR 0001) deferred cross-currency sends out of the first release; that scope has to be reversed, because this *is* the product. |
| **No send to non-users (claim links)** | Sending to a phone number that has no MoneyA account yet (claim link by SMS) is designed, not built. |
| **No two-sided liquidity or partners** | A cross-border corridor needs a cash-in partner on one side and a cash-out partner on the other, and local-currency liquidity on both. None is contracted. |
| **No KYC** | Document and selfie capture screens exist; upload, the identity-verification provider and tier limits are not wired. |
| **No real SMS provider** | One-time codes use a fake provider in development. An HTTP SMS adapter with failover exists and is tested against a local server, but no vendor is connected. |
| **No push notifications, no realtime channel, no voice** | Designed, not built. |
| **Rates are sample rates** | Currency conversion uses fixed development rates until a real rate source is set. |
| **Not licensed, not audited** | Legal posture in both launch countries (VASP / money-transmitter, and the WAEMU rules for the CFA side) is to be confirmed before any real money moves. No external security audit yet. |
| **No users, no revenue** | This is pre-launch. |
| **Continuous integration has not been observed green on GitHub** | The workflow (copy lint, backend tests on PostgreSQL, migration checks, Flutter analyze and tests) is defined; we pass the same checks locally. |

---

## 4. How it works

```mermaid
flowchart LR
  subgraph Phone["MoneyA app (Flutter)"]
    UI["Fiat-only UI<br/>EN / FR"]
  end
  subgraph API["API (NestJS)"]
    AUTH["Auth: OTP, passcode,<br/>step-up tokens"]
    ORD["Quotes + orders<br/>(idempotent)"]
    LED[("Ledger<br/>PostgreSQL<br/>per-user, per-currency")]
    ACC["Account API<br/>balance, history"]
  end
  subgraph Rails["Local rails"]
    MM["Mobile money<br/>provider / anchor"]
  end
  subgraph Stellar["Stellar (to build + prove)"]
    TRE["Treasury: cold + hot,<br/>KMS signer, multisig"]
    SUB["Submit worker<br/>channel accounts, fee-bump"]
    STR["Deposit stream<br/>cursor + dedupe"]
  end
  UI --> AUTH
  UI --> ORD
  UI --> ACC
  ORD <--> LED
  ACC --> LED
  ORD <--> MM
  MM -. "USDC on Stellar" .-> STR
  STR --> LED
  LED --> SUB --> TRE
  TRE -. "USDC on Stellar" .-> MM
```

**Cross-border send** (the product; to be built). The sender picks a recipient and a destination country, sees one quote ("you pay 10,000 XOF, they receive about 254 GHS, fee included, valid for 60 seconds"), and confirms with their passcode. The sender's balance is debited in XOF, value moves through the Stellar settlement leg, and the recipient's mobile money is paid out in GHS. If any step fails, the sender is refunded exactly once. Where the recipient already has a MoneyA account the money can land in their balance instead of a mobile-money payout.

**Top-up and cash-out** (built, simulated provider). Top-up: quote, passcode, pay from mobile money, the ledger credits the balance exactly once when the provider confirms. Cash-out: quote, passcode, the ledger holds the amount, the provider pays out, the hold settles; a failed payout refunds exactly once. A cross-border send reuses these two legs with a currency conversion in between.

**Same-currency send between MoneyA users** (planned). A ledger-only transfer: no chain transaction, instant, no network fee.

**Where Stellar sits.** USDC on Stellar is the bridge between the two local currencies: value enters as one currency, is held and moved as USDC, and leaves as the other. It is also how value moves between the treasury and the ramp providers, and how we reconcile that the ledger matches what is on-chain. Design choices that follow Stellar's strengths:

- one pooled treasury (cold + hot accounts, native multisig thresholds) instead of an account and trustline per user;
- channel accounts so parallel payouts do not collide on a single sequence number;
- fee-bump transactions so the treasury, not the user, pays network fees;
- transaction hash and signed envelope persisted before submit, so a retry resubmits the same envelope and is idempotent;
- a payments stream with a stored cursor and `(tx_hash, op_index)` dedupe for inbound deposits, with a memo per order and a suspense account for anything that does not match;
- SEP-24 / SEP-10 / SEP-38 as the fallback integration with a licensed anchor.

Details: [`docs/backend/stellar-mvp-plan.md`](docs/backend/stellar-mvp-plan.md) and [ADR 0001](docs/backend/adr/0001-stellar-pooled-custody.md).

---

## 5. The goal

**Our main purpose: make it easy and cheap to move money between francophone and anglophone Africa.** "Easy" means a sender needs only a phone number, their mobile money and a passcode, in their own language, and sees exactly what the recipient will get before confirming. "Cheap" means the all-in cost to the sender (fee plus the exchange-rate margin) is lower than what people pay today on the same corridor. We will measure it against the incumbents on each corridor and publish the comparison rather than assert it.

**Near term (the MVP).** One corridor pair, live on Stellar **mainnet** with real USDC behind low limits: a user in a francophone country sends from their mobile money and a recipient in an anglophone country receives on theirs, and the reverse; with sign-up and identity checks, history, status updates, refunds when something fails, and a reconciliation job that proves the ledger equals the chain.

The MVP is done when:

- the send works in both directions on the launch corridor with real funds, with the rate and fee shown up front;
- ledger-to-chain reconciliation is green for 7 consecutive days on staging and 3 on mainnet;
- every chain submit stays correct under injected failures (duplicate submits, timeouts, stream gaps, sequence errors, provider webhook replays);
- signer rotation and a treasury sweep have been rehearsed;
- legal sign-off for the launch jurisdictions is on file;
- the measured all-in cost on the corridor is published next to the alternatives.

**Medium term (the startup).** Add corridors in both directions (Ghana, Nigeria and Kenya on one side; the WAEMU and CEMAC zones on the other), a second provider per side for resilience and better rates, same-currency and merchant payments, and voice-first sending in local languages. Revenue comes from an all-in fee plus a small, disclosed exchange margin (the current pricing configuration uses a 1.5 % fee as a placeholder; real pricing follows provider quotes). We will track activation (sign-up → first send), repeat sends per user, all-in cost against incumbents, time to delivery, failure and refund rates, and reconciliation health.

---

## 6. Our ask from Stellar

We are asking for support to take MoneyA from "works against a simulator" to "moves real money across the francophone–anglophone border on Stellar, in one corridor pair", which is the step that turns a prototype into a company. We have put the technical risk, the effort and the deliverables below so the ask can be evaluated against something concrete.

### 6.1 Funding, in milestone-based tranches

Our own estimate of the remaining engineering work in the existing plan is roughly **100 ideal-engineer-days** out of ~150 (about a third is done). **That plan deferred cross-currency sends, which are the heart of the product, so the cross-border work is additional and not yet sized**; we are sizing it now and expect it to add several weeks. With two backend engineers and one Flutter engineer, the existing scope alone is about 8 to 10 weeks to a limited launch. These are estimates built with the same sizing method as the backlog, not commitments.

| Tranche | Scope | Verifiable deliverable | Plan tickets |
|---------|-------|------------------------|--------------|
| **1. Prove Stellar** | Run the testnet spike; treasury setup scripts (cold, hot, deposit, channel accounts, multisig, trustlines); KMS/HSM-backed signer with policy limits and an audit log; submit worker with persisted hash + envelope, retries and fee-bump; deposit stream with cursor, catch-up and suspense handling; chain-error mapping; ops view | A public testnet demo: an on-chain USDC deposit credits a ledger balance exactly once; a payout is submitted, confirmed and survives injected failures; a reconciliation report shows ledger = chain | STL-00 to STL-06, INV-05 |
| **2. The cross-border corridor** | Contract a cash-in and cash-out partner (or SEP-24 anchor) **on each side** of the launch corridor; the cross-currency send end to end (quote with the recipient's amount, ledger and state machine, payout in the destination currency, refund path, per-corridor limits and compliance checks); send screens in the app with destination country, recipient amount and fee up front; identity verification and tier limits; real SMS provider; notifications and realtime status; reconciliation with alerts | A closed beta where invited users send from a francophone country to an anglophone one and back, with the rate and fee shown up front, on infrastructure ready for mainnet | RMP-00, M3, M9, M10, M11, APP-02 and APP-07 to APP-09, plus new cross-currency send tickets (not yet in the plan) |
| **3. Mainnet launch** | Mainnet dry run with small real amounts; load and chaos tests; key ceremony and signer rotation drill; alerts and runbooks; external security review of the signing and settlement path; store submission; staged rollout with low limits; measure and publish the all-in cost against incumbents on the corridor | Live on mainnet on the launch corridor with daily and per-user limits, the reconciliation and monitoring evidence, and a public post-launch report including the cost comparison | HRD-01 to HRD-06 |

> **Budget figure:** *to be filled in by the team before submission* (engineering rate × the effort above, plus the external security review, KYC and SMS costs for the beta, treasury float and local-currency liquidity on both sides of the corridor for the dry run, and legal/licensing advice for the two launch countries). Tranches are released against the verifiable deliverables in the table.

### 6.2 Beyond funding

These unblock the project as much as money does:

1. **Confirm Stellar support at ramp providers, on both sides of a corridor.** Written confirmation from Yellow Card (or an introduction to an alternative) that its payments API accepts and pays out USDC on Stellar, with sandbox access, for the anglophone side (Ghana, Nigeria, Kenya). Yellow Card's published coverage does not include the CFA-franc zones, so we also need a partner for **XOF and XAF** cash-in and cash-out. This is the single biggest external dependency (ticket RMP-00).
2. **Introductions to Stellar-native anchors and mobile-money partners** in both language zones (Ghana, Nigeria, Kenya, and the WAEMU/CEMAC countries), including SEP-24 / SEP-31 anchors, so we are not dependent on one provider.
3. **Cross-currency liquidity and treasury guidance:** how to source and hedge local-currency liquidity for XOF, XAF, GHS, NGN and KES against USDC, how to size and fund a treasury, hot-wallet caps, and sweep and rebalancing practice. Our margin and our ability to be cheaper depend on this.
4. **Technical review** of our design by people who run Stellar in production: channel accounts, fee-bump, resubmission rules, deposit stream and reconciliation, and which KMS / custody options support Ed25519 signing for Stellar.
5. **Security audit support or credits** for the signing and settlement path before we hold real funds.
6. **Regulatory orientation** for both ends of the launch corridor (for example Ghana and Côte d'Ivoire or Togo, and later Nigeria, Kenya and the CEMAC zone): what licence or partnership structure is expected for a cross-border service in this model, including the WAEMU central-bank rules.
7. **Ecosystem visibility and early users:** inclusion in Stellar ecosystem channels and help finding beta testers and partner merchants once we are live.

### 6.3 What the grant changes

Without it, MoneyA stays a well-tested prototype that settles against a simulator. With it, we have a live Stellar-settled cross-border product on a real francophone–anglophone corridor, real data on cost, speed and failure rates against the incumbents, and a public record of the design and its results, which is what we need to raise a seed round and become a company. We will publish the testnet demo, the design notes and the post-launch report openly so other teams building on Stellar can reuse the pieces (the chain adapter, the deposit-stream consumer, the reconciliation approach).

---

## 7. Roadmap

Weeks assume the staffing above and count from the start of funding.

| Weeks | Phase | Outcome |
|-------|-------|---------|
| 1–3 | **Prove Stellar** (tranche 1) | Testnet spike passes; treasury, signer, submit worker and deposit stream running on testnet; provider confirmation received |
| 3–8 | **The cross-border corridor** (tranche 2) | Partners on both sides integrated; cross-currency send end to end; KYC; notifications; closed beta. *Timing is indicative: the cross-border work is not yet sized.* |
| 8–11 | **Mainnet launch** (tranche 3) | Dry run, hardening, security review, store submission, staged rollout with low limits |
| After launch | **Grow** | More corridors in both directions (Nigeria, Kenya, the CEMAC zone); a second provider per side; same-currency and merchant payments; voice-first sending |

---

## 8. Risks

| Risk | Why it matters | What we do |
|------|----------------|------------|
| No partner on one side of the corridor, or no Stellar support at a provider | Blocks real cash-in or cash-out; a corridor needs both ends | Confirm in week 0 (RMP-00), for both sides; the provider interface is abstract and already has a contract test suite; SEP-24 anchor as fallback, budgeted as contingency |
| Key compromise on the treasury | Loss of funds | KMS/HSM signer, hot-wallet cap of about a day's volume, multisig thresholds, signing policy limits and an append-only audit log, a rehearsed rotation drill, external review |
| Missed or double-credited deposits | Wrong balances | Stream cursor with catch-up, `(tx_hash, op_index)` dedupe, suspense account for mismatches, reconciliation every few minutes |
| Sequence-number collisions and stuck submits | Failed payouts | Channel accounts, persisted envelopes, time bounds, resubmit-the-same-envelope rule |
| Regulatory blocker | Cannot launch regardless of engineering | Legal posture is a week-0 item; low limits and tiering; sign-off before the mainnet dry run |
| Treasury FX exposure | Local-currency balances are fixed while rates move | Balances are held in the user's currency and converted at a locked quote; exposure is priced into the spread and bounded by limits |
| Small team | Delivery risk | Narrow first scope (one corridor), the plan's contingency, and tickets with acceptance criteria |

---

## 9. Run it

You need Flutter (a recent stable release), Node 22 with pnpm, and Docker for a local PostgreSQL.

**Database (throwaway, local):**

```bash
docker run -d --name moneya-dev-pg -e POSTGRES_PASSWORD=postgres -p 127.0.0.1:54330:5432 postgres:16-alpine
export PGPASSWORD=postgres; H="-h 127.0.0.1 -p 54330 -U postgres"
psql $H -c "create database moneya_dev"
psql $H -d moneya_dev -c "create schema auth; create function auth.uid() returns uuid language sql as 'select null::uuid';"
for f in docs/backend/migrations/*.sql; do psql $H -d moneya_dev -v ON_ERROR_STOP=1 -1 -q -f "$f"; done
```

**API:**

```bash
cd backend && pnpm install && pnpm build
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54330/moneya_dev \
NODE_ENV=development SMS_PROVIDER=fake RAMP_PROVIDER=simulated FAKE_SMS_LOG=true \
RAMP_RESUMER_INTERVAL_MS=3000 PORT=3000 node apps/api/dist/main.js
```

One-time codes are printed in the API console (`[fake-sms]`). The resumer setting lets simulated top-ups settle, because the simulator sends no webhooks.

**App (Android, dev flavor):**

```bash
adb reverse tcp:3000 tcp:3000
flutter run --flavor dev --dart-define=API_BASE_URL=http://localhost:3000
```

Always pass `--flavor dev` (plain `flutter run` builds every flavor) and `API_BASE_URL` (without it every request fails).

**Tests and checks:**

```bash
flutter analyze && flutter test
python3 scripts/lint_copy.py                         # stablecoin-invisibility lint
cd backend && pnpm lint && pnpm typecheck
TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54330/moneya_test \
LEDGER_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54330/moneya_test pnpm test
```

(Create `moneya_test` the same way as `moneya_dev`. Without the database variables the PostgreSQL tests are skipped, not faked.)

---

## 10. Repository map and documentation

```
lib/                     Flutter app (feature-first: auth, home, ramp, account, transfer, …)
test/                    App tests
backend/
  apps/api               NestJS API (auth, ramp, account, health)
  packages/chain         ChainAdapter + Stellar implementation
  packages/ledger        Double-entry ledger service and journal templates
  packages/ramp          Provider interface, simulator, contract test suite
  packages/invisibility  Stablecoin-invisibility guard and contract lint
docs/backend/            Architecture, ledger, state machine, webhooks, OpenAPI, migrations, ADR, plan
scripts/                 Copy lint, migration sync, run helpers
supabase/                Supabase config and generated migrations
```

Start with:

- [`docs/backend/stellar-mvp-plan.md`](docs/backend/stellar-mvp-plan.md): the plan, status table with evidence, risks and acceptance criteria
- [`docs/backend/adr/0001-stellar-pooled-custody.md`](docs/backend/adr/0001-stellar-pooled-custody.md): the settlement, custody and balance-currency decisions
- [`docs/backend/openapi.yaml`](docs/backend/openapi.yaml): the fiat-only API contract
- [`docs/backend/ledger.md`](docs/backend/ledger.md) and [`transfer-state-machine.md`](docs/backend/transfer-state-machine.md)
- [`docs/backend/supabase.md`](docs/backend/supabase.md): database runbook
