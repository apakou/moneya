---
name: fintech-mobile-uiux
description: Mobile UI/UX expertise for MoneyA — WCAG 2.2 AA accessibility, fintech trust patterns, microcopy, motor-accessibility, dark-bg contrast tokens, screen-reader semantics in Flutter, and money-screen conventions (tabular figures, digit spell-out, textScaler clamping, swipe-to-confirm, biometric-step-up affordances). USE WHEN the user mentions accessibility, a11y, WCAG, contrast, screen reader, TalkBack, VoiceOver, Semantics, tooltip, microcopy, copy review, "is this accessible", trust, error states, loading states, empty states, swipe-to-pay, confirmation UX, haptics, focus ring, tap target, color blindness, or asks for a UI/UX review of a screen. DO NOT USE FOR backend security (see fintech-security), folder structure (see flutter-architecture), or African-specific payment-rail UX copy nuances (see african-payment-rails).
---

# MoneyA Mobile UI/UX Patterns

A reference for building **trustworthy, inclusive, fast** money screens. This skill is opinionated and prescriptive — when in doubt, follow it.

> The whole point of a fintech UI is to make people feel safe moving money. Every contrast failure, ambiguous label, or unlabeled icon is a trust failure.

---

## 1. Brand & color tokens (always reference these)

All foreground decisions on the brand gradient (`AppColors.brandGradient`) MUST use the named tokens in `lib/core/theme/app_colors.dart`. Do not write `Colors.white.withValues(alpha: x)` inline.

