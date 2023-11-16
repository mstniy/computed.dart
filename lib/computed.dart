import 'dart:async';
import 'package:meta/meta.dart';

import 'src/computed.dart';

class NoValueException implements Exception {}

/// Thrown by [Computed.use] if this usage
/// would cause a cyclic dependency.
class CyclicUseException implements Exception {}

abstract class Computed<T> {
  /// The current result of this computation.
  /// If this computation threw, throws the same exception.
  /// If the value of a data source is missing, throws [NoValueException]
  /// Note that this accessor will run this computation if its result is not cached.
  T get value;

  factory Computed(T Function() f) => ComputedImpl(f);

  /// Fixes the result of this computation to the given value.
  ///
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

  /// Gets the current value of this computation, if one exists, and subscribes to it.
  ///
  /// Can only be used inside computations.
  /// Throws [NoValueException] if a data source [use]d by this
  /// computation or another computation [use]d by it has no value yet.
  /// Throws [CyclicUseException] if this usage would cause a cyclic dependency.
  T get use;
}

extension ComputedStreamExtension<T> on Stream<T> {
  T get use => ComputedStreamExtensionImpl<T>(this).use;
}

extension ComputedFutureExtension<T> on Future<T> {
  T get use => ComputedFutureExtensionImpl<T>(this).use;
}
