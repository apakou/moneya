import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/locale/locale_controller.dart';
import 'core/responsive/breakpoints.dart';
import 'core/theme/app_colors.dart';
import 'features/home/presentation/screens/home_shell.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'l10n/generated/app_localizations.dart';

Future<void> main() async {
  // Required because we await SharedPreferences (via LocaleController.load)
  // before runApp — without this, the engine binding may not be ready.
  WidgetsFlutterBinding.ensureInitialized();

  // Load locale-specific date/time symbol tables for every shipped
  // locale up-front. Without this, `DateFormat.MMMM('fr').format(...)`
  // throws a `LocaleDataException` the first time French month names
  // are needed (e.g. on the Transactions tab). Calling for English
  // too is cheap and keeps the call site symmetric.
  await Future.wait([
    initializeDateFormatting('en'),
    initializeDateFormatting('fr'),
  ]);

  // Default to portrait-only at startup. The real policy is reapplied
  // dynamically by [_OrientationPolicy] once `MediaQuery` is available
  // — but setting it here too means the very first frame (and the OS
  // task-switcher preview) honors the lock instead of briefly showing
  // a landscape-capable orientation while we boot.
  //
  // Fintech-industry standard: money screens are portrait-only on
  // phones. Cash App, Wise, Revolut, Venmo, N26 all lock portrait.
  // Tablets (≥ expanded breakpoint) get all orientations.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  final localeController = LocaleController();
  // Hydrate the persisted locale before first frame so we never paint
  // the English UI for one frame and then swap to French.
  await localeController.load();

  runApp(MoneyaApp(localeController: localeController));
}

/// Dev-only flag to bypass the splash → onboarding → auth → KYC chain
/// and land directly on [HomeShell].
///
/// Set to `false` so the app boots into the full splash → onboarding →
/// auth → KYC flow (the canonical first-run experience). Flip back to
/// `true` temporarily when iterating on post-onboarding screens (home,
/// transfer, confirm, success/pending/failed, transactions) to avoid
/// re-walking the auth chain on every hot restart.
///
/// Override at run-time without code edits via:
/// `flutter run --dart-define=BYPASS_ONBOARDING=true`
const bool _bypassOnboarding = bool.fromEnvironment(
  'BYPASS_ONBOARDING',
  defaultValue: true,
);

class MoneyaApp extends StatelessWidget {
  const MoneyaApp({required this.localeController, super.key});

  /// App-wide locale state. Lifted into `main()` so every
  /// `MaterialApp.locale`-bound widget relocalizes when the user
  /// toggles — `setState` inside any single screen would not be
  /// enough.
  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    // In release builds we ALWAYS run the real flow regardless of the
    // dart-define — this prevents us shipping a build that skips KYC.
    final useBypass = _bypassOnboarding && !kReleaseMode;

    // Rebuild on locale change. AnimatedBuilder + a Listenable is the
    // lightest pattern that does not pull in a state-management dep;
    // when the broader Riverpod migration happens this becomes a
    // `ConsumerWidget` reading a `localeProvider`.
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) => GetMaterialApp(
        title: 'MoneyA',
        debugShowCheckedModeBanner: false,
        locale: localeController.current.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.brandPurple,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: AppColors.black,
          fontFamily: 'Satoshi',
        ),
        // Surface the controller to the widget tree so any descendant
        // can flip the locale (currently the language pill on Home).
        // Wrapped in [_OrientationPolicy] so the portrait-lock is
        // continuously re-evaluated as the viewport size changes (e.g.
        // foldable unfolding while the app is open).
        // No `package:provider` dep — a tiny `InheritedNotifier` is
        // enough until Riverpod lands.
        builder: (context, child) => _OrientationPolicy(
          child: LocaleScope(
            controller: localeController,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: useBypass ? const HomeShell() : const SplashScreen(),
      ),
    );
  }
}

