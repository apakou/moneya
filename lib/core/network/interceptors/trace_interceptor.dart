import 'dart:io' show Platform;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Adds the per-request envelope headers:
///
/// - `traceparent` (W3C trace context) — fresh per request. Lets the backend
///   correlate a single client call across all downstream provider calls
///   (Yellow Card, Smile ID, Solana RPC, Privy).
/// - `X-Device-Id` — stable per install. Injected from the value supplied at
///   interceptor construction (the [SessionController] device id).
/// - `X-App-Version` — supplied at construction via [appVersion].
/// - `X-Platform` — `ios` / `android` / host platform name on web/desktop.
/// - `Accept-Language` — supplied at construction (current locale). Tests
///   can override per request via `extra['acceptLanguage']`.
class TraceInterceptor extends Interceptor {
  TraceInterceptor({
    required this.deviceIdProvider,
    required this.appVersion,
    required this.localeProvider,
    Random? random,
  }) : _random = random ?? Random.secure();

  final String Function() deviceIdProvider;
  final String appVersion;
  final String Function() localeProvider;
  final Random _random;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['traceparent'] = _traceparent();
    options.headers['X-Device-Id'] = deviceIdProvider();
    options.headers['X-App-Version'] = appVersion;
    options.headers['X-Platform'] = _platform();
    final override = options.extra['acceptLanguage'];
    options.headers['Accept-Language'] =
        override is String && override.isNotEmpty ? override : localeProvider();
    handler.next(options);
  }

  String _traceparent() {
    // Format: 00-<32 hex>-<16 hex>-01
    final traceId = _hex(16);
    final spanId = _hex(8);
    return '00-$traceId-$spanId-01';
  }

  String _hex(int bytes) {
    final buf = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buf.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  String _platform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }
}
