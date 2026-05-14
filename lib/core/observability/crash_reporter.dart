import '../logging/app_logger.dart';

/// Crash + non-fatal error reporter.
///
/// PR7 will provide a Sentry-backed implementation. Until then, the no-op
/// default ([NoopCrashReporter]) is installed by [CrashReporter.installNoop],
/// which is called from `main.dart` before any other framework hook runs.
///
/// The reporter is also bound to [AppLogger.crashReporter] via
/// [CrashReporter.bindLogger] so that `AppLogger.w` / `AppLogger.e` route to
/// the same sink without callers needing to know about both.
abstract class CrashReporter {
  static CrashReporter _instance = const NoopCrashReporter();

  static CrashReporter get instance => _instance;

  /// Replace the current reporter. Call from `main.dart` after picking up
  /// the DSN from env. Safe to call multiple times (last call wins).
  static void install(CrashReporter reporter) {
    _instance = reporter;
    AppLogger.crashReporter = _LoggerSink(reporter);
  }

  /// Install the no-op reporter. Safe to call from tests and from cold-boot
  /// before env is read.
  static void installNoop() => install(const NoopCrashReporter());

  /// Capture a thrown exception (typically from `FlutterError.onError` or
  /// `PlatformDispatcher.instance.onError`).
  Future<void> captureException(
    Object error,
    StackTrace stack, {
    Map<String, Object?>? extras,
    bool fatal = false,
  });

  /// Capture a non-fatal log message at the given [level]. Used by
  /// [AppLogger.w] / [AppLogger.e].
  Future<void> captureMessage(
    String message, {
    required ReportLevel level,
    Map<String, Object?>? extras,
    Object? error,
    StackTrace? stack,
  });

  /// Attach context for subsequent events. Pass `null` to clear.
  void setUser({String? id, String? phone, String? countryIso2});

  /// Drop a breadcrumb. The reporter is free to throttle / cap.
  void breadcrumb(String message, {String? category, Map<String, Object?>? data});
}

class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> captureException(
    Object error,
    StackTrace stack, {
    Map<String, Object?>? extras,
    bool fatal = false,
  }) async {}

  @override
  Future<void> captureMessage(
    String message, {
    required ReportLevel level,
    Map<String, Object?>? extras,
    Object? error,
    StackTrace? stack,
  }) async {}

  @override
  void setUser({String? id, String? phone, String? countryIso2}) {}

  @override
  void breadcrumb(String message, {String? category, Map<String, Object?>? data}) {}
}

/// Adapter that bridges [CrashReporter] to [AppLogger]'s sink interface.
class _LoggerSink implements CrashReporterSink {
  _LoggerSink(this._reporter);
  final CrashReporter _reporter;

  @override
  void captureMessage(
    String message, {
    required ReportLevel level,
    Map<String, Object?>? extras,
    Object? error,
    StackTrace? stack,
  }) {
    // Fire-and-forget; loggers should never await.
    _reporter.captureMessage(
      message,
      level: level,
      extras: extras,
      error: error,
      stack: stack,
    );
  }
}
