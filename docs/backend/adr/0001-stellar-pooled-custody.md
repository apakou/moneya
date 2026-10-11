# ADR 0001 — Stellar settlement, pooled custody, fiat-denominated balances

Status: **Accepted** (2026-10-10). Closes DEC-01; supersedes the Solana/Privy assumptions in `architecture.md`, `ledger.md`, `backlog.md` (see plan Appendix B).

| # | Decision | Outcome | Confirmed by |
|---|----------|---------|--------------|
| D1 | Custody model | **Pooled custody.** One treasury (hot + cold) holds all settlement funds; users have ledger balances only; MoneyA→MoneyA sends are ledger-only; the chain is touched at top-up credit and cash-out debit. | Owner |
| D2 | Ramp provider | Yellow Card primary, licensed SEP-24 anchor fallback. Stellar support in its Payments API still unconfirmed (RMP-00). | Decided earlier |
| D3 | Launch corridor | **One corridor first, from Yellow Card's current list: GHS (Ghana).** KES next. XOF/XAF follow via the mobile-money aggregator path. | Owner confirmed the plan's recommendation (GHS or KES); GHS picked as the first one by the implementer — **owner to veto** |
| D4 | Key custody | KMS/HSM-backed signer (Ed25519) + native Stellar multisig thresholds on cold/treasury. Provider (cloud KMS / Turnkey / Fireblocks) is chosen in STL-03 after verifying current Stellar support. Privy is not assumed. | Owner |
| D5 | Licensing | Confirm VASP/MTL posture for Ghana before mainnet; not an engineering gate for testnet/staging. | Owner |
| D6 | Backend location | `backend/` monorepo folder. | Decided earlier |
| D7 | Currency of user balances | **(b) Fiat-denominated per-user ledger.** Each user's balance is held in their fiat currency; conversion happens at top-up and cash-out at a locked quote rate. Balances never move with FX. The treasury (MoneyA) carries the FX exposure between conversions, priced into the spread and bounded by limits. | Implementer (delegated by owner) |

## D7 consequences

- `USER_WALLET` ledger accounts are per `(user, fiat currency)`; settlement-asset accounts (`TREASURY`, `SUSPENSE`, in-flight) are in the settlement unit. Cross-currency postings go through an FX account so every journal balances per currency.
- A quote fixes `{fiat amount, settlement amount, rate, fee, expires_at}`; it is the only place the rate appears.
- A cross-currency MoneyA→MoneyA send is out of scope for the MVP launch corridor (single currency, GHS) and rejected explicitly.
- Treasury FX exposure limits and hedging policy are a finance follow-up before mainnet; the ledger exposes the net open position per currency for it.

## Rejected alternatives
- Per-user Stellar accounts (plan Appendix A): ≈ +10 IED, trustlines/reserves/key provisioning per user.
- USD-denominated user ledger shown at live rate: balances drift without user action.
- Solana/Base: replaced by Stellar (settled earlier).

## Open
RMP-00 (Yellow Card written answer) and the KMS provider choice (STL-03) remain open; STL-02..06 and M6/M7 stay gated on RMP-00.

## Addendum (2026-10-11) — scope of the first release

The owner states that the product's main purpose is moving money easily and cheaply **between francophone and anglophone African countries**. That makes the first release a **currency pair, not a single currency**, and supersedes two statements above: D3's "one corridor, GHS (Ghana)" as a single market, and D7's "a cross-currency send is out of scope for the MVP launch corridor … and rejected explicitly". The D7 design itself (fiat-denominated per-user ledger, conversion at a locked quote, FX accounts so journals balance per currency) is unchanged and is what makes the cross-currency send possible. The launch pair (proposed: Ghana ⇄ Côte d'Ivoire / Togo) and the cross-currency send tickets still have to be agreed and added to `stellar-mvp-plan.md`.

