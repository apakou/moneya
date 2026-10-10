---
name: usdc-stablecoin-ops
description: Stablecoin settlement operations for MoneyA on Stellar — USDC on Stellar, pooled custody, treasury/channel accounts, tx submission and confirmation, deposit detection, ledger-only escrow for unclaimed transfers, RPC providers, key custody, and the rule that users never see any of it. USE WHEN the user mentions USDC, stablecoin, Stellar, XLM, Horizon, trustline, on-chain, wallet, escrow, blockchain, RPC, fees, treasury or custody. DO NOT USE FOR fiat-only flows (see african-payment-rails) or KYC (see fintech-security).
---

# Stablecoin Operations (Stellar, invisible to users)

Full plan: `docs/backend/stellar-mvp-plan.md`. This skill is the short operating guide.

## Rule 0 — The user must never know (non-negotiable)

MoneyA users see **money in their own currency** (XOF, XAF, NGN, GHS, KES), a
**MoneyA balance**, and **mobile money**. Never in any user-facing surface —
UI copy (FR/EN), notifications, SMS, receipts/PDF, error messages, store
listing, onboarding art, support macros, API responses:

- ❌ "USDC", "USD Coin", "stablecoin", "crypto", "blockchain", "Stellar", "XLM", "on-chain", "wallet", "gas", "hash", "address"
- ❌ A rate shown as `XOF/USDC`. Show the all-in rate fiat→fiat, or just the amount received.
- ❌ Coin/crypto imagery (e.g. a USD Coin illustration).

How it is enforced: fiat-only API contract (`docs/backend/openapi.yaml`), copy lint
over `lib/l10n/*.arb` and assets, a contract test over response schemas, and the
`payment-flow-reviewer` / `fintech-uiux-reviewer` checklists. See plan §0.

Legal note: hiding this from the **UX** is not hiding it from **legal documents**.
The Terms of Service / privacy notice must truthfully describe how funds are held
and settled (counsel decides the wording). Do not remove disclosures regulators require.

## Chain decision: Stellar

| Criterion | Stellar |
|---|---|
| Asset | Circle-issued native USDC (`USDC:<issuer>`), 7 decimals on-chain; ledger keeps 6 dp, convert at the adapter |
| Fee | ~0.00001 XLM per op (paid by MoneyA via fee-bump; users never hold XLM) |
| Finality | ~5 s ledger close |
| Backend SDK | `@stellar/stellar-sdk` (backend only) |
| Ramps | Yellow Card (primary, Stellar support to be confirmed — ticket RMP-00); SEP-24/SEP-6 anchors (fallback) |

**Rule**: never touch the chain from the Flutter client. All chain operations go
through the backend; the app sees only fiat amounts.

## Custody model (MVP): pooled

- Treasury (cold, multisig thresholds), hot distribution account, deposit account (memo/muxed per order), channel accounts (sequence-number pool).
- User balances live in the **Postgres double-entry ledger**, not on-chain. MoneyA → MoneyA sends are **ledger-only** (instant, free).
- Chain is touched at onramp credit (inbound deposit) and offramp debit (outbound payout) only.
- Trade-off: you are a custodian/VASP in most jurisdictions — licensing required (decision D5).
- Non-custodial / per-user accounts: post-MVP; see plan Appendix A.

## Transaction rules

1. Build op → set **timebounds** (60–120 s) → compute hash → **persist hash + signed XDR before submit**.
2. Submit; on unknown result **resubmit the same XDR** or look up the hash. Never build a second envelope until the first is provably expired.
3. Fees via **fee-bump**; use **channel accounts** for parallel submits (one sequence number per source account).
4. Post the ledger journal only after confirmed settlement (FSM principle P5).
5. Inbound: payments stream with persisted cursor, dedupe `(tx_hash, op_index)`, match by memo; anything unmatched → **suspense** + alert, never auto-credit.

## Escrow for unclaimed transfers

Ledger-only `MONEYA_ESCROW` account keyed by `sha256(recipient_e164 + salt)`;
SMS claim link (TTL 7 days, FR/EN by country code; wording says "money", never any asset name);
recipient verifies phone, KYC tier ≥ 1, redeems; day 7 → auto-refund to sender.
(Stellar claimable balances only apply if custody moves to per-user accounts.)

## Fee economics (worst case, illustrative)

```
Sender mobile-money collection .. 1.0–1.5%  (provider)
FX spread (fiat→USD) ............ 0.3–0.8%
Network fee ..................... ~0.00001 XLM (negligible)
Receiver payout ................. 1.0–1.5%
FX spread (USD→fiat) ............ 0.3–0.8%
MoneyA margin ................... 0.5–1.0%
Total to user ................... 3–5% typical — shown as ONE all-in fee
```

## RPC providers

Two independent Horizon/Stellar RPC providers with failover (e.g. SDF public + one commercial). Submission is idempotent, so failover is safe.

## Security essentials

- Hot balance ≤ 24 h of expected volume; sweep excess to cold.
- Native multisig: weighted signers + thresholds on treasury; payout above threshold needs manual approval + Slack alert.
- Keys in HSM/KMS or a custody API that supports Ed25519 — never in app code or env vars (verify current vendor Stellar support; do not assume).
- Reconcile ledger ⇄ on-chain (hot + deposit + cold − in-flight) every 5 min; alert on any drift.
- Monitor XLM low-water on every signing/fee account.

## What the Flutter client must NOT do
- ❌ Sign transactions, hold keys, query RPC
- ❌ Display or log USDC, addresses, tx hashes, fees in XLM, chain names
- ❌ Ship fields like `amount_usdc` / `solana_signature` / `chain` in DTOs — the contract is fiat-only

Support/debug screens may show a **support reference id** (ours), never a chain hash.
