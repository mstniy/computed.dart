sealed class ValueOrException<T> {
  ValueOrException._();

  factory ValueOrException.value(T value) => Value._(value);
  factory ValueOrException.exc(Object exc) => Exception._(exc);

  T get value => switch (this) {
        Value<T>(_value: final v) => v,
        Exception<T>(exc: final e) => throw e,
      };
}

class Value<T> extends ValueOrException<T> {
  final T _value;

  Value._(this._value) : super._();
}

class Exception<T> extends ValueOrException<T> {
  final Object exc;

  Exception._(this.exc) : super._();
}
