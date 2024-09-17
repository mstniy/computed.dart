sealed class ValueOrException<T> {
  ValueOrException._();

  factory ValueOrException.value(T value) => Value._(value);
  factory ValueOrException.exc(Object exc, StackTrace st) =>
      Exception._(exc, st);

  T get valueOrThrow => switch (this) {
        Value<T>(value: final v) => v,
        Exception<T>(exc: final e) => throw e,
      };
}

class Value<T> extends ValueOrException<T> {
  final T value;

  Value._(this.value) : super._();
}

class Exception<T> extends ValueOrException<T> {
  final Object exc;
  final StackTrace st;

  Exception._(this.exc, this.st) : super._();
}
