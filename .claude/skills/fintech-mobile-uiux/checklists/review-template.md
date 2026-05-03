# UI/UX review output template

Every review produced by `fintech-uiux-reviewer` MUST follow this format. Findings without this structure are rejected.

---

## Header

```
# UI/UX review — <screen-name>

Files reviewed:
- lib/features/.../screen.dart
- lib/features/.../widgets/*.dart

Skill references applied:
- fintech-mobile-uiux SKILL.md §X, §Y
- checklists/wcag22-aa.md (criterion 1.4.3, 2.5.5, ...)
- checklists/microcopy.md
- checklists/motor-a11y.md
- checklists/trust-patterns.md
```

---

## Findings

For each finding:

```
[SEVERITY] [CATEGORY] file.dart:LINE
Issue: <one sentence — what's wrong>
WCAG: <criterion ID + name, if applicable, e.g. "1.4.3 Contrast (Minimum)">
Risk: <user impact — concrete, not abstract>
Fix: <proposed change, with code snippet if ≤6 lines>
```

### Severities

- **CRITICAL** — auto-fail. Includes:
  - Money-loss risk (silent FX, double-charge).
  - WCAG 2.2 AA violations affecting authentication or payments.
  - Forbidden copy ("USDC", "blockchain", "crypto").
  - Missing "your money is safe" reassurance on a failure screen.

- **HIGH** — must-fix before merge:
  - Body text contrast < 4.5:1 on user-facing screens.
  - Missing `tooltip:` / `Semantics(label:)` on icon-only buttons.
  - Tap target < 44 dp.
  - Color-only state indicators.
  - Disabled CTA without `Semantics(hint:)`.

- **MEDIUM** — fix this sprint:
  - Copy doesn't follow microcopy library.
  - Numeric data without `FontFeature.tabularFigures()`.
  - Visible focus ring missing on `InkWell`.
  - Live region missing on async status row.
  - Hero numerics not clamping `textScaler`.

- **LOW** — nice to have:
  - Token usage could be more idiomatic (`onBrandTertiary` instead of `Colors.white.withValues(alpha: 0.6)`).
  - Suggestion to merge two semantic nodes.
  - Ornamental contrast nit (passes 3:1 but feels weak).

### Categories

- `[A11Y]` — accessibility (semantics, focus, contrast, labels)
- `[MOTOR]` — tap targets, swipe alternatives, timeouts
- `[CONTRAST]` — color contrast specifically
- `[COPY]` — microcopy
- `[TRUST]` — fintech trust patterns
- `[I18N]` — localization
- `[PERF]` — performance UX
- `[NAV]` — navigation/focus order
- `[TOKEN]` — design token usage

---

## Example finding

```
[HIGH] [A11Y] receive_screen.dart:412
Issue: Phone-clear `GestureDetector` has no Semantics label and the tap zone is 20×20 dp.
WCAG: 2.5.5 Target Size (≥ 44×44 dp), 4.1.2 Name/Role/Value
Risk: Screen-reader users hear no name; motor-impaired users can't reliably hit the target.
Fix:
  IconButton(
    icon: const Icon(Icons.close, size: 20),
    tooltip: 'Clear phone number',
    onPressed: onClear,
    padding: const EdgeInsets.all(12),  // 20 + 24 = 44dp target
  )
```

---

## Summary table

End every review with this table:

| Severity | Count |
|---|---|
| CRITICAL | N |
| HIGH | N |
| MEDIUM | N |
| LOW | N |

And a one-line verdict:

```
Recommendation: SHIP / SHIP-AFTER-HIGH-FIXES / DO-NOT-SHIP
```

- `SHIP` — only LOW findings.
- `SHIP-AFTER-HIGH-FIXES` — HIGH/MEDIUM only, no CRITICAL.
- `DO-NOT-SHIP` — any CRITICAL.

---

## Hard rules for the reviewer

- Do NOT propose redesigns or large refactors. Targeted fixes only.
- Do NOT invent findings — every finding cites file + line number.
- Do NOT mark something CRITICAL unless it maps to the CRITICAL list above.
- Do NOT review code outside the requested screens.
- DO check token usage against `lib/core/theme/app_colors.dart`.
- DO read `SKILL.md` and the relevant `checklists/*.md` before reviewing.
- If you can't find a file, say so and list what you searched for.
