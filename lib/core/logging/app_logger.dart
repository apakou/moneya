import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as pkg;

/// Application-wide structured logger.
///
/// - Debug builds (`kDebugMode == true`): all levels printed to console via
///   `package:logger`.
/// - Release/profile builds: `trace`/`debug`/`info` are suppressed; `warn` and
///   `error` are forwarded to whatever [CrashReporter](../observability/crash_reporter.dart)
///   is currently bound (no-op until PR7 wires Sentry).
///
/// Every public method accepts a [Map] of structured fields. **Never embed
/// PII or secrets in the message string.** Use the redaction helpers in
/// `lib/core/logging/pii.dart` on any value that might carry phone numbers,
/// tokens, passcodes, OTP codes, or money amounts you don't want surfaced.
///
/// Usage:
/// ```dart
/// AppLogger.i('otp.requested', {
///   'phone': maskPhone(phone),
///   'device_id': session.deviceId,
/// });
/// ```
class AppLogger {
  AppLogger._();

  /// Override hook used by tests. Set this to a non-null logger to capture
  /// output; restore to null in `tearDown` to revert to the production
  /// logger.
  @visibleForTesting
  static pkg.Logger? testOverride;

  static final pkg.Logger _defaultLogger = pkg.Logger(
    printer: pkg.PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      lineLength: 100,
      colors: true,
      printEmojis: false,
      // ignore: deprecated_member_use
      printTime: true,
    ),
    level: kDebugMode ? pkg.Level.trace : pkg.Level.warning,
  );

  static pkg.Logger get _logger => testOverride ?? _defaultLogger;

  /// Reporter sink for `warn`/`error` in release. Bound by PR7 (Sentry).
  /// Default is a no-op so the rest of the app can log freely.
  static CrashReporterSink crashReporter = const _NoopCrashReporterSink();

  static String _format(String event, [Map<String, Object?>? fields]) {
    if (fields == null || fields.isEmpty) return event;
    final buf = StringBuffer(event);
    buf.write(' ');
    var first = true;
    fields.forEach((k, v) {
      if (!first) buf.write(' ');
      buf.write(k);
      buf.write('=');
      buf.write(v);
      first = false;
    });
    return buf.toString();
  }

  static void t(String event, [Map<String, Object?>? fields]) {
    _logger.t(_format(event, fields));
  }

  static void d(String event, [Map<String, Object?>? fields]) {
    _logger.d(_format(event, fields));
  }

  static void i(String event, [Map<String, Object?>? fields]) {
    _logger.i(_format(event, fields));
  }

  static void w(
    String event, [
    Map<String, Object?>? fields,
    Object? error,
    StackTrace? stack,
  ]) {
    _logger.w(_format(event, fields), error: error, stackTrace: stack);
    crashReporter.captureMessage(
      event,
      level: ReportLevel.warning,
      extras: fields,
      error: error,
      stack: stack,
    );
  }

  static void e(
    String event, [
    Map<String, Object?>? fields,
    Object? error,
    StackTrace? stack,
  ]) {
    _logger.e(_format(event, fields), error: error, stackTrace: stack);
    crashReporter.captureMessage(
      event,
      level: ReportLevel.error,
      extras: fields,
      error: error,
      stack: stack,
    );
  }
}

/// Minimal sink interface so `AppLogger` can forward to whatever crash
/// reporter is bound at runtime. PR7 will provide a Sentry-backed
/// implementation; until then the no-op default is used.
abstract class CrashReporterSink {
  void captureMessage(
    String message, {
    required ReportLevel level,
    Map<String, Object?>? extras,
    Object? error,
    StackTrace? stack,
  });
}

enum ReportLevel { warning, error, fatal }

class _NoopCrashReporterSink implements CrashReporterSink {
  const _NoopCrashReporterSink();

  @override
  void captureMessage(
    String message, {
    required ReportLevel level,
    Map<String, Object?>? extras,
    Object? error,
    StackTrace? stack,
  }) {
    // intentionally empty
  }
}
