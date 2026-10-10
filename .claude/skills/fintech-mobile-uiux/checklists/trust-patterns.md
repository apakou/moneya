# Trust patterns — MoneyA

The fintech-specific UX rules. Trust > brevity. Trust > cleverness.

---

## The three commandments

1. **Money is sacred.** Never animate money values for show. Never display fake amounts.
2. **Failures don't lose money.** Every failure screen says "Your money is still in your account."
3. **No surprises.** Never silently FX-convert. Never silently retry a payment. Never silently change a quote.

---

## Pre-action confirmation

For any money movement, the user sees three things in one glance:

```
[How much]   5 000 XOF        ← bold, hero size, tabular
[To whom]    Awa Diop         ← bold, name only
             +221 77 123 45 67  ← phone, formatted
[Fee]        50 XOF           ← if applicable
[Total]      5 050 XOF        ← if fee present
```

Action label: `Swipe to send` — verb + monetary nature implied.

Avoid: "Are you sure?" — instead, restate the action so the answer is "yes, send 5 000 to Awa".

---

## Step-up authentication

| User action | Auth required |
|---|---|
| Open app | Passcode OR biometric |
| View balance | None (already authed) |
| View transaction list | None |
| Send < 50 000 XOF (Tier 1) | Biometric OR passcode |
| Send ≥ 50 000 XOF | Passcode (always) |
| Add new recipient | Biometric/passcode |
| Save card | Passcode |
| Change passcode | Current passcode + biometric |
| Delete account | Passcode + 24 h cool-off period |
| Export transaction history | Passcode |

`local_auth` config for transactions:

```dart
options: const AuthenticationOptions(
  biometricOnly: true,        // never accept device PIN as fallback
  stickyAuth: true,
  sensitiveTransaction: true,
),
```

---

## Outcome screens (success / pending / failed)

All three share the `TransferOutcomeScaffold`. Differences:

| | Success | Pending | Failed |
|---|---|---|---|
| Glyph | check | clock | x |
| Glyph color | `success` | `onBrandSecondary` | `danger` |
| Title | "Sent" | "On its way" | "Couldn't send" |
| Body | Restates amount + recipient | Restates + "We'll let you know when it lands" | "Your money is still in your account." + reason |
| Primary CTA | "View transaction" | "View transaction" | "Retry payment" |
| Secondary | "Done" | "Done" | "Cancel" |

**Mandatory on failed:** "Your money is still in your account." Top of body. No exceptions.

---

## Receipt aesthetics

Receipts must feel like paper:

- White surface, `brandPurpleDeep` text.
- Tabular monospace numbers.
- Sawtooth top + bottom edges (visual cue for "physical receipt").
- Dashed dividers between sections.
- Signed amount as hero (`+5 000 XOF` green for received, `-5 000 XOF` deep purple for sent).
- Reference number copyable, with "Tap to copy" semantic hint.
- Phone number copyable.
- Footer: brand wordmark SVG.
- Share / Download buttons at bottom.

---

## Quote handling

If a quote is involved (FX, fee tier, dynamic pricing):

- Show TTL countdown only if remaining ≤ 60 s.
- < 10 s remaining: pulse the countdown gently.
- 0 s: re-quote automatically AND show the diff explicitly.

```
"Rate changed.
They'll now receive 8,130 XOF instead of 8,140.
[Confirm new rate]  [Cancel]"
```

Never silently re-quote.

---

## Currency switching

Project rule: **switching the currency dropdown relabels the input field; it does NOT FX-convert the amount.**

Example: user types `5000` in XOF → switches to USD → field shows `5000 USD` (not converted). Tooltip: "Currency only — amount stays the same".

Real FX requires the quote screen with explicit confirmation.

---

## Reversibility

| Action | Reversible? | UI |
|---|---|---|
| Sent payment (post-success) | No | "Contact recipient" only path |
| Saved recipient | Yes | "Remove" with confirm dialog |
| Notification dismissed | Yes (5 s) | "Undo" snackbar |
| Filter cleared | Yes | "Reapply" snackbar |
| Account deleted | Yes (24 h) | Cool-off countdown |
| Profile photo changed | Yes (immediate) | "Revert" available for 1 session |

---

## Status disclosure hierarchy

Always communicate state with **icon + text + color** (never color alone):

- Pending: clock + "Pending" + neutral color (NOT green, NOT red).
- Success: check + "Sent" + `success`.
- Failure: x + "Failed" + `danger`.
- In progress: spinner + "Sending…".

Color-blind users (~8% of men) cannot distinguish red/green. Icons are mandatory.

---

## Number formatting (the trust signal)

- Tabular figures everywhere amounts are shown (see `SKILL.md §2`).
- Right-align amounts in lists.
- Sign always explicit on transaction rows: `+5 000` / `-5 000`.
- Currency code suffix, never prefix: `5 000 XOF` not `XOF 5 000`.
- Zero-decimal currencies: never show `.00`.
- Locale-aware grouping: `1 234,56` (FR) / `1,234.56` (EN).

---

## Empty / new-user states

Build trust through transparency:

- Account number visible from day 1 (even before first transaction).
- KYC tier visible: "Tier 1 · Up to 50 000 XOF/day".
- Limit hit: "You've sent 48 000 of 50 000 XOF today. [Upgrade]"

---

## Notifications

- Money received: high priority, system push.
- Payment failed: high priority, system push + in-app banner.
- KYC update: medium priority.
- Promotions: low priority, in-app only, never push.

In-app notification sheet must:
- Group by 7-day rolling window.
- Show unread badge.
- "Mark all read" affordance.
- Tap → deep-link to relevant screen (transaction detail, KYC, etc.).

---

## Honesty patterns

- "Last updated 2 min ago" badge on stale data — better than blank.
- "Couldn't fetch latest" with cached value — better than spinner forever.
- "Approximate" tag on FX rates older than 30 s.
- Disclose fees BEFORE the amount field, not in a footnote on confirm.

---

## Forbidden trust violations

1. Auto-incrementing balance counter on screen load.
2. Spinner-only loading on amount-display widgets.
3. Showing a recipient as "verified" without checking the verification API.
4. Combining multiple transactions into a single row without disclosure.
5. Hiding the actual failure reason behind a generic "Something went wrong".
6. Pre-checking opt-in checkboxes for paid features.
7. Dark patterns in destructive flows ("Delete" red AND right-side, but a competing "Subscribe" CTA).
8. Showing FX rate without timestamp or TTL.
9. Truncating account numbers without `...` indicator.
10. Localizing currency CODE itself (XOF stays XOF in every language; only the position/grouping localizes).
