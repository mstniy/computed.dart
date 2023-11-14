import 'dart:async';

import 'src/computed.dart';

abstract class Computed<T> {
  /// Whether the value in [lastResult], or the exception it throws, is up-to-date.
  bool get evaluated;

  /// The latest result of this computation.
  /// If the computation threw, throws the same exception.
  T? get lastResult;

  factory Computed(T Function() f) => ComputedImpl(f);

  Stream<T> get asStream;

  T get use;
}

extension ComputedStreamExtension<T> on Stream<T> {
  T get use => ComputedStreamExtensionImpl<T>(this).use;
}
