# MoneyA — Stellar MVP Implementation Plan

> **Status:** Proposal v1 — supersedes the Solana/Privy assumptions in
> [`architecture.md`](./architecture.md), [`ledger.md`](./ledger.md) and
> [`backlog.md`](./backlog.md). Those docs stay the reference for everything
> that is **not** chain-specific (auth, KYC, ledger, FSM, webhooks, compliance).
> **Decision:** Stellar replaces Solana as the settlement chain.
> **Sizes** are estimates in ideal-engineer-days (IED), same unit as the backlog.

## 0. Status snapshot

**Done and verified in the authoring environment** (commands were run; results below):

| Ticket | What exists | Evidence |
|--------|-------------|----------|
| FND-01 (partial) | `backend/` pnpm monorepo: NestJS API with `/health`, strict TS, ESLint, Prettier, Jest | `pnpm lint/typecheck/test/build` green; built API answered `GET /health` → `{"status":"ok"}` |
| STL-01 (offline part) | `@moneya/chain`: `ChainAdapter`, `StellarAdapter` build/sign/hash/timebounds/memo/fee-bump, 6↔7 dp amount conversion, address validation, config | 61 backend tests with the real Stellar SDK (real keys, signatures, hashes) |
| DB-01 | `migrations/0003_stellar_chain.sql` | Applied on PostgreSQL 16 after `0001`: single transaction, idempotent re-apply, and constraint tests (dedupe, suspense/matched checks) |
| INV-01 | OpenAPI response contract lint (+ the contract migrated to fiat-only) | `contract.spec.ts`; it caught a leftover "Wallet" description during development |
| INV-02 | `scripts/lint_copy.py` (+ 7 self-tests) over `.arb`, Dart string literals and asset names; wired in CI | passes on the repo; fails on a planted `Send USDC` |
| INV-03 (core) | `@moneya/invisibility` guard + `InvisibilityInterceptor` (non-production) | unit + e2e tests; the e2e suite grows with every endpoint |
| APP-00 | Client DTOs/copy/assets moved to the fiat-only contract (V1–V5 fixed) | `flutter analyze`: only the 1 pre-existing info; `flutter test`: 119 pass (117 before + 2 new) |
| M1 (auth, logic + API) | OTP request/verify (HMAC'd codes, 3/10 min rate limit, 5-failure lockout), HS256 access JWT + opaque rotating refresh tokens with family reuse-revocation, Argon2id passcode (weak-code rejection, lockout), step-up `txn_token` (60 s, single-use, bound to user+device) + `AuthGuard`/`TxnTokenGuard`; `0004_auth_sessions.sql` | 79 backend tests (18 new e2e in `auth.e2e.spec.ts`, response guard active); 0004 applied twice on PostgreSQL 16 after `0001`+`0003`. **Storage is in-memory and SMS is a fake**: the app refuses to boot in production until a Postgres `AuthStore` and a real SMS adapter exist |
| M2 (LDG-01) | `0002_state_machine.sql`: transition allowlist, `posted_journals` dedupe (enforced), per-currency balance + entry/account currency check (D7), `kind` immutability, `user_available_balance`, `parent_transfer_id`, `v_ledger_imbalance` | Applied with `-1` and re-applied on PostgreSQL 16 after 0001; `migrations/tests/0002_ledger.test.sql` (unbalanced, unregistered, duplicate, currency mismatch, cross-currency, forbidden transition) passes; wired into CI |
| STL-00 (script only) | `backend/scripts/stl00-testnet-spike.ts` (`pnpm stl00`): friendbot-funded throwaway accounts and its own test asset; checks submit, inner-hash `getTx`, idempotent resubmit, `tx_bad_seq` retry, 10 parallel channel accounts, payment stream dedupe | Typechecks and starts; **NOT RUN against testnet** — the sandbox's network policy blocks `horizon-testnet.stellar.org` and `friendbot.stellar.org` (fails at DNS) |
| CI | `.github/workflows/ci.yml` (copy-lint, backend, migrations, app) | **YAML parses; has NOT run on GitHub yet** |

**Not verifiable here, implemented but unproven:** the network half of `StellarAdapter`
(`submit`, `getTx`, `getSequence`, `streamPayments`, failover, `opIndexFromOperationId`).
Horizon, Friendbot and Soroban RPC are unreachable from the authoring sandbox, so
**STL-00 (testnet spike) must be run on a machine with internet access** — it is the next step for it.

**Blocked on the owner or an external party** (nothing in this repo can unblock these):

| Item | Waiting on |
|------|------------|
| RMP-00 | Yellow Card written answer (Stellar API support, corridors, sandbox keys) |
| DEC-01 sign-offs: D1, D3, D4, D5 | Owner (custody model, launch corridor, key custody, licensing) |
| **D7** (new) | Owner/finance — see §2 |
| STL-00 | Running the spike with network access |
| FND-02 Supabase staging, Sentry | Accounts/keys |
| STL-02..06, M5–M8 | RMP-00 + D1 + D4 (+ D7 for ledger/quotes) |

**Unblocked, not started** (can proceed without any external input): M1 auth with a fake SMS provider
(real Twilio keys only needed to go live), UI work for APP-01..09 against the contract, `0002_state_machine.sql`
(M2 — but its *account currency* depends on D7).

---

---

## 1. What "ready MVP" means

A real user, on a real phone, in the launch corridor(s) can:

1. Sign up (phone OTP → passcode → KYC tier 1).
2. **Top up** with mobile money and see a balance.
3. **Send** to another MoneyA user, or to a phone number that is not yet a user (claim link by SMS).
4. **Cash out** to mobile money.
5. See history, receive push/realtime status, and get a refund when something fails.

It runs on Stellar **mainnet** with real USDC, behind limits, with monitoring
and a reconciliation job that proves ledger = chain.

**Out of scope for the MVP:** voice intent, cross-corridor (3-leg) sends,
merchant APIs, non-custodial wallets, Soroban contracts, SEP-31 direct payouts,
AWS migration, tier-2 KYC.

### 1.1 Non-negotiable: users must never know stablecoins are used

MoneyA users see **money in their own currency**, a **"MoneyA balance"** and
**mobile money**. Nothing else. This applies to **every** surface:

| Surface | Rule |
|---------|------|
| UI copy FR/EN (`lib/l10n/*.arb`) | No "USDC", "USD Coin", "stablecoin", "crypto", "blockchain", "Stellar", "XLM", "wallet", "gas", "hash", "address". Say "balance" / "solde MoneyA". |
| Rates and fees | One all-in fiat→fiat rate and one all-in fee. Never `XOF/USDC`, never a network fee line. |
| API contract | Fiat-only. No `amount_usdc`, `fee_usdc`, `solana_signature`/tx hash, `chain`, `address`. Done in `openapi.yaml` (this plan's change set). |
| Enums (status, failure reasons) | Never rendered; the client maps them to localized copy. Chain failures collapse to `SERVICE_UNAVAILABLE`. |
| Notifications, SMS claim links, receipts/PDF | Templates reviewed against the forbidden-term list. Say "money". |
| Errors | Chain errors (bad sequence, trustline, low XLM, timeout) → generic localized copy; no chain vocabulary in `ApiError.title/detail`. |
| Imagery | No USD Coin / crypto art (onboarding, store screenshots, marketing). |
| Logs, analytics, crash reports | No chain terms in client telemetry; support uses **our** reference id, never a chain hash. |
| Support | Agents see a support reference id; chain hashes live only in the internal ops console. |

**Honesty boundary:** hiding it from the *UX* is not hiding it from the *legal
documents*. Terms of Service / privacy notice and regulator filings must describe
truthfully how funds are held and settled; counsel decides the wording (part of D5).

**Violations found in the repo today (audit of `lib/`):**

| # | Where | Problem | Fix (ticket) |
|---|-------|---------|--------------|
| V1 | `lib/features/transfer/presentation/screens/payment_confirm_screen.dart` (≈ l.238–245), `transfer_dtos.dart` | The client sends the **local-currency amount in a field named `amount_usdc`** ("W3 scope… backend dev env accepts this"). Beyond leaking the concept, this is a **money-correctness bug**: 5 000 XOF would be read as 5 000 USDC. | APP-00 |
| V2 | `lib/features/onboarding/presentation/pages/send_money_page.dart` + `assets/images/USD Coin_3D.png/.svg` | Onboarding hero shows a **USD Coin** illustration. | APP-00 |
| V3 | `fundingProviderMoneyaWallet` in `app_en.arb`/`app_fr.arb`, `funding_provider.dart`; `withdrawFailedBodySuffix`; `payment_failed_screen.dart` l.73–78 | "MoneyA Wallet" / "your wallet" — the word the skills forbid. | APP-00 |
| V4 | `transfer_dtos.dart` (`TransferResponse.solanaSignature`, `feeUsdc`, claim DTO `amountUsdc`) | DTOs mirror chain-revealing contract fields. | APP-00 |
| V5 | Comments/descriptions (`home_screen.dart` ≈ l.232, `app_en.arb` l.49, `supported_currency.dart`, `transaction.dart`) | Mention "stablecoin"/"on-chain". Not user-visible but invites drift. | APP-00 |

**Enforcement (so it stays true):** INV-01 contract lint, INV-02 copy/asset lint
in CI, INV-03 response guard on the backend, INV-04 error/notification template
review, INV-05 chain-error mapping. Details in §6 and Appendix C.

---

## 2. Decisions to close in week 0 (they gate the plan)

| # | Decision | Recommendation | Why it matters |
|---|----------|----------------|----------------|
| D1 | **Custody model** | **Pooled custody.** One Stellar treasury setup (hot + cold) holds all USDC. Users have ledger balances only; MoneyA→MoneyA sends are ledger-only. Chain is touched at onramp credit and offramp debit. | Removes per-user accounts, trustlines, reserves, sponsored-reserve logic and per-user key provisioning. Cuts ≈ 10 IED and most chain failure modes. Matches the `usdc-stablecoin-ops` skill's "pooled custodial wallet with per-user ledger". |
| D2 | **Ramp provider(s)** | **DECIDED: Yellow Card is the primary** (already in the specs, announced USDC-on-Stellar support in Feb 2024). **Correction:** the repo's own `african-payment-rails` skill lists Yellow Card for **NGN, GHS, KES, ZAR, XAF — not XOF**. XOF (UEMOA) is therefore *not* assumed covered: it would be served by a fiat-side mobile-money aggregator (Onafriq in the skill) paid from float that MoneyA refills by converting treasury USDC through Yellow Card/an anchor. Confirm in RMP-00. **Fallback:** a licensed SEP-24 anchor for the launch corridor (SEP-10 auth + SEP-24 interactive flow + SEP-38 quotes). MoneyGram Ramps is **not** chosen: it is no longer Stellar-only and its African cash-in coverage is thin. | The Feb 2024 announcement covers Yellow Card's app. **Its Payments API on Stellar is not confirmed.** Ticket **RMP-00** (below) must confirm it with Yellow Card (written answer: Stellar USDC deposit address + memo on collect, Stellar payout `txProof`, sandbox access, corridor list) **before** M6/M7 start. If the answer is no, switch to the fallback; this is already covered by the contingency. |
| D7 | **Currency of user balances (FX risk)** | **DECIDED (b), see ADR 0001.** `0001` denominates the ledger in USDC (`currency DEFAULT 'USDC'`) while users see fiat. (a) USD-denominated ledger shown in fiat at the live rate: a user's XOF balance would drift with FX without them acting — confusing and a support burden. (b) **Fiat-denominated per-user ledger**, converted at top-up/cash-out with the rate locked at the time: balances never move, MoneyA's treasury carries the FX exposure (priced into the spread, limited and hedged by policy). **Chosen: (b).** | Decides the currency of `USER_WALLET` ledger accounts, what a quote means, and treasury risk limits. **Unblocks M2 ledger posting design and the M6/M7 quote logic.** The schema already supports either (`UNIQUE (kind, user_id, currency)`). |
| D6 | **Where the backend lives** | **DECIDED: monorepo.** NestJS backend in `backend/` at the root of this repository (pnpm workspace: `backend/apps/api`, `backend/packages/{chain,ledger,infra,infra-supabase}`), next to the Flutter app. | `docs/backend/openapi.yaml` is the contract the client already codes against; one repo means one PR can change the contract, the API and the client, and one branch/CI view for the small team. Matches the `packages/infra` layout already described in `architecture.md` §11. Split into its own repo only if the team grows or release cadences diverge. |
| D3 | **Launch corridor(s)** | One corridor first, from those Yellow Card lists today. Recommendation: **GHS or KES** (lighter regulatory load than NGN/BVN). XOF/XAF follow via the aggregator path above. This is a business call — confirm. | Limits compliance, liquidity and support scope. |
| D4 | **Signing / key custody** | Treasury keys in a KMS/HSM-backed signer (cloud KMS with Ed25519, Turnkey, or Fireblocks — verify current Stellar support). Use native Stellar **multisig thresholds** on the cold/treasury account. Do **not** assume Privy supports Stellar; verify before keeping it. | Replaces Privy + Squads/Safe. Key handling is the main security risk. |
| D5 | **Legal / licensing** | Confirm VASP/MTL posture for the launch jurisdiction before mainnet. | Stellar does not change this. It can block launch regardless of engineering. |

> If D1 is overridden to per-user accounts, add the **Appendix A** tickets and
> ≈ +10 IED. Everything else in this plan still applies.

---

## 3. Target architecture (what changes vs. today)

The Flutter client stays chain-agnostic. The skill rule remains: **no signing,
no RPC, no addresses on the client.**

| Area | Today (Solana) | MVP (Stellar) |
|------|----------------|---------------|
| Chain / asset | Solana + USDC SPL | Stellar + USDC (Circle issuer, `USDC:G…`) |
| Custody | Privy per-user wallet | Pooled treasury (D1/D4); users = ledger rows |
| Wallet provisioning | Privy `createWallet` after KYC | DB row only (no on-chain account; inbound deposits are attributed by a per-order memo) |
| Submit + confirm | `sendTransaction` + `confirmTransaction` | Horizon / Stellar RPC `submitTransaction`; poll tx hash; ~5 s ledger close |
| Inbound deposits | Helius webhooks | Horizon **payments stream** (cursor-based) on the deposit account + provider webhook |
| Idempotency key for chain | tx signature | **tx hash** — known *before* submit (deterministic from the envelope), so resubmitting the same envelope is safe |
| Concurrency | n/a | **Channel accounts** (sequence-number pool) so parallel payouts do not collide on one account's sequence |
| Fees | SOL gas | Base fee in XLM, paid by treasury / **fee-bump** transactions; XLM balance monitored |
| Treasury security | Squads / Safe multisig | Stellar account **signers + thresholds** (e.g. 2-of-3 for med, 3-of-5 for high) |
| Escrow (unclaimed) | On-chain escrow wallet | **Ledger-only** `MONEYA_ESCROW` account (already in the schema). Claimable balances are not needed under D1. |
| RPC | Helius + QuickNode | Two independent Horizon/RPC providers (e.g. SDF public + a commercial one such as QuickNode/Blockdaemon) with failover |
| Backend SDK | `@solana/web3.js` | `@stellar/stellar-sdk` (backend only) |

New backend module: **`ChainModule`** with a `ChainAdapter` interface
(`getBalance`, `submitPayment`, `getTx`, `streamPayments`, `isValidAddress`).
`StellarAdapter` is the only implementation in the MVP. The interface exists so
a second chain is a drop-in later, not a rewrite.

---

## 4. Stellar technical design

### 4.1 Accounts
- **Treasury (cold):** holds the bulk of USDC. Multisig, rarely used. Funded with XLM for reserve.
- **Hot distribution account:** signs payouts and funds channel accounts. Balance cap = ≤ 24 h of expected volume; sweep excess to cold.
- **Deposit account:** receives onramp USDC. Attribute deposits with a **memo** (`MEMO_ID`/`MEMO_HASH` = order id) or muxed addresses. Never share an address without a memo.
- **Channel accounts (N ≈ 5–10):** pure sequence-number holders for parallel submissions. Hot account is the source of the payment op; the channel is the tx source.
- **Fee source:** fee-bump envelope signed by hot account.
- Every account needs the **USDC trustline** and enough XLM for reserves + fees (alert at a low-water mark).

### 4.2 Transaction pipeline
1. Build the payment op (strict amounts as 7-dp strings; USDC is 7 dp on Stellar vs 6 in the current `numeric(20,6)` — keep 6 dp in the ledger, convert at the adapter boundary and reject sub-micro amounts).
2. Set **timebounds** (≈ 60–120 s) so a stuck tx expires deterministically.
3. Compute and **persist the tx hash and signed XDR before submit**.
4. Submit. On timeout or unknown result, **resubmit the same XDR** (idempotent) or look the hash up.
5. Confirm via tx hash lookup; treat `tx_bad_seq`, `tx_insufficient_fee`, `tx_too_late` as retryable with a **new** envelope only after the old one is provably expired.
6. Only then post the ledger journal (principle P5 in the FSM doc stays unchanged).

### 4.3 Inbound detection (onramp)
- Stream payments for the deposit account from a stored **paging cursor**; process idempotently keyed on `(tx_hash, op_index)`.
- Match by memo to the `onramp_orders` row; check asset = USDC issuer, amount ≥ expected, order not expired.
- Cursor persisted in Postgres; on restart replay from cursor. A catch-up job covers stream gaps.
- Mismatches (no memo, wrong asset, short amount) go to a **suspense** ledger account + ops alert, never auto-credited.

### 4.4 Ramps
- **Primary (decided): Yellow Card on Stellar:** same REST/webhook flow as today; only the deposit address/memo and `txProof` change (tx hash instead of Solana signature). Gated by RMP-00.
- **If a SEP-24 anchor:** backend implements the SEP-10 client auth and the SEP-24 interactive flow (webview in the Flutter app) with SEP-38 quotes where the anchor supports them. This is a **different integration**, budgeted in the contingency in §7.

### 4.5 Reconciliation
Daily and every-5-minute checks: `sum(ledger USER_WALLET + ESCROW + FEES + SUSPENSE)` vs on-chain
(hot + deposit + cold − in-flight), plus provider settlement reports. The current
REC-01 changes from "every wallet" to "a handful of accounts", which is cheaper.

---

## 5. Data & API changes

**New migration `0003_stellar_chain.sql`** (append-only; `0001` is never edited,
`0002_state_machine.sql` is already planned):
- `ALTER TYPE app.chain ADD VALUE 'STELLAR'` and make it the default for new rows.
- `transfers.solana_signature` / `offramp_orders.solana_signature` → add `chain_tx_hash TEXT` (+ unique index where applicable), backfill, keep old columns until launch, then drop.
- `wallets`: `privy_wallet_id`, `address`, `chain` become nullable (no default); `onramp_orders.deposit_memo` (unique) attributes inbound deposits.
- New tables: `chain_accounts` (role, public key, xlm_low_water), `chain_txs` (tx hash, signed XDR, status, timebounds, attempts), `chain_cursors` (stream name, paging token), `chain_inbound_payments` (dedupe on `operation_id` and `(tx_hash, op_index)`; `SUSPENSE`/`MATCHED` checks).
- Seed ledger account `MONEYA_HOT_WALLET` description → "Stellar hot wallet"; add `MONEYA_DEPOSIT` if you want it separate.

**OpenAPI** (`openapi.yaml`) — **already migrated to a fiat-only contract (§1.1)**: no `chain`, `address`, `*_usdc`, `solana_signature`/tx hash in any response; `amount`+`currency` everywhere; `/v1/wallet` returns `balance`+`currency` only; quotes expose `from/to` fiat amounts, one effective `rate` and one all-in `fee`; chain failures collapse to `SERVICE_UNAVAILABLE`; `/webhooks/privy` marked deprecated (kept only if D4 keeps a hosted custodian). `chain_tx_hash` exists **only in the database and internal ops tooling**, never in the public API.
**Webhooks doc:** drop the Privy sections unless D4 keeps Privy; add the Horizon stream consumer as an internal "webhook-like" source with the same dedupe table.

---

## 6. Work plan

Sizes are for the backend unless marked **[App]**. Milestones keep the backlog
numbering so the two plans can be run together.

### Phase A — Foundation and de-risking (≈ 2 weeks)

| Ticket | Description | Size | Deps |
|--------|-------------|------|------|
| DEC-01 | Record D1–D6 in an ADR in `docs/backend/adr/` (D2 and D6 are decided above; D1, D3, D4, D5 still need the owner's confirmation) | 1 | — |
| RMP-00 | **Yellow Card Stellar confirmation** (see D2): written confirmation + sandbox keys, or trigger the SEP-24 fallback. Start in day 1; it is lead-time, not engineering. | 1 | — |
| STL-00 | **Spike on testnet:** create accounts, trustline, payment, fee-bump, channel account, stream, `tx_bad_seq` retry. Throwaway scripts. | 2 | — |
| FND-01..05 | NestJS skeleton **in `backend/`** (D6), Supabase staging, CI (path-filtered: `backend/**` vs `lib/**`), `0001` deployed, Sentry (unchanged from backlog M0) | 4 | — |
| STL-01 | `ChainAdapter` interface + `StellarAdapter` skeleton + config (network passphrase, issuer, RPC URLs) | 2 | FND-01 |
| DB-01 | `0003_stellar_chain.sql` + doc updates (§5). OpenAPI fiat-only contract **already updated** in this change set | 1 | FND-03 |
| INV-01 | **Contract lint:** Spectral rule + CI step failing if any response schema/property/description contains a forbidden term or field (`usdc`, `solana`, `stellar`, `chain`, `address`, `hash`, `signature`…) | 1 | — |
| INV-03 | **Response guard (backend):** e2e test that scans every JSON response in the suite for Stellar address (`G[A-Z2-7]{55}`), 64-hex hashes and forbidden terms | 1 | FND-01 |

**Exit gate:** ramp provider confirmed (D2) and spike proves submit/confirm/stream on testnet.

### Phase B — Identity and ledger (≈ 2 weeks; mostly unchanged)

| Milestone | Scope | Size | Change vs backlog |
|-----------|-------|------|-------------------|
| M1 Auth & sessions | OTP, passcode, step-up, refresh rotation | 6 | none |
| M2 Ledger primitives | `0002_state_machine.sql`, posting helpers, balance fns | 4 | none |
| M3 KYC + account | Smile ID flow; **account provisioning = DB row** | 4 | −3 (no Privy) |
| M4 Webhooks | Universal handler, dedupe, replay CLI; YC + Smile only | 4 | −1 (no Privy HMAC) |

### Phase C — Money movement on Stellar (≈ 3–4 weeks)

| Ticket | Description | Size | Deps |
|--------|-------------|------|------|
| STL-02 | Treasury setup scripts: accounts, trustlines, signers/thresholds, channel pool, runbook | 3 | STL-00, D4 |
| STL-03 | Signer service (KMS/HSM): sign XDR, policy limits, audit log of every signing | 3 | STL-02 |
| STL-04 | Submit worker: persist hash+XDR → submit → confirm; retry/resubmit rules; fee-bump; channel pool lease | 4 | STL-01, M2 |
| INV-05 | **Chain-error mapping:** map every chain/provider failure to `SERVICE_UNAVAILABLE`/`QUOTE_EXPIRED`/etc.; localized generic copy; unit-tested table | 1 | STL-04 |
| STL-05 | Deposit stream consumer + cursor + catch-up + suspense handling | 3 | STL-01, M2 |
| M5 In-network P2P | Ledger-only transfer, FSM, mirror RECEIVED, WSS/push hooks | 6 | −3 (no chain leg) |
| M6 Onramp | Quote → order → collected → credit ledger on confirmed deposit | 6 | −1 |
| M7 Offramp | Quote → order → debit ledger → STL-04 payout with memo → provider payout → settle/refund | 7 | −1 |
| M8 Unclaimed | Claim link, Twilio SMS, redeem, 7-day expiry refund, **ledger-only escrow** | 4 | −2 |
| STL-06 | Ops console basics (CLI/SQL views): stuck chain txs, suspense items, XLM balances | 2 | STL-04/05 |

### Phase D — Notifications, compliance, reconciliation (≈ 2 weeks, parallel with C)

| Milestone | Scope | Size |
|-----------|-------|------|
| M9 Notifications & realtime | FCM/APNs, in-app feed, WSS gateway | 5 |
| M10 Compliance & limits | Velocity, sanctions on recipient phone, per-corridor limits, tier 0/1 caps | 4 |
| M11 Reconciliation | On-chain (few accounts) + ledger + provider report; alerts | 3 (−1) |

### Phase E — Flutter app to production-ready (runs from week 3, in parallel) **[App]**

Existing: W1 foundations (dio, secure storage, logging, flavors), W2 step-up,
`POST /v1/transfers` wired to the confirm screen. Remaining to wire to real endpoints:

| Ticket | Scope | Size |
|--------|-------|------|
| APP-00 | **Contract + copy migration (fixes V1–V5):** move DTOs to the fiat-only contract (`amount`+`currency`, `fee`, no `solanaSignature`/`amountUsdc`/`feeUsdc`), send the real currency, rename "MoneyA Wallet"→"MoneyA balance"/"Solde MoneyA", remove the USD Coin hero art, clean comments; update the 26+ affected tests; run `flutter gen-l10n`, `flutter analyze`, `flutter test` | 3 | contract (done) |
| INV-02 | **Copy/asset lint in CI:** script (`scripts/lint_copy.py`, self-tested) failing on forbidden terms in `lib/l10n/*.arb` values, `lib/**` string literals, and asset file names; wired to CI | 1 | — |
| APP-01 | Auth: OTP verify, passcode set, refresh/session (replace stubs in `auth/…verify_phone_screen`) | 3 |
| APP-02 | KYC: document + selfie capture upload to `/v1/kyc/submissions`, status polling, pending/approved UI | 4 |
| APP-03 | Home: real balance, history, transaction detail from `/v1/wallet`, `/v1/transfers` (replace stubs in `home/…`) | 4 |
| APP-04 | Load money: quote → order → AWAITING_PAYMENT → result (replace stubs in `load_money/…`) | 4 |
| APP-05 | Withdraw: quote → order → status (replace stubs in `withdraw/…`) | 4 |
| APP-06 | Send to non-user + **claim deep link** (`m.moneya.app/c/<token>`), claim screen, redeem | 4 |
| APP-07 | Realtime (WSS) + push (FCM/APNs), notification center | 4 |
| APP-08 | Error/empty/pending states, FR/EN strings, a11y pass (`fintech-uiux-reviewer`), payment-flow review (`payment-flow-reviewer`) | 4 |
| APP-09 | Test coverage for repositories/controllers; golden path integration test against staging | 3 |

The client never displays "USDC", addresses or tx hashes (skill rule).

### Phase F — Hardening and launch (≈ 2 weeks)

| Ticket | Description | Size |
|--------|-------------|------|
| HRD-01 | **Mainnet dry run** with a small funded treasury; full onramp → P2P → offramp with real money, tiny amounts | 2 |
| HRD-02 | Load/chaos tests: RPC failover, duplicate submits, stream gap, `tx_bad_seq`, provider webhook replay | 3 |
| HRD-03 | Key ceremony + signer rotation drill + treasury sweep procedure | 2 |
| HRD-04 | Alerts wired: XLM low-water, hot > cap, ledger≠chain, stuck txs > 5 min, stream lag, suspense > 0 | 2 |
| HRD-05 | Runbooks, on-call, refund/dispute procedure, privacy/PII review | 2 |
| HRD-06 | Store submission (Play/App Store), staged rollout, limits set low (e.g. $50/day first week) | 2 |
| M12 remainder | Secret rotation drill, DB pool tuning | 2 |

---

## 7. Estimate and timeline

| Block | IED |
|-------|-----|
| A Foundation + de-risking (incl. INV-01/03, RMP-00) | 13 |
| B Identity + ledger | 18 |
| C Money movement (incl. INV-05) | 39 |
| D Notifications, compliance, recon | 12 |
| F Hardening + launch | 15 |
| **Backend total** | **≈ 97** |
| E Flutter app (incl. APP-00, INV-02) | ≈ 38 |
| **Contingency (SEP-24 ramp or provider surprises, ~15%)** | **≈ 15** |

Backend figure is higher than the backlog's 74 because it includes the Stellar
design work, mainnet dry run and launch tasks the backlog left implicit; the
chain-specific savings in M3/M5/M6/M7/M8 are already netted in.

**Staffing:** 2 backend + 1 Flutter engineer → **≈ 11–12 calendar weeks** to a
limited public launch in one corridor. One backend engineer alone: ≈ 18–20 weeks.
These are estimates from the existing backlog's sizing method, not commitments.

```
Wk  1  2  3  4  5  6  7  8  9 10 11 12
A   ██ ██
B      ██ ██
C            ██ ██ ██ ██
D               ██ ██ ██
E         ██ ██ ██ ██ ██ ██ ██ ██
F                              ██ ██ ██
```

---

## 8. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | Ramp provider does not support Stellar USDC in the launch corridor | Medium | **High** | D2 in week 0; budget SEP-24 integration as contingency |
| R2 | Key compromise on hot/treasury account | Low | Critical | KMS/HSM signer, hot cap ≤ 24 h, multisig thresholds, signing policy limits, audit log |
| R3 | Sequence-number collisions / stuck submits | Medium | Medium | Channel pool, persisted XDR, timebounds, resubmit-same-envelope rule |
| R4 | Missed or duplicated deposit credit | Medium | High | Cursor + catch-up, `(tx_hash, op_index)` dedupe, suspense account, recon every 5 min |
| R5 | Thin USDC liquidity or ramp limits in a corridor | Medium | Medium | Pre-fund treasury; per-corridor caps; second provider after launch |
| R6 | RPC/Horizon outage | Medium | Medium | Two independent providers with failover; submit is idempotent |
| R7 | Regulatory blocker | Medium | Critical | D5 in week 0; limits + tier gating; legal sign-off before HRD-01 |
| R8 | XLM balance runs out and payouts stop | Low | High | Low-water alert, auto-top-up runbook |
| R9 | Unverified assumptions about vendor Stellar support (Privy, KMS Ed25519, YC) | Medium | Medium | Verified in STL-00 / DEC-01 before any dependent ticket starts |

---

## 9. Definition of done for the MVP

- All §1 flows pass on **mainnet** with real funds in the launch corridor.
- Ledger = chain reconciliation green for 7 consecutive days on staging and 3 days on mainnet.
- Every chain submit is idempotent under injected failures (HRD-02).
- Signer rotation and treasury sweep rehearsed; runbooks reviewed by a second engineer.
- `payment-flow-reviewer` and `fintech-uiux-reviewer` pass on every money-touching screen and service.
- Legal sign-off (D5) on file.

---

## Appendix A — If D1 is changed to per-user Stellar accounts (+≈ 10 IED)

- STL-A1: Account creation on KYC approval (create + fund minimum XLM, or **sponsored reserves** via `BeginSponsoringFutureReserves`), add USDC trustline, store public key in `wallets.address`. (3)
- STL-A2: Per-user signing keys in the signer service; key derivation/rotation policy; account merge on closure. (3)
- STL-A3: On-chain P2P payments between user accounts (restores the original §4.3 flow) and per-account balance reconciliation. (3)
- STL-A4: Claimable balances for unclaimed transfers with predicates (recipient claim before day 7, sender reclaim after), replacing the ledger-only escrow. (1)
- Revert M3/M5/M8 savings listed in §6.

## Appendix B — Supersession map (what in the older docs no longer applies)

The older docs stay valid for everything not listed. Each now carries a banner pointing here.

| Doc | Superseded parts | Read instead |
|-----|------------------|--------------|
| `architecture.md` | §0 tech table (Privy, Solana, USDC SPL), §1–2 diagrams (Privy/Solana boxes), §3.3 Wallet (Privy provisioning, on-chain balance), §3.4 flavors 1–3 (on-chain P2P, SPL legs), §3.6 step 3, §4.2–4.5 sequences (Privy/Solana calls; P2P is **ledger-only**, escrow is **ledger-only**), §8 matrix rows Privy/Helius, §12.1 | plan §3, §4, §6 |
| `ledger.md` | §3 account `USER_WALLET` "matches on-chain" (now: pooled), §4.x "Solana confirms …" triggers (P2P and escrow journals post on **ledger events**, not chain events), §7.1 reconciliation (compare ledger totals to **treasury + hot + deposit** accounts) | plan §4.5 |
| `transfer-state-machine.md` | `solana_signature`, "Privy returns 4xx/5xx", "Solana confirmTransaction", PROCESSING→AWAITING_CLAIM chain trigger | plan §4.2–4.3; use `chain_tx_hash` internally |
| `webhooks.md` | §7 Privy webhook, §6.4 Privy wallet provisioning chain, Privy rows in §2/§3 | plan §4.3 (deposit stream consumer replaces provider webhooks for inbound USDC) |
| `openapi.yaml` | **Already updated** to the fiat-only contract | — |
| `backlog.md` | M3 Privy tickets, P2P-06 "Solana submission worker", OFF-02 "Solana debit", REC-01 per-wallet reconciler, Solana RPC risk R3 | plan §6 (STL-*, M5–M8 deltas) |
| `migrations/0001_init.sql` | `app.chain = 'SOLANA'`, `solana_signature`, `privy_wallet_id NOT NULL`, "Solana base58" comments | `0003_stellar_chain.sql` (never edit `0001`) |
| `.claude/skills/usdc-stablecoin-ops`, `.claude/README.md`, `.claude/agents/payment-flow-reviewer.md` | **Already updated** (Stellar + invisibility rule) | — |

## Appendix C — Acceptance criteria for the new tickets

A ticket is done only when **all** its bullets are true and the global Definition of
Done (§9) holds. Every ticket also ships its metrics/tracing (backlog principle S7).

### Phase A
- **DEC-01** — ADR committed in `docs/backend/adr/0001-stellar-pooled-custody.md` recording D1–D6, with owner sign-off (initials/date) on D1, D3, D4, D5. Rejected alternatives listed.
- **RMP-00** — Written answer from Yellow Card (email/ticket attached to the ADR) covering: Stellar USDC deposit address + memo on collect, Stellar payout `txProof`, corridor list, sandbox keys received. If any answer is "no", a decision (fallback anchor or other) is recorded and M6/M7 scope adjusted.
- **STL-00** — Throwaway testnet scripts demonstrate: account + USDC trustline, payment with memo, fee-bump, channel-account parallel submits (≥ 10 concurrent without `tx_bad_seq` after retry), payments stream resume from cursor, resubmit-same-XDR is idempotent. Findings written up (≤ 1 page) and linked from the ADR.
- **STL-01** — `ChainAdapter` interface (`getBalance`, `submitPayment`, `getTx`, `streamPayments`, `isValidAddress`) in `backend/packages/chain`; `StellarAdapter` passes the interface contract tests against testnet; network passphrase, issuer and RPC URLs come from config, never code.
- **DB-01** — `0003_stellar_chain.sql` applies cleanly on a fresh DB and on top of `0001`+`0002`; adds `STELLAR`, `chain_tx_hash`, `onramp_orders.deposit_memo`, `chain_accounts`, `chain_txs`, `chain_cursors`, `chain_inbound_payments`; down/rollback documented; RLS on new user-owned tables; schema docs updated.
- **INV-01** — Spectral (or equivalent) rule in CI fails on any of: property names or descriptions in **response** schemas containing `usdc`, `stablecoin`, `solana`, `stellar`, `xlm`, `chain`, `address`, `hash`, `signature` (webhook request signature headers excepted by allowlist); a deliberate violation in a test PR turns CI red.
- **INV-03** — E2E suite asserts no response body (any status) matches Stellar address `G[A-Z2-7]{55}`, a 64-hex string, or the forbidden-term list; includes error responses and WebSocket events.

### Phase C (chain)
- **STL-02** — Reproducible script/runbook creates cold, hot, deposit and N channel accounts on testnet, sets signers/thresholds, adds trustlines, funds XLM; run twice yields the same end state (idempotent). Mainnet variant documented and dry-run reviewed by a second engineer.
- **STL-03** — Signer service signs XDR only for allowlisted destinations and amounts under policy; over-threshold requires a second approval; every signing is written to an append-only audit table; keys never appear in logs/env; test proves a tampered destination is rejected.
- **STL-04** — Hash + signed XDR persisted **before** submit; under injected faults (timeout after submit, 5xx, duplicate worker) exactly one on-chain payment results; `tx_bad_seq`/`tx_too_late` handled per §4.2; channel lease released on every path; metrics: submit latency, retries, failures by code.
- **INV-05** — Table-driven test: every chain/provider error code maps to a localized generic message key (FR+EN) and a non-chain `failure_reason`; no raw SDK error text can reach a response (verified by INV-03).
- **STL-05** — Deposit stream resumes from the persisted cursor after kill -9; replaying the same events never double-credits (`(tx_hash, op_index)` unique); wrong asset / no memo / short amount → suspense row + alert, no credit; catch-up job heals an injected gap.
- **STL-06** — Ops view lists stuck chain txs (> 5 min), suspense items, XLM balances per account, and last-processed stream ledger; each has a documented action.

### Phase E (app)
- **APP-00** — `flutter analyze` clean, `flutter test` green; DTOs match `openapi.yaml` exactly; the request carries the real `currency`; `grep -rniE "usdc|stablecoin|solana|stellar|crypto|blockchain|wallet" lib assets` returns no user-visible hit (comments cleaned); onboarding hero no longer uses USD Coin art; FR/EN strings say "MoneyA balance"/"solde MoneyA".
- **INV-02** — `scripts/lint_copy.py` exits non-zero on a planted forbidden term in an `.arb` value, a Dart string literal, or an asset filename; runs in CI on every PR touching `lib/**` or `assets/**`.
- **APP-01** — Real OTP verify + passcode set against staging; refresh-token rotation works across app restarts; wrong/expired OTP and rate-limit states have localized copy; widget + repository tests.
- **APP-02** — Document + selfie upload with progress/retry; KYC status moves PENDING→APPROVED/REJECTED via push or polling; rejection reasons localized; no PII in logs.
- **APP-03** — Home balance and history come from the API; pull-to-refresh; empty/loading/error states; amounts formatted per locale and currency decimals (XOF/XAF 0 dp).
- **APP-04** — Top-up: quote shown with all-in fee and countdown; on expiry re-quote with explicit diff (never silent); provider app/USSD handoff; AWAITING_PAYMENT → success/failed screens; idempotent on retry.
- **APP-05** — Cash-out: same quote rules; payout status tracked to SETTLED/REFUNDED; failed payout copy says the money is back in the balance.
- **APP-06** — Send to a non-user creates an unclaimed transfer; claim deep link opens the claim screen on cold start and warm start; redeem works after signup+KYC; expired/revoked states handled.
- **APP-07** — WSS reconnects with backoff and resumes; push permission flow; notification center reflects server events; no duplicate toasts on reconnect.
- **APP-08** — `fintech-uiux-reviewer` and `payment-flow-reviewer` run on every money-touching screen with zero blocker findings; TalkBack/VoiceOver pass on the send flow; `i18n-auditor` clean for FR/EN.
- **APP-09** — Golden-path integration test (login → top-up → send → cash-out) runs against staging in CI nightly; repository/controller unit coverage ≥ 80% on changed files.
