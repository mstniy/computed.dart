import 'dart:async';
import 'package:meta/meta.dart';

import 'src/computed.dart';

class NoValueException {}

abstract class Computed<T> {
  /// The current result of this computation.
  /// If this computation threw, throws the same exception.
  /// If the value of a data source is missing, throws [NoValueException]
  /// Note that this accessor will run this computation if its result is not cached.
  T get value;

  factory Computed(T Function() f) => ComputedImpl(f);

  /// Fixes the result of this computation to the given value.
  ///
  /// Maintains connections to upstream computations/data sources.
  /// If this computation has not produced its first result yet,
  /// or its last result is not equal to [value], its listeners will be notified.
  /// Note that there is no way to "un-fix" a computation, but [fix] can be
  /// called at a later time with another value.
  @visibleForTesting
  void fix(T value);

  /// Fixes the result of this computation to the given exception.
  ///
  /// The listeners of this computation will receive the given exception.
  /// See [fix]
  @visibleForTesting
  void fixException(Object e);

  Stream<T> get asStream;

  T get use;
}

extension ComputedStreamExtension<T> on Stream<T> {
  T get use => ComputedStreamExtensionImpl<T>(this).use;
}

extension ComputedFutureExtension<T> on Future<T> {
  T get use => ComputedFutureExtensionImpl<T>(this).use;
}
