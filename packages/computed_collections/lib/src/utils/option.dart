import 'package:meta/meta.dart';

@immutable
class Option<T> {
  final bool is_;
  final T? value;

  Option.some(T value_)
      : value = value_,
        is_ = true;
  Option.none()
      : is_ = false,
        value = null;

  bool operator ==(Object other) =>
      other is Option &&
      ((is_ && other.is_ && value == other.value) || (!is_ && !other.is_));

  @override
  String toString() => is_ ? 'Option.some($value)' : 'Option.none()';
}
