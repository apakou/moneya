import 'api_error.dart';

/// Discriminated union returned by every repository call. Eliminates the need
/// to wrap call sites in `try/catch` for `ApiError`s — those are reified.
///
/// **Unexpected** exceptions (programmer error, framework bugs) still throw
/// through `Future<ApiResult<T>>` — `ApiResult` is for *expected* failures
/// only.
///
/// Usage:
/// ```dart
/// final result = await repo.createTransfer(req);
/// switch (result) {
///   case Success(:final value):
///     // ...
///   case Failure(:final error):
///     // pattern-match on error subtype
/// }
/// ```
sealed class ApiResult<T> {
  const ApiResult();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get valueOrNull => switch (this) {
        Success(:final value) => value,
        Failure() => null,
      };

  ApiError? get errorOrNull => switch (this) {
        Success() => null,
        Failure(:final error) => error,
      };
}

class Success<T> extends ApiResult<T> {
  const Success(this.value);
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Success<T> && other.value == value);

  @override
  int get hashCode => value.hashCode;
}

class Failure<T> extends ApiResult<T> {
  const Failure(this.error);
  final ApiError error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Failure<T> && other.error == error);

  @override
  int get hashCode => error.hashCode;
}
