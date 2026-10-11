import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/config/env.dart';
import 'core/locale/locale_controller.dart';
import 'core/network/api_client.dart';
import 'core/network/dio_session_refresher.dart';
import 'core/observability/analytics.dart';
import 'core/observability/crash_reporter.dart';
import 'core/preferences/app_prefs.dart';
import 'core/responsive/breakpoints.dart';
import 'core/session/session_controller.dart';
import 'core/session/session_store.dart';
import 'core/session/step_up_controller.dart';
import 'core/storage/secure_storage.dart';
import 'core/theme/app_colors.dart';
import 'features/auth/data/auth_flow.dart';
import 'features/home/presentation/screens/home_shell.dart';
import 'features/wallet/data/wallet_controller.dart';
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

  // --- Foundations bootstrap (W1) -------------------------------------
  // Install no-op observability up-front so any subsequent code that
  // logs through AppLogger.w/e has a sink to talk to. PR7 will swap in
  // real Sentry + PostHog implementations once DSN / key envs are wired.
  CrashReporter.installNoop();
  Analytics.installNoop();

  // SessionController is the single source of truth for auth state. Its
  // SessionRefresher is wired against a BARE Dio (no interceptors) to
  // break the AuthInterceptor → refresh → AuthInterceptor cycle.
  final secureStorage = SecureStorageImpl();
  final sessionStore = SessionStore(secureStorage);
  final session = SessionController(
    store: sessionStore,
    refresher: DioSessionRefresher(baseUrl: Env.apiBaseUrl),
  );
  await session.bootstrap();
  Get.put<SessionController>(session, permanent: true);

  // Hydrate persistent UI flags (onboarding completion + biometric
  // opt-in) so the first frame can route correctly without an async
  // gap that would flash the wrong screen.
  final prefs = AppPrefs(secureStorage);
  await prefs.load();
  Get.put<AppPrefs>(prefs, permanent: true);

  // ApiClient depends on SessionController.deviceId being populated, so
  // it must be constructed AFTER bootstrap completes.
  final packageInfo = await PackageInfo.fromPlatform();
  final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
  final api = ApiClient.build(
    session: session,
    appVersion: appVersion,
    localeProvider: () => localeController.current.locale.toLanguageTag(),
  );
  Get.put<ApiClient>(api, permanent: true);
  Get.put<StepUpController>(StepUpController(api), permanent: true);
  Get.put<AuthFlow>(AuthFlow(), permanent: true);
  Get.put<WalletController>(WalletController(), permanent: true);
  // --------------------------------------------------------------------

  runApp(MoneyaApp(localeController: localeController));
}

/// Dev-only flag to bypass the splash → onboarding → auth → KYC chain
/// and land directly on [HomeShell].
///
/// Sourced from [Env.bypassOnboarding], which itself is triple-guarded:
///   - debug build (`kDebugMode`);
///   - flavor != prod;
///   - `--dart-define=BYPASS_ONBOARDING=true` is supplied.
///
/// Production cannot be tricked into skipping KYC: even if a dart-define
/// leaks in, the `kDebugMode` and flavor checks reject it.
///
/// Override at run-time for local iteration:
/// `./scripts/run_dev.sh` already sets it to true; pass
/// `BYPASS_ONBOARDING=false ./scripts/run_dev.sh` to opt out.
bool get _bypassOnboarding => Env.bypassOnboarding;

class MoneyaApp extends StatelessWidget {
  const MoneyaApp({required this.localeController, super.key});

  /// App-wide locale state. Lifted into `main()` so every
  /// `MaterialApp.locale`-bound widget relocalizes when the user
  /// toggles — `setState` inside any single screen would not be
  /// enough.
  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    // `Env.bypassOnboarding` is already triple-guarded (debug + non-prod
    // + dart-define). No additional release-mode check needed.
    final useBypass = _bypassOnboarding;

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
