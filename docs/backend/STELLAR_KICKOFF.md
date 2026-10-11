# Stellar MVP — Kickoff for the implementation session

Read this first. It tells a fresh session (or engineer) what is decided, what is
still open, what to read, and what to build first.

## 1. One-paragraph brief

MoneyA is a Flutter remittance app for West & Central Africa. We are building the
backend (NestJS, in `backend/` of this repo) and wiring the app to it. Money is
settled in **USDC on Stellar** with **pooled custody** (users have ledger balances;
chain is touched only at top-up credit and cash-out debit). **Users must never learn
that stablecoins exist** — the API is fiat-only and no surface shows crypto terms.

## 2. Read order (≈ 45 min)

1. `docs/backend/stellar-mvp-plan.md` — the plan. §1.1 (invisibility), §2 (decisions), §3–4 (design), §6 (tickets), Appendix B (what older docs no longer apply), Appendix C (acceptance criteria).
2. `docs/backend/openapi.yaml` — **already migrated** to the fiat-only contract. It is the source of truth for the API.
3. `docs/backend/transfer-state-machine.md`, `ledger.md`, `webhooks.md` — still valid except the parts listed in plan Appendix B (all carry a banner).
4. `docs/backend/client-integration-notes.md` — how the Flutter client is wired (dio interceptors, idempotency, step-up).
5. `.claude/skills/usdc-stablecoin-ops/SKILL.md` (updated), `fintech-security`, `fintech-mobile-uiux`, `flutter-architecture`.

## 3. Status of decisions

| | Status |
|---|---|
| Stellar replaces Solana | **Decided** |
| Fiat-only API / stablecoins invisible | **Decided, non-negotiable** |
| Backend location | **Decided:** `backend/` monorepo folder (pnpm workspace) |
| Ramp provider | **Decided:** Yellow Card primary, SEP-24 anchor fallback — **but Stellar support in its API is unconfirmed (RMP-00)** and it does **not** list XOF in the repo's skill |
| D1 pooled custody · D3 launch corridor (GHS first) · D4 key custody · D5 licensing | **Confirmed by the owner** — recorded in `docs/backend/adr/0001-stellar-pooled-custody.md` (D3's GHS-vs-KES pick is the implementer's; owner may veto) |
| **D7 currency of user balances** | **Decided: fiat-denominated per-user ledger** (ADR 0001). M2 and quote logic are unblocked. |
| RMP-00 Yellow Card answer | **Still open** — gates STL-02..06 and M6/M7 |

## 4. Where to work

- Branch: `feature/v1.0` (do not push elsewhere without permission).
- Migrations are append-only: new schema goes in `docs/backend/migrations/000N_*.sql` (or `backend/` migration dir once created); never edit `0001_init.sql`.
- Contract changes go through `openapi.yaml` first, then backend, then client — same PR when possible.

## 5. State of the work and what to do next

**Already done and verified** (see plan §0 for the evidence): backend skeleton in `backend/` (lint/typecheck/61 tests/build green),
`@moneya/chain` offline Stellar core, `0003_stellar_chain.sql` (validated on PostgreSQL 16), fiat-only OpenAPI + contract lint,
copy/asset lint, response guard, and the Flutter fiat-only migration (APP-00: analyze unchanged, 119 tests green). CI is written but has not run on GitHub yet.

**Do next, in this order:**

| # | Who | What |
|---|-----|------|
| 1 | Owner | Send RMP-00 to Yellow Card; confirm D1, D3, D4, D5; **decide D7**. |
| 2 | Anyone with internet | **STL-00** on Stellar testnet: run `StellarAdapter` for real (`getSequence`, `submit` incl. fee-bump, `getTx` by **inner** hash, `streamPayments`, `opIndexFromOperationId`) — these were unreachable in the authoring sandbox and are **unverified**. |
| 3 | Backend | Check the first CI run on GitHub (it has never run); fix anything environment-specific. |
| 4 | Backend | M1 auth with a fake SMS provider (no external keys needed); `0002_state_machine.sql` once D7 is decided. |
| 5 | App | APP-01, APP-04, APP-05 are wired (see plan §0). Remaining: APP-02 KYC, APP-03 balance/history (needs `GET /v1/wallet` + transfers endpoints), APP-06..09. |

## 6. Rules that must hold in every PR

1. **No stablecoin/crypto vocabulary or fields reach the user or the client** (UI, l10n FR/EN, SMS, push, receipts, errors, art, API responses). Say "money" / "MoneyA balance" / "solde MoneyA".
2. Money is a **string/Decimal** — never `double`. Fiat display decimals: XOF/XAF 0, NGN/GHS/KES 2. Ledger 6 dp internally; convert to Stellar's 7 dp only inside the chain adapter.
3. **Idempotency everywhere**: `Idempotency-Key` on money POSTs; chain tx hash + signed XDR persisted **before** submit; inbound credits keyed on `(tx_hash, op_index)`.
4. Ledger posts **only after confirmed settlement**; unmatched deposits go to suspense, never auto-credit.
5. Never log PII, keys, passcodes; no chain details in client telemetry.
6. Prefer the repo's agents before merging money/UX work: `payment-flow-reviewer`, `fintech-uiux-reviewer`, `i18n-auditor`.
7. Do not claim something works until you ran it (`flutter analyze`/`flutter test`, backend tests, testnet).

## 7. Known gotchas

- `flutter pub get` rewrites `pubspec.lock` and `analysis_options.yaml` with newer SDKs: do not commit those unrelated changes. Do not run `dart format` on the whole tree — the repo is not formatted with the current SDK and it produces large unrelated diffs.
- Vendor claims to verify, not assume: Yellow Card Payments API on Stellar; a KMS/custody product that signs Ed25519 for Stellar (Privy support unverified).
- Stellar USDC is 7 dp; the ledger and API are 6 dp — reject sub-micro amounts at the adapter.
- A single Stellar account has one sequence number: parallel submits need channel accounts.

## 8. Prompt to paste into the implementation session

> Read `docs/backend/STELLAR_KICKOFF.md` and `docs/backend/stellar-mvp-plan.md` (§0 status, §1.1, Appendix C),
> then continue on branch `feature/v1.0`. The scaffold, chain core, migration 0003, invisibility checks and the
> Flutter fiat-only migration are already done. First, if you have internet access, run STL-00 on Stellar testnet to
> verify the network half of `StellarAdapter`; otherwise start M1 auth with a fake SMS provider. Respect §1.1
> (stablecoins invisible: `python3 scripts/lint_copy.py` and `pnpm test` in `backend/` must stay green). Do not
> start any Phase C chain ticket or the ledger account currency until D1, D4 and D7 are confirmed. Commit in small steps.
