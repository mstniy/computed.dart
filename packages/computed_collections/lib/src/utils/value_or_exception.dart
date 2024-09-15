sealed class ValueOrException<T> {
  ValueOrException._();

  factory ValueOrException.value(T value) => Value(value);
  factory ValueOrException.exc(Object exc) => Exception(exc);

  T get value => switch (this) {
        Value<T>(_value: final v) => v,
        Exception<T>(exc: final e) => throw e,
      };
}

class Value<T> extends ValueOrException<T> {
  final T _value;

  Value(this._value) : super._();
}

class Exception<T> extends ValueOrException<T> {
  final Object exc;

  Exception(this.exc) : super._();
}
