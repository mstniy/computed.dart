import 'dart:async';

import 'src/computed.dart';

class NoValueException {}

abstract class Computed<T> {
  /// The current result of this computation.
  /// If the computation threw, throws the same exception.
  /// If the value of a data source is missing, throws [NoValueException]
  /// Note that this accessor will run the computation if its result is not cached.
  T get value;

  factory Computed(T Function() f) => ComputedImpl(f);

  Stream<T> get asStream;

  T get use;
}

extension ComputedStreamExtension<T> on Stream<T> {
  T get use => ComputedStreamExtensionImpl<T>(this).use;
}

extension ComputedFutureExtension<T> on Future<T> {
  T get use => ComputedFutureExtensionImpl<T>(this).use;
}
