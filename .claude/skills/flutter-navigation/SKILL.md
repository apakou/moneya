---
name: flutter-navigation
description: Flutter 3.44+ navigation patterns for MoneyA — Android predictive-back compliance, PopScope (not WillPopScope), wizard step navigation, form-data discard dialogs, terminal-screen back-locks (success/failed/pending), bottom-sheet/keyboard dismissal, and a forward migration path from Navigator 1.0 (MaterialPageRoute) to go_router 14+. USE WHEN the user mentions back button, system back, predictive back, swipe back, gesture navigation, PopScope, WillPopScope, "Navigator.pop", deactivated widget error, wizard navigation, multi-step form, "lose form data", go_router, push/pushReplacement, or any screen that has discard-changes semantics. DO NOT USE FOR top-level bottom-nav tab switching (that's HomeShellController) or in-flow modal sheets (those are showModalBottomSheet, not Navigator).
---

# MoneyA Flutter Navigation & Back Handling

Authoritative source for back-button behaviour, predictive-back compliance, and the Navigator 1.0 → go_router 14+ migration path. Targets Flutter 3.27+ stable (project is currently on 3.41.9 stable) and Android 13+ (API 33+), where the predictive back gesture is the system default.

## 1. The root cause: Android predictive back

Since Android 13, the OS sends `onBackInvokedCallback` instead of `onBackPressed`. Flutter 3.27+ supports this — but only when the app opts in via the manifest. Apps that don't opt in get **silent crashes**: gesture swipes register as back events the framework can't route, often surfacing as the dreaded "Looking up a deactivated widget's ancestor" red screen on wizard / form flows where `Navigator.pop` runs against a stale `context`.

**Fix this once, project-wide:**

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application
    android:label="MoneyA"
    android:enableOnBackInvokedCallback="true"
    ...>
```

Without this flag, the rest of the rules below paper over symptoms — fix the manifest first.

iOS swipe-from-edge is unaffected — it just calls `Navigator.maybePop()` like the AppBar leading button.

## 2. `PopScope`, not `WillPopScope`

`WillPopScope` is **deprecated** as of Flutter 3.12 and is fundamentally incompatible with predictive back (it can't preview a back attempt without committing to it). Always use `PopScope`.

### Rule of thumb

| Need | Pattern |
|------|---------|
| Just observe back | `PopScope(onPopInvokedWithResult: (didPop, _) { … })` |
| Allow back unconditionally | No `PopScope` (default) |
| Block back unconditionally (terminal screens) | `PopScope(canPop: false)` |
| Block back conditionally (dirty forms, in-flight ops) | `PopScope(canPop: !isDirty && !isLoading, onPopInvokedWithResult: …)` |

**Never call `Navigator.pop` from inside `onPopInvokedWithResult` when `didPop == false`** — that re-enters the pop and crashes. Show a dialog, then call `Navigator.pop()` if the user confirms.

### Canonical dirty-form guard

```dart
PopScope(
  canPop: !_isDirty,
  onPopInvokedWithResult: (didPop, _) async {
    if (didPop) return; // user already left
    final shouldLeave = await _confirmDiscard(context);
    if (shouldLeave == true && context.mounted) {
      Navigator.of(context).pop();
    }
  },
  child: Scaffold(...),
)
```

`onPopInvoked` (no `WithResult`) is **also deprecated** as of Flutter 3.22. Always use `onPopInvokedWithResult` — the result parameter lets you carry a return value when the predictive-back gesture completes.

## 3. Wizard flows — each step is a route

The Load Money flow (`LoadProviderScreen` → `LoadAmountScreen` → `_LoadSuccessScreen`) is the canonical wizard pattern in this project. Rules:

1. **Each step is a real route** pushed with `Navigator.push(MaterialPageRoute(...))`. Never use `IndexedStack` or `PageView` for wizards — those break the system back gesture entirely (back exits the whole wizard instead of returning to the previous step).
2. **The first step header uses `Navigator.maybePop`** so the user lands back on the screen that opened the wizard (Home, Settings, etc.).
3. **Intermediate steps use `Navigator.maybePop`** to return one step. Predictive back handles this automatically — no extra wiring needed.
4. **The final / outcome step uses `popUntil((r) => r.isFirst)`** to drop the user back at Home, never to the form. See §4.
5. **State lives in the step that owns it.** Don't lift wizard state to a parent controller unless two steps need to mutate the same value. The simple `Navigator.push` pattern carries forward state via constructor arguments (`currency`, `country`, `provider`, …) — that's enough for 3-step wizards. Lift to Riverpod only when you have 4+ steps or cross-step validation.

### Anti-pattern: `pushReplacement` between wizard steps

```dart
// WRONG — kills the back gesture mid-wizard.
Navigator.pushReplacement(...LoadAmountScreen...);
```

`pushReplacement` removes the previous route from the stack, so swipe-back from step 2 exits the wizard. Use `push` between wizard steps and reserve `pushReplacement` for the final form → outcome transition (§4).

## 4. Terminal screens — lock back, route forward

Success / failed / pending outcome screens must not let the user navigate back to the form (re-submission risk, especially on debit flows). Two pieces:

1. **Use `pushReplacement` from the form to the outcome** so the form is no longer on the stack.
2. **Wrap the outcome `Scaffold` in `PopScope(canPop: false)`** so predictive back is a no-op. The primary CTA must call `popUntil((r) => r.isFirst)` — the back gesture intentionally does nothing.

```dart
return PopScope(
  canPop: false,
  child: TransferOutcomeScaffold(
    primaryLabel: 'Go back home',
    onPrimary: () => Navigator.of(context).popUntil((r) => r.isFirst),
    ...
  ),
);
```

This is **mandatory** for `PaymentSuccessScreen`, `PaymentPendingScreen`, `PaymentFailedScreen`, and `_LoadSuccessScreen`. Currently missing — add `PopScope(canPop: false)` to each.

## 5. Bottom sheets and keyboards do not need special handling

`showModalBottomSheet`, `showDialog`, and the soft keyboard are **not** routes in the Navigator's app-level sense — they're route-modal overlays that intercept back before the screen sees it. A back press while a sheet is open dismisses the sheet only. **Do not** add `PopScope` to a screen to "protect" it from a back press during a sheet; you'll double-handle the event.

The one exception: if you open a sheet that itself pushes a route (e.g. an in-sheet "Edit" button that navigates), close the sheet first (`Navigator.pop(sheetCtx)`) before pushing — otherwise back from the new route returns into a stale sheet context.

## 6. `BackChevronButton` rules

`lib/core/widgets/back_chevron_button.dart` exists specifically because synchronous `Navigator.pop` calls from `IconButton.onPressed` were crashing with "deactivated widget" errors when the parent rebuilt mid-pop. Rules:

- **All in-app back chevrons in the header row** use `BackChevronButton`, never raw `IconButton(icon: Icons.chevron_left)`.
- The `onTap` callback **must** call `Navigator.of(context).maybePop()` — never `pop()`. `maybePop` is a no-op if the route can't be popped (e.g. it's the first route) and returns `false` so callers can react; `pop` throws.
- Never call `Navigator.pop` from inside an `async` gap that re-enters the same `BuildContext`. Capture `Navigator.of(context)` to a local before the `await`:

```dart
final navigator = Navigator.of(context);
final result = await someAsyncWork();
if (!mounted) return; // StatefulWidget
navigator.pop(result);
```

For `StatelessWidget` (where there's no `mounted`), capture *both* the navigator and a `mounted` proxy via `context.mounted` check after the await.

## 7. Forms — discard-changes dialog

Any screen with form fields that hold user input must guard back with a discard-changes dialog. The form is "dirty" when **any** field deviates from its initial value (don't track `hasChanged` per field — diff against the initial snapshot). Reset the dirty flag after a successful submit so the post-submit back doesn't re-prompt.

Canonical dialog copy (add to ARB; do not hardcode):

- Title: "Discard changes?" / "Annuler les modifications ?"
- Body: "Your entries on this screen won't be saved." / "Vos saisies sur cet écran ne seront pas enregistrées."
- Destructive CTA: "Discard" / "Annuler"
- Cancel CTA: "Keep editing" / "Continuer la saisie"

Wire via `showAdaptiveDialog` so iOS gets the native style for free.

## 8. Migration path → go_router 14+

The project plans to move off raw `Navigator.push` once the auth guard story stabilizes. When that happens:

### 8.1 Router config

`go_router 14+` is the target. Configure in `lib/core/router/app_router.dart`:

```dart
final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(
      path: '/home',
      builder: (_, __) => const HomeShell(),
      routes: [
        // Load Money wizard — nested so deep links land mid-wizard.
        GoRoute(
          path: 'load',
          builder: (_, st) => LoadProviderScreen(currency: st.extra as SupportedCurrency),
          routes: [
            GoRoute(
              path: 'amount',
              builder: (_, st) {
                final args = st.extra as LoadAmountArgs;
                return LoadAmountScreen(
                  currency: args.currency,
                  country: args.country,
                  provider: args.provider,
                );
              },
            ),
          ],
        ),
      ],
    ),
  ],
);
```

### 8.2 Pop semantics differences from Navigator 1.0

- `context.pop()` is fine for in-app back chevrons.
- `context.go('/home')` replaces the entire stack — equivalent to `popUntil((r) => r.isFirst)`. Use this on outcome screens' primary CTAs.
- `GoRouter.of(context).canPop()` returns `false` at the root — `BackChevronButton` should hide itself in that case rather than rendering a dead chevron.

### 8.3 Predictive back with go_router

go_router 14+ exposes `parentNavigatorKey` and `onExit` for branch-level back handling. The `onExit` callback is `Future<bool>`-returning — return `false` to block the back, `true` to allow. This *replaces* `PopScope` for routes managed by go_router; mixing both leads to double-prompts.

```dart
GoRoute(
  path: 'amount',
  onExit: (context, state) async {
    final shouldLeave = await _confirmDiscard(context);
    return shouldLeave == true;
  },
  builder: ...,
)
```

Outcome screens get `onExit: (_, __) async => false` — equivalent to today's `PopScope(canPop: false)`.

### 8.4 Migration checklist

When migrating each feature:

1. Move route definitions out of `MaterialPageRoute(builder: …)` calls into the central router.
2. Replace `Navigator.push(MaterialPageRoute(...))` with `context.push('/path', extra: …)`.
3. Replace `Navigator.pushReplacement(...)` with `context.pushReplacement(...)` or `context.go(...)` depending on intent (see §8.2).
4. Replace `Navigator.popUntil((r) => r.isFirst)` with `context.go('/home')`.
5. Move `PopScope(canPop: false)` on outcome screens to `onExit: (_, __) async => false` on the matching route.
6. Keep `PopScope` for dirty-form guards on input screens — go_router's `onExit` handles route-level concerns, but `PopScope` still handles screen-level back gestures inside a single route.
7. Keep `BackChevronButton` — it now calls `context.pop()` instead of `Navigator.of(context).maybePop()`.

Do not migrate piecemeal within a single feature. Migrate one feature at a time, top to bottom.

## 9. Quick checklist for any new screen

Before merging any new screen, verify:

- [ ] If it's a terminal/outcome screen → wrapped in `PopScope(canPop: false)`.
- [ ] If it has form fields → `PopScope` with dirty-check + discard dialog.
- [ ] If it's reached via `pushReplacement` from a form → preceding screen is no longer reachable via back. Intentional?
- [ ] Header chevron uses `BackChevronButton`, not raw `IconButton`.
- [ ] No `Navigator.pop` calls from inside `onPopInvokedWithResult` when `didPop == false`.
- [ ] All async `Navigator.pop` calls capture `Navigator.of(context)` before the await and check `mounted` / `context.mounted` after.
- [ ] No `WillPopScope` (deprecated).
- [ ] No `onPopInvoked` without `WithResult` (deprecated).
- [ ] Manifest has `android:enableOnBackInvokedCallback="true"` (one-time, project-wide).

## 10. Things this skill does NOT cover

- Top-level bottom-nav tab switching (use `HomeShellController.selectTab`, not `Navigator`).
- Deep-link routing on cold start (go_router's `initialLocation` + `redirect`; covered in flutter-architecture skill).
- In-app modal sheets where the sheet is the whole UI (`showModalBottomSheet`, not a route).
- Web-only browser back-button quirks (the project is mobile-only).
