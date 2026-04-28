---
name: usdc-stablecoin-ops
description: USDC stablecoin operations for MoneyA — chain selection (Solana vs Base), SPL/ERC-20 transfer mechanics, gas/fee economics, escrow patterns for unclaimed transfers, RPC provider choices, and custody models. USE WHEN the user mentions USDC, stablecoin, on-chain, wallet, escrow, Solana, Base, blockchain, RPC, gas fees, or custody. DO NOT USE FOR fiat-only flows (see african-payment-rails) or KYC (see fintech-security).
---

# USDC Stablecoin Operations

## Chain decision: Solana (primary), Base (fallback)

| Criterion | Solana | Base | Ethereum L1 |
|---|---|---|---|
| Avg tx fee | ~$0.00025 | ~$0.01 | $1–20 ❌ |
| Finality | ~0.4s | ~2s (soft), 10min (hard) | 12+ min |
| USDC native | ✅ Circle-issued SPL | ✅ Circle-issued ERC-20 | ✅ |
| SDK maturity | `solana_web3` Dart is weak → use backend | `web3dart` works | `web3dart` works |
| Africa latency | Acceptable via EU RPC | Acceptable | Acceptable |

**Rule**: Never touch chain from the Flutter client. All on-chain ops go through our backend; the app sees only fiat-denominated balances and fiat-denominated quotes.

## Custody model (recommended for MVP)

**Pooled custodial wallet with per-user ledger.**

- One master hot wallet + one warm/cold treasury wallet.
- User balances tracked in **Postgres ledger** (double-entry), not on-chain.
- On-chain moves happen only at onramp settlement and offramp initiation.
- Internal MoneyA → MoneyA transfers are **ledger-only** (instant, free).

Trade-offs:
- ✅ Instant UX, no gas per transfer, simpler key mgmt.
- ❌ You are a money transmitter / VASP in most jurisdictions — need licensing.
- ❌ Must pass proof-of-reserves audits.

**Non-custodial alternative** (post-MVP): MPC wallets via Privy / Web3Auth / Turnkey, keyed by passcode + device. Defer until regulatory path is clear.

## Escrow pattern for unclaimed transfers

Receiver has no account yet:

1. Sender's fiat debit → USDC credited to **escrow sub-ledger** keyed by `sha256(recipient_e164 + salt)`.
2. SMS sent with `https://moneya.app/claim/<one-time-token>` (token TTL 30 days).
3. Recipient installs app, verifies phone via OTP.
4. Backend matches hashed phone → moves funds from escrow sub-ledger → new user's ledger.
5. **Reclaim policy**: after 30 days unclaimed, funds auto-return to sender (minus network fee if any).

Store the SMS invite text in both FR and EN; detect locale from the recipient's country code.

## Fee economics (per transfer, worst case)

```
Sender fiat onramp .......... 1.0–1.5%  (provider fee)
FX spread (fiat→USD) ........ 0.3–0.8%
On-chain settlement ......... ~$0.01 flat (Solana)
Receiver fiat offramp ....... 1.0–1.5%
FX spread (USD→fiat) ........ 0.3–0.8%
MoneyA margin ............... 0.5–1.0%
─────────────────────────────────────
Total to user ............... 3–5% typical
```

Compete against WorldRemit (~5%), Wise (~1.5% but no Africa MM), Wave (1%, intra-Africa only).

## RPC providers

| Provider | Solana | Base | Notes |
|---|---|---|---|
| Helius | ✅ | ❌ | Best Solana DX, webhooks for deposits |
| Triton | ✅ | ❌ | Low-latency RPC |
| Alchemy | ✅ | ✅ | Good multi-chain |
| QuickNode | ✅ | ✅ | Reliable |

Always configure **two independent providers** with failover.

## Circle CCTP (cross-chain transfer)

If you need to move USDC between Solana and Base (e.g., one partner only supports Base offramp), use Circle's CCTP — native burn/mint, no bridges. Backend responsibility only.

## Security essentials

- Hot wallet balance ≤ 24h of expected volume; sweep excess to warm/cold.
- Multi-sig (3-of-5) on treasury using Squads (Solana) or Safe (Base).
- Withdrawals above threshold require manual approval + Slack notification.
- Seed phrases in HSM / AWS KMS / GCP Cloud KMS — never in app code or env vars.
- Reconcile on-chain balance vs ledger sum **every 5 minutes**; alert on drift.

## What the Flutter client should NOT do
- ❌ Sign transactions
- ❌ Hold private keys
- ❌ Query RPC directly
- ❌ Display USDC, hex addresses, tx hashes, or gas to normal users

Power users / support screens may show tx hash behind a debug flag.