/// Continuously enforces the app's orientation policy based on the
/// current viewport size class.
///
/// Policy:
///   - **Compact / medium** (phones, phones-in-landscape-split,
///     small tablets in portrait): portrait-up only. Money screens
///     are vertical-stack products; landscape phone layouts
///     consistently feel amateurish on financial apps. This matches
///     Cash App / Wise / Revolut / Venmo / N26.
///   - **Expanded / large** (tablets, foldables fully open, ChromeOS,
///     desktop): all orientations allowed — these form factors are
///     genuinely landscape-friendly and locking them feels broken.
///
/// Why a widget (and not a one-shot call in `main`)?
///
/// The viewport size class can change at runtime: a Galaxy Z Fold
/// goes from 412dp (folded, compact) to 884dp (unfolded, expanded)
/// without the app restarting. A one-shot call in `main` would lock
/// the user to portrait on a fully-unfolded tablet — which is the
/// exact opposite of what we want. By rebuilding when [MediaQuery]
/// changes, we get the right policy at every viewport size.
///
/// The platform channel call is idempotent and only ~µs of overhead,
/// so calling it on every viewport-size change (rare) is fine. We
/// still gate it behind an equality check to avoid log spam during
/// frequent rebuilds (e.g. keyboard open/close).
class _OrientationPolicy extends StatefulWidget {
  const _OrientationPolicy({required this.child});

  final Widget child;

  @override
  State<_OrientationPolicy> createState() => _OrientationPolicyState();
}

class _OrientationPolicyState extends State<_OrientationPolicy> {
  /// Last orientations we asked the platform for. Used to skip the
  /// platform channel call when the policy hasn't actually changed
  /// (e.g. the rebuild was triggered by keyboard insets, not by a
  /// viewport-width change crossing a breakpoint).
  List<DeviceOrientation>? _lastApplied;

  @override
  Widget build(BuildContext context) {
    // Read the size class. This subscribes the widget to MediaQuery
    // size changes — exactly the trigger we want.
    final size = context.screenSize;
    final next = _orientationsFor(size);

    if (!_listEquals(_lastApplied, next)) {
      _lastApplied = next;
      // Fire-and-forget. SystemChrome.setPreferredOrientations
      // returns a Future but we never need to await it — the
      // platform applies the policy on its own timeline, and our
      // UI doesn't depend on the result.
      //
      // Wrapped in microtask to avoid calling into the engine from
      // inside a build phase, which would assert in debug.
      Future.microtask(() => SystemChrome.setPreferredOrientations(next));
    }

    return widget.child;
  }

  /// Maps a size class to the orientations the OS should allow.
  ///
  /// Phones (compact) AND small-tablet/landscape-phone (medium) are
  /// both portrait-locked. The reason medium is portrait-locked too
  /// is subtle: a 414dp phone in landscape *measures* as ~736dp wide
  /// (medium-class), and we don't want our portrait lock to release
  /// the moment a user rotates their phone. The size class transition
  /// only meaningfully signals "real tablet" once we cross into
  /// expanded (≥840dp), which is the iPad-portrait floor.
  static List<DeviceOrientation> _orientationsFor(ScreenSize size) {
    if (size.isSmallerThan(ScreenSize.expanded)) {
      return const [DeviceOrientation.portraitUp];
    }
    return const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
  }

  static bool _listEquals(
    List<DeviceOrientation>? a,
    List<DeviceOrientation>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Inherited handle on the app-wide [LocaleController].
///
/// Exposes the controller (not just the current value) so descendants
/// can both read `LocaleScope.of(context).current` for the active
/// locale AND call `LocaleScope.of(context).toggle()` to switch.
/// Listening (the default) rebuilds the descendant when the locale
/// flips.
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    required LocaleController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<LocaleScope>()
        : context.getElementForInheritedWidgetOfExactType<LocaleScope>()?.widget
              as LocaleScope?;
    assert(scope != null, 'No LocaleScope found in context.');
    return scope!.notifier!;
  }
}
