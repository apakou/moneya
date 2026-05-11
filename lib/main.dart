import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/locale/locale_controller.dart';
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

  final localeController = LocaleController();
  // Hydrate the persisted locale before first frame so we never paint
  // the English UI for one frame and then swap to French.
  await localeController.load();

  runApp(MoneyaApp(localeController: localeController));
}

/// Dev-only flag to bypass the splash → onboarding → auth → KYC chain
/// and land directly on [HomeShell].
///
/// Defaults to `true` while we iterate on the post-onboarding screens
/// (home, transfer, confirm, success/pending/failed, transactions) so
/// hot-reloading doesn't kick us back to the country picker every
/// time. Flip back to `false` — or guard with `kReleaseMode` (already
/// done below) — before shipping.
///
/// Override at run-time without code edits via:
/// `flutter run --dart-define=BYPASS_ONBOARDING=false`
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
      builder: (context, _) => MaterialApp(
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
        // No `package:provider` dep — a tiny `InheritedNotifier` is
        // enough until Riverpod lands.
        builder: (context, child) => LocaleScope(
          controller: localeController,
          child: child ?? const SizedBox.shrink(),
        ),
        home: useBypass ? const HomeShell() : const SplashScreen(),
      ),
    );
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
