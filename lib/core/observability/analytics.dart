/// Product analytics interface.
///
/// PR7 will provide a PostHog-backed implementation. Until then, the no-op
/// default is in effect — every call is silently dropped, which keeps call
/// sites cheap and lets us instrument the funnel now without waiting on
/// vendor setup.
///
/// **Do not pass PII into [track] properties.** Phone numbers, full names,
/// passcodes, and amounts must be omitted or masked via
/// `lib/core/logging/pii.dart` first.
abstract class Analytics {
  static Analytics _instance = const NoopAnalytics();

  static Analytics get instance => _instance;

  static void install(Analytics analytics) {
    _instance = analytics;
  }

  static void installNoop() => install(const NoopAnalytics());

  Future<void> identify(String userId, {Map<String, Object?>? traits});
  Future<void> reset();
  Future<void> track(String event, {Map<String, Object?>? properties});
  Future<void> screen(String name, {Map<String, Object?>? properties});
}

class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  Future<void> identify(String userId, {Map<String, Object?>? traits}) async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> track(String event, {Map<String, Object?>? properties}) async {}

  @override
  Future<void> screen(String name, {Map<String, Object?>? properties}) async {}
}
