# Motor accessibility — MoneyA

Designing for users with limited dexterity, prosthetics, tremors, switch control, voice control.

---

## Tap targets

- **Minimum 44×44 dp** (iOS HIG) / **48×48 dp** (Material 3). MoneyA enforces 44 dp.
- Adjacent targets ≥ 8 dp apart.
- The visible glyph can be smaller — wrap in a padded container/InkWell to reach the target size.
- Verify with Flutter Inspector → "Show paint baselines" / a11y overlay.

```dart
// Bad: 20dp target
GestureDetector(onTap: clear, child: Icon(Icons.close, size: 20))

// Good: 44dp target, 20dp glyph
SizedBox(
  width: 44, height: 44,
  child: IconButton(
    icon: const Icon(Icons.close, size: 20),
    tooltip: 'Clear',
    onPressed: clear,
  ),
)
```

---

## Drag and swipe

WCAG 2.5.7 (new in 2.2) requires: **every drag action must have a single-pointer alternative.**

- Swipe-to-pay → also accept tap on a "Tap to pay" affordance for switch-control / one-finger users.
- Swipe-to-delete notification → also expose a visible "Dismiss" button on long-press / overflow menu.
- Pull-to-refresh → also expose a refresh icon in the header.
- ReorderableListView → also expose "Move up/down" via accessibility actions:

```dart
Semantics(
  customSemanticsActions: {
    const CustomSemanticsAction(label: 'Move up'): () => onMove(-1),
    const CustomSemanticsAction(label: 'Move down'): () => onMove(1),
  },
  child: ...,
)
```

---

## Swipe-to-confirm specifics

The MoneyA `SwipeToPayButton` pattern:

| Threshold | Behavior |
|---|---|
| 0% | Idle, label visible |
| 0–50% | Track follows finger; no haptic |
| 50% | `HapticFeedback.selectionClick()` (commitment cue) |
| 70%+ | `completionThreshold` reached; auto-complete on release |
| 100% | `HapticFeedback.mediumImpact()` (commit) + visual lock |
| Released < 70% | Spring back to 0%, no commit |

**Required:**
- `completionThreshold: 0.7` (default 0.9 too punishing for tremor users).
- A `Tap to confirm` fallback for non-swipe users — render a small text affordance below the swipe ("Or tap and hold to confirm") that opens a passcode entry as alternative.
- `Semantics(button: true, label: 'Swipe to send', hint: 'Swipe right to confirm')`.
- Disabled state: `AbsorbPointer` + `Semantics(enabled: false, hint: 'why disabled')`.

---

## Long press

- Never the only way to invoke a primary action.
- OK for secondary actions (copy text from a row, peek transaction details) IF a tap path also exists.
- Long-press duration: respect system setting (`HapticFeedback.longPress` triggers at ~500 ms default).

---

## Timeouts (WCAG 2.2.1)

- Critical info (failure messages, money outcomes): **never** auto-dismiss.
- Snackbars confirming success: 4–6 s acceptable.
- OTP entry timeout: ≥ 60 s; expose a "Resend code" affordance.
- Quote TTL: visible countdown; "Refresh quote" button before expiry.
- Idle session lock: ≥ 2 minutes for view-only screens; 30 s for in-flight transfer screens.

---

## Form inputs

- Don't auto-advance OTP fields on every keystroke — many users can't type fast enough; the field jumps and they re-enter. Auto-advance ONLY after pasting all digits.
- Don't reset input on validation error — keep the value, show the error inline.
- Don't disable submit while user is typing — validate on blur, not keystroke.

---

## Voice control / Switch control

- All interactive widgets need a unique, speakable label.
- "Tap on Send button" must work — so the label must be `Send`, not an SVG.
- Lists with many similar items: include row-specific labels ("Transaction with Awa, 5 000 XOF, sent").

---

## Tremor-friendly patterns

- Larger hit zones around small icons (44 dp wrappers).
- Confirmation step before destructive actions — never edge-swipe to delete a recipient without confirmation.
- Slider increments: prefer ±1 buttons alongside the slider for precise values.
- Number entry: prefer numeric keypad with large buttons over thumb-wheels.

---

## Audio cues (parity)

- Haptic feedback always pairs with semantic announcement; never assume the user feels the haptic (some prosthetics).
- System sounds disabled by default — never use sound-only feedback.

---

## Review auto-fail (motor)

1. Tap target < 44 dp.
2. Action invokable only by drag/swipe with no tap alternative.
3. Action invokable only by long-press with no other path.
4. Auto-dismissed failure message.
5. Form auto-advances per keystroke.
6. Critical action lacks confirmation step.
7. `SwipeToPayButton` with `completionThreshold > 0.8` (too punishing).
