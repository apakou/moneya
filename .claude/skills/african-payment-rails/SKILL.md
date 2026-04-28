---
name: african-payment-rails
description: African mobile money and fiat rails for MoneyA — provider selection per corridor (XOF, XAF, NGN, GHS, KES), onramp/offramp partners (Yellow Card, Fonbnk, Juicyway, Onafriq, Accrue), KYC tiers by jurisdiction, phone number formats, and regulator constraints (BCEAO, BEAC, CBN, BoG, CBK). USE WHEN the user mentions mobile money, MoMo, Orange Money, Wave, MTN, Airtel, Moov, onramp, offramp, XOF, XAF, CFA, naira, cedi, shilling, BCEAO, BEAC, CBN, or any African country regulator. DO NOT USE FOR on-chain USDC mechanics (see usdc-stablecoin-ops).
---

# African Payment Rails

## Corridors in scope (phased rollout)

| Phase | Corridor | Currencies | Why first |
|---|---|---|---|
| 1 | Senegal ↔ Côte d'Ivoire | XOF ↔ XOF | Same currency, Wave dominant, simple FX |
| 2 | XOF ↔ NGN | XOF ↔ NGN | Largest diaspora demand SN/CI → NG |
| 3 | XOF ↔ GHS | XOF ↔ GHS | MTN MoMo huge in Ghana |
| 4 | XAF ↔ XOF | Cameroon, Gabon ↔ UEMOA | CEMAC integration |
| 5 | +KES, +anglophone | Add Kenya, Ghana anglo corridors | Scale |

## Mobile money providers by country

| Country | Currency | Dominant MM | Others |
|---|---|---|---|
| Senegal | XOF | **Wave** (~60%), Orange Money | Free Money, Wizall |
| Côte d'Ivoire | XOF | Orange Money, MTN MoMo, **Wave** | Moov Money |
| Mali | XOF | Orange Money, Moov | Wave (growing) |
| Burkina Faso | XOF | Orange Money, Moov | |
| Benin | XOF | MTN MoMo, Moov | Celtiis |
| Togo | XOF | T-Money (Togocom), Flooz (Moov) | |
| Cameroon | XAF | **MTN MoMo**, Orange Money | |
| Gabon | XAF | Airtel Money, Moov | |
| Nigeria | NGN | Bank transfers (NIP), OPay, PalmPay | MTN MoMo (new), Airtel |
| Ghana | GHS | **MTN MoMo** (~80%), Telecel Cash, AirtelTigo | |
| Kenya | KES | **M-Pesa** (Safaricom) | Airtel Money |

## Onramp / Offramp partner matrix

| Partner | Onramp in | Offramp in | Notes |
|---|---|---|---|
| **Yellow Card** | NGN, GHS, KES, ZAR, XAF | same | Licensed in 20+ countries; good API; KYC required |
| **Fonbnk** | Airtime → USDC in 35+ countries | limited | Low-ticket only; airtime rails clever but slow |
| **Juicyway** | NGN | NGN, USD | Nigeria specialist, good NIP speed |
| **Onafriq** (MFS Africa) | 40+ countries via MM | same | Aggregator; single API for many MMs |
| **Accrue** | NGN, GHS, KES | same | Consumer-focused; API in beta |
| **Kotani Pay** | KES, UGX, GHS | same | Africa-native; stablecoin focus |
| **Fincra** | NGN, GHS | NGN, GHS | Business-focused; cards + MM |

**MVP recommendation**: Onafriq for breadth + Yellow Card for USDC conversion. Add Juicyway for NGN speed.

## Phone number normalization

Always store and transmit in **E.164** (`+221771234567`). Use `libphonenumber` or `phone_numbers_parser` Dart package.

Country detection order:
1. User's selected country at signup (authoritative).
2. SIM MCC/MNC if available (`sim_data` package, Android only).
3. Locale fallback.

Common mistakes to reject in validation:
- Local format with no country code (`0771234567` → prompt for country)
- Nigerian numbers without the `0` stripped after `+234`
- XOF operator prefix changes (Orange SN added digit in 2020)

## KYC tiers by regulator

### BCEAO (UEMOA — XOF countries)
| Tier | Daily limit | Monthly limit | Requirements |
|---|---|---|---|
| 1 | 200,000 XOF (~$330) | 2M XOF | Phone + name |
| 2 | 1M XOF (~$1,650) | 10M XOF | + ID photo |
| 3 | Unlimited | Unlimited | + proof of address + source of funds |

### BEAC (CEMAC — XAF countries)
Similar tiered structure; Cameroon enforces strictest.

### Nigeria CBN
- **BVN** (Bank Verification Number) required for meaningful limits.
- Tier 1 (no BVN): ₦50k/day, ₦300k balance cap.
- Tier 2 (BVN + ID): ₦200k/day, ₦500k balance cap.
- Tier 3 (full KYC): higher limits.
- ⚠️ CBN stance on crypto has been volatile — check current guidance before launch.

### Ghana BoG
PSP license or partnership required. Tiered KYC similar to BCEAO.

### Kenya CBK
Virtual asset service providers now regulated (2025 VASP act). Partnership with licensed entity required.

## FX quote handling

- Pull mid-market rate from backend (aggregates Coinbase, Binance, B2C2).
- Add spread per corridor (0.3–0.8%).
- **Quote TTL: 30 seconds** — re-quote before confirmation.
- Lock quote at swipe-to-confirm; honor for 60s for settlement.
- If settlement fails within lock window, refund and re-quote.

## SMS invite for escrow claim

Template (FR, for SN/CI/ML/…):
```
{sender_first_name} vous a envoyé {amount} {currency} sur MoneyA.
Téléchargez l'app pour le recevoir : https://moneya.app/claim/{token}
Expire dans 30 jours. Répondez STOP pour ne plus recevoir.
```

Template (EN, for NG/GH/KE):
```
{sender_first_name} sent you {amount} {currency} on MoneyA.
Download the app to claim: https://moneya.app/claim/{token}
Expires in 30 days. Reply STOP to opt out.
```

Use Twilio or Africa's Talking (cheaper in Africa). Always include STOP clause for regulatory compliance.

## Regulatory red flags to surface to user

- Receiver phone in a country with active sanctions → block.
- Sender cumulative monthly volume > Tier threshold → require KYC upgrade.
- Rapid structuring pattern (multiple transfers just under threshold in 24h) → flag for review.
- New account + immediate high-value transfer → manual review hold.
