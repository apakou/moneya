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
| D1 custody (pooled) · D3 launch corridor · D4 key custody · D5 licensing | **Recommended in the plan, awaiting owner confirmation.** Do not start Phase C chain tickets until D1 and D4 are confirmed. |

## 4. Where to work

- Branch: `feature/v1.0` (do not push elsewhere without permission).
- Migrations are append-only: new schema goes in `docs/backend/migrations/000N_*.sql` (or `backend/` migration dir once created); never edit `0001_init.sql`.
- Contract changes go through `openapi.yaml` first, then backend, then client — same PR when possible.

## 5. What to build first (no blockers)

Phase A can all start now, in parallel:

| Track | Tickets | Notes |
|-------|---------|-------|
| Owner / business | **RMP-00**, DEC-01 sign-offs | Email Yellow Card; confirm D1/D3/D4/D5 |
| Backend | FND-01..05, STL-00 (testnet spike), STL-01, DB-01, INV-01, INV-03 | Skeleton in `backend/`, CI path-filtered |
| App | APP-00, INV-02 | Needs the Flutter SDK; fixes V1–V5 (plan §1.1), including the `amount_usdc`-carries-local-currency bug |

Then: Phase B (auth, ledger, KYC) → Phase C (chain) once RMP-00 and D1/D4 are closed.

## 6. Rules that must hold in every PR

1. **No stablecoin/crypto vocabulary or fields reach the user or the client** (UI, l10n FR/EN, SMS, push, receipts, errors, art, API responses). Say "money" / "MoneyA balance" / "solde MoneyA".
2. Money is a **string/Decimal** — never `double`. Fiat display decimals: XOF/XAF 0, NGN/GHS/KES 2. Ledger 6 dp internally; convert to Stellar's 7 dp only inside the chain adapter.
3. **Idempotency everywhere**: `Idempotency-Key` on money POSTs; chain tx hash + signed XDR persisted **before** submit; inbound credits keyed on `(tx_hash, op_index)`.
4. Ledger posts **only after confirmed settlement**; unmatched deposits go to suspense, never auto-credit.
5. Never log PII, keys, passcodes; no chain details in client telemetry.
6. Prefer the repo's agents before merging money/UX work: `payment-flow-reviewer`, `fintech-uiux-reviewer`, `i18n-auditor`.
7. Do not claim something works until you ran it (`flutter analyze`/`flutter test`, backend tests, testnet).

## 7. Known gotchas

- The authoring environment for the plan **had no Flutter SDK**: the Dart changes in APP-00 are *not* done and were never compiled. Run `flutter pub get`, `flutter gen-l10n`, `flutter analyze`, `flutter test` before and after.
- Vendor claims to verify, not assume: Yellow Card Payments API on Stellar; a KMS/custody product that signs Ed25519 for Stellar (Privy support unverified).
- Stellar USDC is 7 dp; the ledger and API are 6 dp — reject sub-micro amounts at the adapter.
- A single Stellar account has one sequence number: parallel submits need channel accounts.

## 8. Prompt to paste into the implementation session

> Read `docs/backend/STELLAR_KICKOFF.md` and `docs/backend/stellar-mvp-plan.md`, then
> start Phase A on branch `feature/v1.0`: scaffold the NestJS monorepo in `backend/`
> (FND-01..05), then STL-01 and DB-01. Respect plan §1.1 (stablecoins invisible) and
> the acceptance criteria in Appendix C. Ask me before starting any Phase C chain ticket
> until D1 and D4 are confirmed. Commit in small steps and push to `feature/v1.0`.
