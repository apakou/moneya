# MoneyA — Stellar MVP Implementation Plan

> **Status:** Proposal v1 — supersedes the Solana/Privy assumptions in
> [`architecture.md`](./architecture.md), [`ledger.md`](./ledger.md) and
> [`backlog.md`](./backlog.md). Those docs stay the reference for everything
> that is **not** chain-specific (auth, KYC, ledger, FSM, webhooks, compliance).
> **Decision:** Stellar replaces Solana as the settlement chain.
> **Sizes** are estimates in ideal-engineer-days (IED), same unit as the backlog.

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

---

## 2. Decisions to close in week 0 (they gate the plan)

| # | Decision | Recommendation | Why it matters |
|---|----------|----------------|----------------|
| D1 | **Custody model** | **Pooled custody.** One Stellar treasury setup (hot + cold) holds all USDC. Users have ledger balances only; MoneyA→MoneyA sends are ledger-only. Chain is touched at onramp credit and offramp debit. | Removes per-user accounts, trustlines, reserves, sponsored-reserve logic and per-user key provisioning. Cuts ≈ 10 IED and most chain failure modes. Matches the `usdc-stablecoin-ops` skill's "pooled custodial wallet with per-user ledger". |
| D2 | **Ramp provider(s)** | **DECIDED: Yellow Card is the primary** (already in every spec, one aggregator across XOF/XAF/NGN/GHS/KES, announced USDC-on-Stellar support in Feb 2024). **Fallback:** a licensed SEP-24 anchor for the launch corridor (SEP-10 auth + SEP-24 interactive flow + SEP-38 quotes). MoneyGram Ramps is **not** chosen: it is no longer Stellar-only and its African cash-in coverage is thin. | The Feb 2024 announcement covers Yellow Card's app. **Its Payments API on Stellar is not confirmed.** Ticket **RMP-00** (below) must confirm it with Yellow Card (written answer: Stellar USDC deposit address + memo on collect, Stellar payout `txProof`, sandbox access, corridor list) **before** M6/M7 start. If the answer is no, switch to the fallback; this is already covered by the contingency. |
| D6 | **Where the backend lives** | **DECIDED: monorepo.** NestJS backend in `backend/` at the root of this repository (pnpm workspace: `backend/apps/api`, `backend/packages/{chain,ledger,infra,infra-supabase}`), next to the Flutter app. | `docs/backend/openapi.yaml` is the contract the client already codes against; one repo means one PR can change the contract, the API and the client, and one branch/CI view for the small team. Matches the `packages/infra` layout already described in `architecture.md` §11. Split into its own repo only if the team grows or release cadences diverge. |
| D3 | **Launch corridor(s)** | One corridor first (pick the one with the confirmed D2 provider), second corridor in the hardening phase. | Limits compliance, liquidity and support scope. |
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
| Wallet provisioning | Privy `createWallet` after KYC | DB row only (`wallets` stores a **deposit memo/muxed ID**, no on-chain account) |
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
- `wallets`: `privy_wallet_id` becomes nullable; add `deposit_memo TEXT UNIQUE`.
- New tables: `chain_accounts` (role, public key, xlm_low_water), `chain_txs` (hash, xdr, status, timebounds, attempts), `chain_cursors` (stream name, paging token).
- Seed ledger account `MONEYA_HOT_WALLET` description → "Stellar hot wallet"; add `MONEYA_DEPOSIT` if you want it separate.

**OpenAPI** (`openapi.yaml`): `chain` enum `[STELLAR]`, rename `solana_signature` → `chain_tx_hash`, remove "base58" / "SPL" wording, `/v1/wallet` returns balance (ledger) + optional deposit memo, `/webhooks/privy` removed (or gated behind D4).
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
| DB-01 | `0003_stellar_chain.sql` + OpenAPI/doc updates (§5) | 2 | FND-03 |

**Exit gate:** ramp provider confirmed (D2) and spike proves submit/confirm/stream on testnet.

### Phase B — Identity and ledger (≈ 2 weeks; mostly unchanged)

| Milestone | Scope | Size | Change vs backlog |
|-----------|-------|------|-------------------|
| M1 Auth & sessions | OTP, passcode, step-up, refresh rotation | 6 | none |
| M2 Ledger primitives | `0002_state_machine.sql`, posting helpers, balance fns | 4 | none |
| M3 KYC + account | Smile ID flow; **wallet provisioning = DB row + deposit memo** | 4 | −3 (no Privy) |
| M4 Webhooks | Universal handler, dedupe, replay CLI; YC + Smile only | 4 | −1 (no Privy HMAC) |

### Phase C — Money movement on Stellar (≈ 3–4 weeks)

| Ticket | Description | Size | Deps |
|--------|-------------|------|------|
| STL-02 | Treasury setup scripts: accounts, trustlines, signers/thresholds, channel pool, runbook | 3 | STL-00, D4 |
| STL-03 | Signer service (KMS/HSM): sign XDR, policy limits, audit log of every signing | 3 | STL-02 |
| STL-04 | Submit worker: persist hash+XDR → submit → confirm; retry/resubmit rules; fee-bump; channel pool lease | 4 | STL-01, M2 |
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
| A Foundation + de-risking | 12 |
| B Identity + ledger | 18 |
| C Money movement | 38 |
| D Notifications, compliance, recon | 12 |
| F Hardening + launch | 15 |
| **Backend total** | **≈ 95** |
| E Flutter app | ≈ 34 |
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

## Appendix B — Files to update when this plan is accepted

`docs/backend/architecture.md` (§0 table, §1–4 diagrams, §8 matrix), `ledger.md` (§7.1 recon),
`transfer-state-machine.md` (signature → tx hash), `webhooks.md` (drop Privy, add stream consumer),
`openapi.yaml`, `backlog.md` (link to this plan), `.claude/skills/usdc-stablecoin-ops/SKILL.md`
(chain decision table, RPC providers, security section), `.claude/agents/payment-flow-reviewer.md`
(Solana-specific checks).
