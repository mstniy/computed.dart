import 'dart:async';

import 'src/computed.dart';

abstract class ComputedStreamResolver {
  T call<T>(Stream<T> s);
}

abstract class Computed<T> extends Stream<T> {
  /// Whether the value in [lastResult], or the exception it throws, is up-to-date.
  bool get evaluated;

  /// The latest result of this computation.
  /// If the computation threw, throws the same exception.
  T? get lastResult;

  factory Computed(T Function(ComputedStreamResolver ctx) f) => ComputedImpl(f);
}
