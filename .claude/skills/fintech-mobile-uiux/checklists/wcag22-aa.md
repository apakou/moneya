# WCAG 2.2 AA — Flutter mapping

The full Web Content Accessibility Guidelines 2.2 success criteria, mapped to MoneyA's Flutter codebase. Items marked **[MUST]** auto-fail any UI/UX review if violated. Items marked **[SHOULD]** are strong preferences — flag as MEDIUM in review.

Reference: <https://www.w3.org/WAI/WCAG22/quickref/?currentsidebar=%23col_overview&levels=aa>

---

## 1. Perceivable

### 1.1.1 Non-text content (A) **[MUST]**
Every `Image`, `Icon`, `SvgPicture`, decorative background image needs a text alternative.
- **Decorative**: `ExcludeSemantics(child: ...)` or `Semantics(excludeSemantics: true)`.
- **Informative**: `Semantics(label: '...')` or wrap in `Tooltip(message: '...')` for icon buttons.
- Avatar initials (`JA`): always `ExcludeSemantics`.
- QR code: `Semantics(image: true, label: 'MoneyA QR code...')`.

### 1.3.1 Info and relationships (A) **[MUST]**
Use `Semantics(header: true)` for screen titles. Use `MergeSemantics` for grouped fields (avatar + name + verified badge).

### 1.3.5 Identify input purpose (AA) **[MUST]**
Set `autofillHints` on inputs:
- Phone: `[AutofillHints.telephoneNumber]`
- OTP: `[AutofillHints.oneTimeCode]`
- Name: `[AutofillHints.name]`
- Email: `[AutofillHints.email]`
- Birth date: `[AutofillHints.birthday]`

### 1.4.3 Contrast minimum (AA) **[MUST]**
- Body text < 18pt (or < 14pt bold): **≥ 4.5:1**
- Large text ≥ 18pt (or ≥ 14pt bold): **≥ 3:1**
- Logos and incidental text: exempt
- Verify with WebAIM contrast checker, not by eye.

### 1.4.4 Resize text (AA) **[MUST]**
Layout must survive `textScaler` up to 200% (most screens) without content loss. Hero numerics may clamp at 1.3 only if overflow is unavoidable.

### 1.4.5 Images of text (AA) **[MUST]**
Never bake text into images. Exception: logos and product photography.

### 1.4.10 Reflow (AA) **[MUST]**
At 320dp width, content must not require horizontal scrolling (except for inherently 2D content like data tables).

### 1.4.11 Non-text contrast (AA) **[MUST]**
- UI components (button borders, focus rings, input borders): **≥ 3:1** against adjacent colors.
- State indicators (selected tab underline, switch on-state): **≥ 3:1**.
- The 24% white outline on cards (`onBrandOutline`) on the brand gradient passes.

### 1.4.12 Text spacing (AA) **[MUST]**
Layout must survive these user-applied overrides without loss:
- Line height 1.5×
- Paragraph spacing 2×
- Letter spacing 0.12×
- Word spacing 0.16×

Don't use fixed-height containers around text.

### 1.4.13 Content on hover or focus (AA) **[SHOULD]**
Tooltips: dismissable, hoverable, persistent until dismissed. Flutter `Tooltip` defaults are acceptable.

---

## 2. Operable

### 2.1.1 Keyboard (A) **[MUST]**
All functionality accessible via keyboard / hardware switch / D-pad. Use `Focus`, `FocusableActionDetector`, `Shortcuts`, `Actions`. No mouse/touch-only flows.

### 2.1.2 No keyboard trap (A) **[MUST]**
Modals, sheets, and dialogs must allow Esc/back to dismiss. `BottomSheet` and `showModalBottomSheet` are fine; custom overlays need `RawKeyboardListener` for Esc.

### 2.4.3 Focus order (A) **[MUST]**
DOM/widget order = reading order = focus order.

### 2.4.4 Link purpose in context (A) **[MUST]**
"View" "Tap here" "Learn more" are forbidden. Use "View transaction details", "Read fee policy".

### 2.4.7 Focus visible (AA) **[MUST]**
Every focusable widget must have a visible focus indicator.
- `InkWell` / `IconButton`: set `focusColor: AppColors.onBrandOutline.withValues(alpha: 0.4)`.
- Custom widgets: wrap in `Focus` and render a 2dp `onBrandOutline` border when `hasFocus`.

