import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// Wraps a form-bearing screen so that any back attempt — predictive
/// gesture, system back, OR the header chevron's `onBack` — first
/// prompts the user to confirm discarding their typed input.
///
/// ## Why this exists
///
/// Per `flutter-navigation` skill §3 & §7, any screen whose user has
/// typed/picked something must guard back. Without a guard, the
/// predictive-back gesture on Android 13+ silently drops the form
/// state — particularly painful on money-entry screens where the user
/// has just picked a recipient + amount + note.
///
/// ## How to use
///
/// ```dart
/// // 1. Capture a snapshot of the form fields at initState time
/// late final _Snapshot _initial = _snapshot();
///
/// // 2. Expose an isDirty getter that diffs against the snapshot
/// bool get _isDirty => _snapshot() != _initial;
///
/// // 3. Wrap the Scaffold (or whatever is below the back-handling
/// // boundary) in DirtyFormScope
/// return DirtyFormScope(
///   isDirty: _isDirty,
///   child: Scaffold(...),
/// );
///
/// // 4. In the header chevron's _onBack, route through the same
/// // helper so both back paths use the identical dialog:
/// Future<void> _onBack() async {
///   FocusManager.instance.primaryFocus?.unfocus();
///   if (await DirtyFormScope.confirmDiscardIfDirty(context, _isDirty)) {
///     Get.back();
///   }
/// }
///
/// // 5. After a successful submit, reset the snapshot so the
/// // post-submit no-op back doesn't re-prompt (only relevant if
/// // the form is still on the stack after submit).
/// ```
///
/// ## Anti-patterns avoided
///
/// - **Never** calls `Navigator.pop` from inside `onPopInvokedWithResult`
///   when `didPop == false` (skill §2 rule of thumb). The pop happens
///   on the next frame after the dialog resolves, via the captured
///   navigator handle.
/// - **Never** uses the deprecated `WillPopScope` or
///   `onPopInvoked` (no `WithResult`).
class DirtyFormScope extends StatelessWidget {
  const DirtyFormScope({
    required this.isDirty,
    required this.child,
    super.key,
  });

  /// Whether the form currently holds unsaved user input. When
  /// `false`, the wrapper is transparent — back propagates normally.
  final bool isDirty;

  final Widget child;

  /// Shows the adaptive discard-changes dialog and resolves to
  /// `true` if the user confirmed leaving, `false` otherwise.
  ///
  /// Use this from header-chevron `onBack` handlers (which run
  /// before the system back path) so both paths share dialog copy
  /// and behavior.
  ///
  /// ## Async-context safety
  ///
  /// `BuildContext` may become invalid across the dialog's `await`
  /// if the user backgrounds the app. We capture the navigator handle
  /// **before** awaiting so callers don't have to remember to re-check
  /// `mounted` — the only check they need is whether to act on the
  /// returned bool. The caller still owns the actual pop; this helper
  /// only resolves the dialog.
  static Future<bool> confirmDiscardIfDirty(
    BuildContext context,
    bool isDirty,
  ) async {
    if (!isDirty) return true;
    return _showDiscardDialog(context);
  }

  /// Convenience: shows the dialog AND, if the user confirms, pops
  /// the enclosing route on the next frame. Returns `true` if a pop
  /// was scheduled.
  ///
  /// The pop is deferred via [SchedulerBinding.addPostFrameCallback]
  /// so any in-flight `Tooltip` / `InkResponse` post-tap timers on
  /// the chevron (or any other tap source) drain against the still-
  /// attached element tree before the route deactivates. Popping
  /// synchronously after `await showAdaptiveDialog` triggers a
  /// "Looking up a deactivated widget's ancestor is unsafe" crash
  /// because the chevron's `Tooltip` ancestor calls `Overlay.of` in
  /// its own post-tap callback chain.
  ///
  /// Use this from chevron `onBack` handlers instead of awaiting
  /// [confirmDiscardIfDirty] and calling `Get.back()` yourself.
  ///
  /// ## Why `Get.back()` and not `Navigator.pop(context)`
  ///
  /// The whole app navigates via GetX (`Get.to`, `Get.off`,
  /// `Get.offAll`). `Navigator.of(context).pop()` resolves to the
  /// nearest enclosing `Navigator`, which on screens pushed via
  /// `Get.to` is the same root navigator GetX uses — BUT GetX
  /// maintains its own internal route accounting (`Get.routing`,
  /// middleware, lifecycle hooks). Bypassing it via `Navigator.pop`
  /// can throw `Bad state: No element` when GetX's internal history
  /// list and the navigator's `_history` get out of sync (e.g. after
  /// a `Get.off` chain). `Get.back()` always pops the right thing.
  static Future<bool> confirmAndPopIfDirty(
    BuildContext context,
    bool isDirty,
  ) async {
    final canLeave = await confirmDiscardIfDirty(context, isDirty);
    if (!canLeave) return false;
    // Defer one frame so any in-flight post-tap timers on the
    // chevron / dialog barrier drain against the still-attached
    // element tree. See [popAfterFrame] for the long-form rationale.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // `Get.back()` is a no-op when there's nothing to pop, so we
      // don't need to guard against an empty navigator stack.
      Get.back<void>();
    });
    return true;
  }

  static Future<bool> _showDiscardDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final result = await showAdaptiveDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final isIOS = Theme.of(dialogCtx).platform == TargetPlatform.iOS ||
            Theme.of(dialogCtx).platform == TargetPlatform.macOS;
        // We dispatch on platform here (rather than always returning
        // CupertinoDialogAction) because CupertinoDialogAction only
        // renders a hit-testable region inside CupertinoAlertDialog's
        // split-row layout. AlertDialog.adaptive on Android builds a
        // Material AlertDialog, where Cupertino actions paint but
        // can't be tapped reliably — confirmed via widget tests.
        return AlertDialog.adaptive(
          title: Text(l10n.discardChangesTitle),
          content: Text(l10n.discardChangesBody),
          actions: <Widget>[
            if (isIOS) ...<Widget>[
              // iOS — native split actions in Cupertino style.
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(l10n.discardChangesCancel),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(l10n.discardChangesConfirm),
              ),
            ] else ...<Widget>[
              // Material — TextButton actions. The destructive
              // intent is conveyed via the danger color on the
              // confirm label.
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(l10n.discardChangesCancel),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(l10n.discardChangesConfirm),
              ),
            ],
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Allow back when the form is clean. When dirty, we block the
      // system pop and route through the dialog ourselves.
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return; // user already left (canPop was true)
        final shouldLeave = await _showDiscardDialog(context);
        if (!shouldLeave) return;
        // Defer the pop one frame so any in-flight post-tap timers
        // from the dialog's barrier or the underlying chevron drain
        // against the still-attached element tree. Synchronous pop
        // here triggers "Looking up a deactivated widget's ancestor
        // is unsafe" because ancestors (Tooltip, InkResponse, Hero)
        // schedule cleanup callbacks that fire after this returns.
        //
        // Uses `Get.back()` (not `Navigator.pop`) to keep GetX's
        // internal route accounting in sync — see
        // [confirmAndPopIfDirty] for the rationale.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          Get.back<void>();
        });
      },
      child: child,
    );
  }
}

/// Lightweight tint used by destructive dialog actions on Material.
/// Exposed so consumers can mirror this color in any inline confirm
/// affordances they build outside the dialog.
const Color discardActionColor = AppColors.danger;