| Token | Use for | Min contrast on brand bg | Min contrast on white |
|---|---|---|---|
| `onBrand` (#F2ECEC, ~95%) | Primary copy, hero numbers, CTA labels | 4.5:1 | n/a |
| `onBrandSecondary` (90% white) | Body copy, list rows, descriptions | 4.5:1 | n/a |
| `onBrandHint` (75% white) | Input placeholders, hint text | 4.5:1 | n/a |
| `onBrandTertiary` (60% white) | **Ornament only** — dividers, decorative numerals. NEVER body text. | 3:1 (UI) | n/a |
| `onBrandOutline` (24% white) | Borders, focus rings, divider strokes | 3:1 (UI) | n/a |
| `onBrandDisabled` (50% white) | Disabled foreground | 3:1 | n/a |
| `actionPurple` (#B200D6) | Primary CTA fill on white surfaces | n/a | 4.5:1 (white text on it) |
| `brandPurpleDeep` (#2B0033) | Receipt/QR text on white surfaces | n/a | 13:1 |
| `success` (#22C55E) | Status icons/text on **dark** bg | 4.5:1 | fails |
| `successOnLight` (#16A34A) | Same on white bg | fails | 4.5:1 |
| `warning` (#FBBF24) | Status on dark bg | 8:1 | fails |
| `danger` (#FF4D2E) | Destructive icons/text everywhere | 4.5:1 | 4.5:1 |
| `successSoft` / `warningSoft` / `dangerSoft` | 20%-alpha backgrounds for status pills | — | — |

**Rules:**
- Status state pills must combine **icon + text + color** (never color alone — color-blind users).
- Disabled CTA = `actionPurple @ 35% alpha` (project convention; do NOT change).
- Dividers on dark bg: prefer `onBrandOutline` (24%), not 10–18% alpha (fails 3:1).
- Cards on brand bg: 8% white surface + 24% white border. 6/10 fails.

---

## 2. Typography for money

Numeric data is *the product*. Treat it like a logo.

```dart
TextStyle(
  fontFeatures: const [FontFeature.tabularFigures()],
  fontVariations: const [FontVariation('wght', 600)],
)
```

| Context | Apply tabular figures? | Notes |
|---|---|---|
| Hero balance / receipt amount | YES | And clamp `textScaler` to 1.3 max so Dynamic Type doesn't blow layout. |
| Account number, IBAN, card number | YES | Group with thin spaces (3-3-3 or 4-4-4-4). |
| Amount input fields | YES | Prevents column-shift while typing. |
| Phone fields | YES | E.164 readability. |
| Transaction list amounts | YES | Right-aligned column needs constant width. |
| Body text, labels | NO | Default proportional figures. |

**`textScaler` clamping:**

```dart
MediaQuery(
  data: MediaQuery.of(context).copyWith(
    textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
  ),
  child: heroAmount,
)
```

Apply this **only** to hero numerics that risk overflow. Don't clamp body copy — Dynamic Type users need it.

**Font weight ladder on dark bg:** add ~100 weight vs. light bg. If the spec says w500 on white, use w600 on the brand gradient. Thin strokes lose contrast.

---

## 3. Accessibility (WCAG 2.2 AA — non-negotiable)

The full bundled checklist lives at `checklists/wcag22-aa.md`. Read it before reviewing any screen. The summary below is just the must-pass items.

### Contrast (1.4.3 / 1.4.11)
- Body text: **≥ 4.5:1**.
- Large text (≥18pt or ≥14pt bold) and UI components/borders: **≥ 3:1**.
- Use `https://webaim.org/resources/contrastchecker/` math; don't eyeball.

### Tap targets (2.5.8)
- **Minimum 44×44 dp** (iOS HIG) / 48×48 dp (Material 3). Wrap small glyphs in a padded `GestureDetector`/`InkWell` to reach this — don't just enlarge the icon.
- Adjacent tappable targets must have ≥8 dp spacing.

### Focus visibility (2.4.7 / 2.4.13)
- Every interactive widget needs a **visible focus ring**. Flutter's default `InkWell` focus is invisible on the brand gradient — set explicit `focusColor` + `highlightColor` to `onBrandOutline`.
- Focus order matches reading order.

### Screen-reader semantics
Every interactive element must have one of:
- `Semantics(button: true, label: '...', hint: '...')`
- `Tooltip(message: '...')` (also serves as a11y label on icon-only buttons)
- `MergeSemantics` for grouped identity blocks (avatar + name + status → 1 node)

**Anti-patterns (auto-fail in review):**
- `IconButton(icon: ...)` with no `tooltip` → screen reader announces glyph name.
- Letter-by-letter strings in `JA` avatars without `excludeSemantics: true` → "J, A" spellout.
- Long account numbers without spaced digits in `Semantics(value: ...)` → "two hundred forty thousand…".

### Live announcements
For async results (lookup found / payment sent / copied), parity is required:
1. Visual feedback (snackbar / inline state).
2. Haptic feedback (`HapticFeedback.selectionClick()` for soft, `.mediumImpact()` for confirmation).
3. **Screen-reader announcement** via `SemanticsService.sendAnnouncement(View.of(context), msg, Directionality.of(context))`.

`SemanticsService.announce(...)` is deprecated as of Flutter 3.35 — use `sendAnnouncement` with a `FlutterView`.

### Inputs
- Every `TextField` needs a visible label (not just placeholder — placeholders disappear on focus).
- `keyboardType`, `textCapitalization`, `textInputAction` always set explicitly.
- Phone fields: `keyboardType: TextInputType.phone`, never `.number`.
- Amount fields: `keyboardType: TextInputType.numberWithOptions(decimal: true)` (locale-aware decimal).
- Error messages live below the field, in `danger`, with an icon — never red border alone.

### Motion (2.3.3)
- Honor `MediaQuery.of(context).disableAnimations`. Long crossfades should collapse to instant when set.
- Confetti / spring overshoot animations must be skippable.

---

## 4. Screen-reader semantics — concrete recipes

### Identity block (avatar + name + verified badge)
```dart
MergeSemantics(
  child: Column(children: [
    ExcludeSemantics(child: _Avatar(initials: 'JA')),
    Text(name),
    Row(children: [Icon(Icons.verified), Text('Verified')]),
  ]),
)
// Reads as: "Jane Adekunle, Verified"
```

### Account number for screen readers
```dart
Semantics(
  label: 'Account number',
  value: digits.split('').join(' '), // "2 4 0 9 8 7 6 3 1"
  readOnly: true,
  child: Text(formatAccountNumber(digits)), // "240 987 631"
)
```

### Tab/segmented control
```dart
Semantics(
  button: true,
  selected: isActive,
  label: '$label tab',
  hint: 'Double tap to switch',
  child: GestureDetector(...),
)
```

### Disabled CTA — explain WHY
```dart
Semantics(
  button: true,
  enabled: canSubmit,
  label: 'Send money',
  hint: canSubmit
    ? 'Swipe right to confirm'
    : 'Enter recipient and amount to enable',
  child: AbsorbPointer(absorbing: !canSubmit, child: ...),
)
```

### Live status row
```dart
Semantics(
  liveRegion: true,
  label: switch (state) {
    Looking() => 'Searching for recipient',
    Found(:final name) => 'Found $name, verified MoneyA member',
    NotFound() => 'No MoneyA account on this number',
  },
  child: ...,
)
```

### Header
```dart
Semantics(header: true, child: Text('Receive', style: ...))
```

---

## 5. Microcopy (the bundled `checklists/microcopy.md` has the full list)

Plain-language fintech voice. No marketing-speak in flows users invoke under stress.

### Tone
- Direct, second person, present tense.
- Verbs over nouns: "Send" not "Initiate transfer".
- Numbers as digits, currency code AFTER the amount: `"5 000 XOF"` not `"$5,000"`.
- Never say "USDC", "blockchain", "crypto", "stablecoin", "wallet" in normal-user UI.

### Button labels
| Bad | Good |
|---|---|
| OK | Send money |
| Cancel (in destructive flow) | Keep account |
| Submit | Confirm transfer |
| Done | Got it |
| Try again | Retry payment |
| Yes / No | Send · Cancel |

### Error copy
- Lead with what happened, not the error code.
- Tell them what to do next.
- Never blame the user.

| Bad | Good |
|---|---|
| Invalid input | Phone number must start with country code |
| Network error | Couldn't reach our servers. Check your connection and try again. |
| Insufficient funds | You need 1 200 XOF more to send this. Top up? |
| Authentication failed | Wrong passcode. 2 tries left before lockout. |

### Empty states
Always tell the user (1) what should be here, (2) how to get there.

```
"No transactions yet
When you send or receive money, it'll show up here.
[Send money] [Receive money]"
```

### Loading states
- Skeleton placeholders for lists (not spinners).
- Spinners only for ≤ 2-second operations.
- > 2 seconds: progress text ("Sending… don't close the app").
- > 10 seconds: actionable copy + cancel option.

### Confirmation copy
| Step | Copy |
|---|---|
| Pre-confirm | "You're sending **5 000 XOF** to **Awa Diop** at **+221 77 123 4567**." |
| Action label | "Swipe to send" (not "Confirm") |
| Post-success | "Sent. **5 000 XOF** is on its way." |
| Pending | "On its way. We'll let you know when it lands." |
| Failed | "Couldn't send. Your money is still in your account." |

The "your money is safe" reassurance is **mandatory** on every failure screen.

---

## 6. Trust patterns (fintech-specific)

The bundled `checklists/trust-patterns.md` has the full set. Highlights:

### Money is sacred
- Never animate money values incrementing/decrementing for show.
- Loading states never display fake amounts. Show `—` or skeleton.
- Currency switching: **relabel only**. Do not silently FX-convert without an explicit quote screen.
- Round-trip every amount through `int minorUnits` — UI receives a formatted string from a single formatter, never builds it inline.

### Step-up authentication
| Action | Auth required |
|---|---|
| View balance | Session token |
| View transaction list | Session token |
| Send < threshold | Biometric OR passcode |
| Send ≥ threshold | Passcode (always) |
| Add new recipient | Biometric/passcode |
| Change passcode | Current passcode + biometric |
| Delete account | Passcode + 24h cool-off |

### Receipt aesthetics
- Receipts feel like paper. Sawtooth top/bottom edges, dashed dividers, tabular monospace numbers, signed amount in hero, `brandPurpleDeep` text on white.
- Reference number copyable. Phone number copyable.
- Always include "Saved to your transactions" footer + share/download CTAs.

### Reversibility cues
- Destructive actions (delete account, remove recipient): use `danger` + confirmation dialog with the specific noun ("Delete account?" not "Are you sure?").
- "Undo" toast for soft-destructive (clear filter, archive notification) — 5-second window.

### Status disclosure hierarchy
1. **Pending** (sent, awaiting settlement) — neutral blue/gray, never green.
2. **Success** — `success`/`successOnLight`, check icon.
3. **Failed** — `danger`, X icon. Always pair with "your money is safe".

### "No money was moved" guarantees
On every failure screen, top of body:
> Your money is still in your account.

Trust > brevity.

### Quote locking
- Show countdown if quote TTL ≤ 60s.
- On expiry: re-quote, show diff explicitly ("Rate changed: you'll now receive 8,130 XOF instead of 8,140").
- Never silently re-quote.

---

## 7. Motor accessibility (the bundled `checklists/motor-a11y.md` has the full set)

- Tap targets ≥ 44 dp.
- No timed dismissals on critical info — snackbars stay until dismissed if they describe failures.
- Swipe-to-confirm: completion threshold ≥ 70%; haptic at 50% (start) and 100% (commit). Cancellation by release before threshold.
- All swipes have a tap fallback for people who can't swipe (motor impairment, prosthetics, switch control).
- No "long-press only" actions for primary flows.
- `ReorderableListView` always has accessibility action handlers (`onReorder` is not enough).

---

## 8. Internationalization gotchas (cross-link to `i18n-auditor`)

- French digit grouping: `1 234,56` (thin space + comma decimal). English: `1,234.56`.
- Currency code position varies: `5 000 XOF` (FR), `XOF 5,000` (EN-style some apps). Pick one and stay consistent — MoneyA convention is **amount + space + ISO code, suffix**.
- RTL not currently supported but write `Directionality.of(context)` correctly so we don't refactor later.
- Pluralization: `intl` `Intl.plural`. Never string-template `"$count items"`.
- Phone format hints localize ("Format: +XX X XX XX XX XX" for FR, "Format: +XX XXX XXX XXXX" for EN).

---

## 9. Performance UX

- First meaningful paint < 1s on mid-range Android (Tecno Spark, Itel A-series).
- Hero amounts render before transaction list (skeleton list while balance is up).
- Avoid `setState` rebuilds of money-displaying widgets — wrap in `Selector`/`select` to scope.
- Network failures show stale-cached state with a "Last updated 2 min ago" badge, not a blank.
- Image assets: lazy-load avatars; show colored initials placeholder always.

---

## 10. Standard headers (project convention)

All non-tab screens (Transfer, Confirm, Receive, Profile, Settings, TransactionDetail) use:

- Padding: `EdgeInsets.fromLTRB(8, 4, 24, 0)`.
- Left: `IconButton` chevron (`Icons.chevron_left_rounded`, 28dp), with `tooltip: 'Go back'`.
- Center: `Text(title, style: 17sp w600, color: AppColors.onBrand)`, wrapped in `Semantics(header: true)`.
- Right: optional action icon, ≥44dp, with `tooltip:`.

---

## 11. Review checklist (the one-page version)

For every screen, verify:

- [ ] All foreground colors use named `AppColors` tokens (no inline `Colors.white.withValues(...)`).
- [ ] Body text ≥ 4.5:1 contrast on its background.
- [ ] All icon-only buttons have `tooltip:` AND/OR `Semantics(label:, button: true)`.
- [ ] Interactive widgets ≥ 44×44 dp.
- [ ] `MergeSemantics` on grouped identity blocks.
- [ ] Numeric data uses `FontFeature.tabularFigures()`.
- [ ] Hero amounts clamp `textScaler` to 1.3.
- [ ] Account/phone numbers in `Semantics(value: spaced-digits)`.
- [ ] Async outcomes have `SemanticsService.sendAnnouncement` + haptic + visual.
- [ ] Disabled CTA semantics explain WHY (`hint: 'Enter X to enable'`).
- [ ] Status (success/warning/danger) uses icon + text + color, not color alone.
- [ ] Error copy uses plain language and tells the user what to do next.
- [ ] Failure screens contain "your money is safe" reassurance.
- [ ] No "USDC"/"blockchain"/"wallet" leaking into normal-user copy.
- [ ] Live regions on status rows that update async.
- [ ] Visible focus ring on every focusable widget (`focusColor` + `highlightColor`).
- [ ] No timed dismissals on failure information.
- [ ] No color-only state communication (color-blind safe).

---

## 12. Hard rules

- Never use `withOpacity` — use `withValues(alpha: ...)`.
- Never use `Colors.X` directly in feature code — go through `AppColors`.
- Never use `print` — `debugPrint` only, gated by `kDebugMode`.
- Never animate money values for visual flair.
- Never silently FX-convert.
- Never commit a screen without screen-reader semantics.
- Never use `Tooltip` as the **only** label on a button — pair with `Semantics(button: true)` for swipe-control users who don't long-press.
- Never include emojis in money screens (project convention).

---

## 13. Bundled resources

- `checklists/wcag22-aa.md` — full WCAG 2.2 AA criteria mapped to Flutter.
- `checklists/microcopy.md` — full microcopy library by screen-type.
- `checklists/motor-a11y.md` — motor accessibility criteria.
- `checklists/trust-patterns.md` — fintech trust patterns library.
- `checklists/review-template.md` — the output format for UI/UX reviews.

When asked to "review screen X", always read the relevant bundled files first.