### 2.4.11 Focus not obscured minimum (AA) **[MUST] [new in 2.2]**
The focused widget must not be entirely covered by sticky headers, FABs, snackbars, or modal sheets.
- Scroll into view on focus: use `Scrollable.ensureVisible(context)`.
- The home FAB must not cover the last list row when keyboard navigation lands there.

### 2.5.5 Target size (AAA, but treat as AA) **[MUST]**
**≥ 44×44 dp** for tap targets. Adjacent targets ≥ 8 dp apart.

### 2.5.7 Dragging movements (AA) **[MUST] [new in 2.2]**
Every drag/swipe action must have a single-pointer (tap) alternative.
- Swipe-to-pay: provide a "Tap to pay" affordance for users who can't swipe (motor, switch control).
- Swipe-to-dismiss notification: provide an explicit dismiss button.

### 2.5.8 Target size minimum (AA) **[MUST] [new in 2.2]**
Reaffirms ≥ 24×24 CSS pixel rule (≈ 24 dp). MoneyA enforces stricter 44 dp.

---

## 3. Understandable

### 3.1.1 Language of page (A) **[MUST]**
Set `MaterialApp(locale: ...)` and `localeListResolutionCallback`. Don't rely on system default alone.

### 3.2.1 On focus (A) **[MUST]**
Focusing an input must NOT submit, navigate, or open modals. Common violation: auto-advancing OTP fields without a clear pattern.

### 3.2.2 On input (A) **[MUST]**
Changing input value must NOT navigate or submit. Submission requires explicit user action (button/swipe).

### 3.3.1 Error identification (A) **[MUST]**
Errors identified in **text** (not just color/border). Pattern:
```
[!] Phone number must start with country code
```

### 3.3.2 Labels or instructions (A) **[MUST]**
Every input has a visible label. Placeholder is not a label.

### 3.3.3 Error suggestion (AA) **[MUST]**
Tell the user how to fix. "Invalid" is forbidden. "Phone number must start with +" is correct.

### 3.3.4 Error prevention (legal, financial, data) (AA) **[MUST]**
For money movement and account deletion:
- Reversible: provide an undo window.
- Checked: confirmation screen with values.
- Confirmed: explicit confirmation gesture (passcode + swipe).

### 3.3.7 Redundant entry (A) **[SHOULD] [new in 2.2]**
Don't make users re-enter info already provided in the same flow (phone, name, etc.) — pre-fill and let them edit.

### 3.3.8 Accessible authentication (minimum) (AA) **[MUST] [new in 2.2]**
Authentication must not require:
- Solving a cognitive puzzle (selecting all squares with traffic lights).
- Memorizing or transcribing if avoidable.

Allowed: passcode (memorized — but biometric alternative offered), OTP (transcribed but autofilled via `AutofillHints.oneTimeCode`).

---

## 4. Robust

### 4.1.2 Name, role, value (A) **[MUST]**
Every interactive widget exposes name + role + value:
- Custom switch: `Semantics(toggled: bool, child: ...)`.
- Custom slider: `Semantics(slider: true, value: '...', increasedValue: '...', decreasedValue: '...')`.
- Custom tab: `Semantics(button: true, selected: bool, label: 'X tab')`.

### 4.1.3 Status messages (AA) **[MUST]**
Async results announce via `SemanticsService.sendAnnouncement(View.of(context), msg, Directionality.of(context))`. Update visual + haptic + announcement together. Inline status that updates in place: wrap in `Semantics(liveRegion: true)`.

---

## Quick auto-fail list (when reviewing)

If any of these are found, the screen FAILS review immediately:

1. `Colors.white.withOpacity(0.3)` (or similar) used for body text on the brand gradient.
2. `IconButton` with no `tooltip:` and no `Semantics(label:)`.
3. `withOpacity` used anywhere (deprecated; use `withValues(alpha:)`).
4. Tap target visibly < 44 dp.
5. Error state communicated by red border alone, no text.
6. Status state communicated by color alone (no icon).
7. Account/phone number Text without spaced-digit `Semantics(value:)`.
8. Disabled CTA with no `Semantics(hint:)` explaining how to enable.
9. Swipe-only action (no tap fallback).
10. Hard-coded English string in user-facing copy (must be localized).
