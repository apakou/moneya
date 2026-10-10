# Microcopy library — MoneyA

Plain-language fintech voice for African + diaspora users. French and English primary.

---

## Voice principles

- **Direct.** Verbs over nouns. "Send" not "Initiate transfer".
- **Calm.** Stress is the enemy in money apps. Avoid exclamation marks.
- **Specific.** Use the actual number, name, currency. "5 000 XOF to Awa" beats "the amount".
- **Honest.** When something fails, say so. Don't soften with "Oops!" or "Whoops!".
- **No jargon.** Never say USDC, stablecoin, blockchain, wallet, on-chain, gas, RPC.
- **No emojis** (project convention).

---

## Currencies and amounts

- ISO code AFTER amount, single space: `5 000 XOF`, `120,50 USD`.
- French: thin space thousand sep + comma decimal: `1 234,56 XOF`.
- English: comma thousand sep + period decimal: `1,234.56 NGN`.
- Zero-decimal currencies (XOF, XAF): never show `,00` or `.00`.
- Phone: always E.164 with spaces in display: `+221 77 123 4567`.

---

## Buttons

| Don't | Do | When |
|---|---|---|
| OK | Send | Generic confirm in a money flow |
| OK | Got it | Acknowledge an info dialog |
| Cancel | Keep account | Destructive flow opt-out |
| Cancel | Discard | Modal discard intent |
| Submit | Confirm transfer | Pre-confirm screen |
| Submit | Save profile | Settings |
| Try again | Retry payment | Recoverable failure |
| Done | Done | Final neutral close (genuinely done) |
| Done | View transaction | Post-success in transfer flow |
| Yes / No | Send · Cancel | Two-action dialog |
| Continue | Send 5 000 XOF | When the action is monetary, name it |

---

## Headings and titles

- Imperative + specific: "Confirm payment" not "Payment confirmation".
- Titles short, ≤ 3 words. "Receive money" not "Receive money from contacts".
- Section labels uppercase, tracked: `FROM`, `AMOUNT`, `NOTE (OPTIONAL)`.

---

## Empty states

Three jobs: explain what's missing, why, and the next action.

```
"No transactions yet"
"When you send or receive money, it'll show up here."
[Send money] [Receive money]
```

```
"No saved recipients"
"People you send to often will appear here."
```

```
"No notifications"
"You're all caught up."
```

---

## Loading states

| Duration | Pattern |
|---|---|
| < 800 ms | No spinner. Optimistic update. |
| 800 ms – 2 s | Inline spinner, no copy. |
| 2 s – 8 s | "Sending… don't close the app." |
| > 8 s | Progress text + cancel option: "This is taking longer than usual. [Cancel]" |
| > 30 s | Failure message: "Couldn't reach our servers. Your money is still in your account." |

Never show fake amounts during loading. Use `—` or skeleton.

---

## Error copy

### Network
- "Couldn't reach our servers. Check your connection and try again."
- "You're offline. Some features won't work until you reconnect."

### Auth
- "Wrong passcode. {N} tries left before lockout."
- "Too many wrong attempts. Try again in {duration}."
- "Couldn't verify your fingerprint. Use your passcode."

### Validation
- "Phone number must start with country code (e.g. +221)."
- "Amount must be at least 100 XOF."
- "You can send up to 50 000 XOF per day at this account level. [Upgrade KYC]"

### Money flows (CRITICAL)
- **Insufficient balance:** "You need 1 200 XOF more to send this. [Top up]"
- **Failed send:** "Couldn't send to {name}. Your money is still in your account."
- **Pending:** "On its way to {name}. We'll let you know when it lands."
- **Recipient blocked:** "We can't send to this number right now."
- **KYC limit:** "You've hit your daily limit. Upgrade your account to send more."
- **Recipient KYC:** "{name} needs to complete KYC before they can receive this. We've sent them a link."

### Quote expiry
- "Rate updated: they'll now receive 8,130 XOF (was 8,140). Confirm new amount?"

---

## Success copy

- **Sent:** "Sent. **5 000 XOF** is on its way to **Awa Diop**."
- **Received:** "**5 000 XOF** from **Awa Diop**."
- **Pending:** "On its way. **5 000 XOF** to **Awa Diop**."
- **Saved:** "Profile updated."
- **Copied:** "Copied to clipboard." (also announced via SemanticsService)

---

## Pre-confirmation screens

Format: "You're sending **{amount}** to **{name}** at **{phone}**."

Always include:
- Amount in bold, with currency code.
- Recipient name in bold.
- Phone number in standard format.
- Fee, if any, on its own line: "Fee: 50 XOF".
- "Total" line if fee is nonzero.

Action: "Swipe to send" (not "Confirm").

---

## Dialogs

### Destructive
Title: noun + question. "Delete account?" "Remove recipient?"
Body: consequence in plain language. "This will permanently erase your transaction history. You can't undo this."
Actions (in order): `[Keep account] [Delete]` — destructive on the right.

### Confirmation
Title: imperative. "Confirm passcode change"
Body: what's about to happen and why.
Actions: `[Cancel] [Continue]`.

---

## Status pills

| State | Icon | Color | Text |
|---|---|---|---|
| Sent | check_circle | success | "Sent" |
| Received | call_received | success | "Received" |
| Pending | schedule | onBrandSecondary (neutral) | "Pending" |
| Failed | error_outline | danger | "Failed" |
| Processing | sync | onBrandSecondary | "Processing" |
| Refunded | refresh | success | "Refunded" |

Never use color alone. Always icon + text.

---

## Accessibility hints (the `Semantics(hint:)` strings)

- "Double tap to switch tab"
- "Double tap to copy"
- "Double tap to share"
- "Swipe right to confirm"
- "Enter recipient and amount to enable"
- "Long press to reorder"
- "Currently selected"

---

## Forbidden phrases (project lint)

- ❌ "USDC"
- ❌ "stablecoin"
- ❌ "blockchain"
- ❌ "crypto"
- ❌ "wallet" (use "account")
- ❌ "Oops!" / "Whoops!" / "Uh oh"
- ❌ "We're sorry" (apologetic tone — replace with action)
- ❌ "Please" (in buttons — use direct verb)
- ❌ "Loading…" (use specific verb: "Sending…", "Searching…")
- ❌ "Click" (mobile) — use "Tap" or imperative
- ❌ Emojis in money flows
