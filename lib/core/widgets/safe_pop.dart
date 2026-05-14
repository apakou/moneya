import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

/// Pops the current route on the **next frame** instead of synchronously
/// inside the current build/tap callback, using GetX as the navigator.
///
/// ## Why this exists (don't remove without reading)
///
/// Material splashes (`InkWell`, `InkResponse`, `ListTile.onTap`,
/// `TextButton`, `FilledButton`, `OutlinedButton`, `ElevatedButton`,
/// `IconButton`) schedule a ripple animation on every press. When the
/// `onTap`/`onPressed` callback synchronously pops the route — whether
/// via `Navigator.pop` or `Get.back` — the route's element tree is
/// **deactivated before the ripple finishes**. The ripple's animation
/// tick then performs `Material.of(context)` on a deactivated element,
/// which throws:
///
/// > Looking up a deactivated widget's ancestor is unsafe.
///
/// Switching to GetX doesn't change this: `Get.back()` ultimately calls
/// the same global `Navigator.pop`, so the splash/route teardown race
/// is identical. The fix is the same as before — defer the pop to the
/// next frame so the splash finishes its inherited-widget lookups
/// against a still-active element tree.
///
/// ## What this helper does
///
/// Defers `Get.back(result: ...)` to `SchedulerBinding.addPostFrameCallback`.
/// Visually indistinguishable from a synchronous pop (~16ms), but no
/// crash.
///
/// ## When to use
///
/// Anywhere a Material-splash-backed widget's `onTap`/`onPressed`
/// would otherwise call `Get.back(result: ...)`. For header
/// chevrons, prefer [BackChevronButton] — it solves the same problem
/// at the widget level by deferring the tap callback internally.
///
/// ## Usage
///
/// ```dart
/// // BEFORE — crashes after long taps:
/// onTap: () => Get.back(result: selected),
///
/// // AFTER — safe:
/// onTap: () => popAfterFrame(context, selected),
/// ```
///
/// The optional [result] is forwarded to `Get.back(result: ...)` so
/// bottom-sheet picker contracts that return a value
/// (`showModalBottomSheet<Foo>` resolving to `Foo`) keep working
/// unchanged.
///
/// ## Why the `BuildContext` parameter is still required
///
/// We keep the signature `popAfterFrame(BuildContext, [T?])` even
/// though `Get.back()` doesn't need a `BuildContext`. Two reasons:
/// (1) callers already pass `context` — keeping the signature avoids
/// touching every site; (2) we use the context as a liveness sentinel:
/// `context.mounted` lets us skip the pop if the widget was already
/// torn down by another path (rare but possible — predictive back,
/// parent rebuild, etc.).
void popAfterFrame<T extends Object?>(BuildContext context, [T? result]) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    // If the widget that scheduled this pop is already gone (predictive
    // back, parent rebuild, hardware back), the pop has already
    // happened or no longer applies — skip silently.
    if (!context.mounted) return;
    // Get.back is a no-op when there's nothing to pop, so we don't
    // need to guard with `canPop` ourselves.
    Get.back<T>(result: result);
  });
}
