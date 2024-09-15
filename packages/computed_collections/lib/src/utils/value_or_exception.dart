// TODO: Refactor this into a sealed class
class ValueOrException<T> {
  final bool isValue;
  Object? exc_;
  T? value_;

  ValueOrException.value(this.value_) : isValue = true;
  ValueOrException.exc(this.exc_) : isValue = false;

  T get value {
    if (isValue) return value_ as T;
    throw exc_!;
  }
}
