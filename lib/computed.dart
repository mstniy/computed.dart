import 'dart:async';
import 'package:meta/meta.dart';

import 'src/computed.dart';

/// Reactive computation with a return type of [T]
abstract class Computed<T> {
  factory Computed(T Function() f) => ComputedImpl(f);
  factory Computed.withSelf(T Function(Computed<T> self) f) {
    Computed<T>? c;
    c = ComputedImpl(() => f(c!));
    return c;
  }

  /// Fixes the result of this computation to the given value.
  ///
  /// See [mock].
  @visibleForTesting
  void fix(T value) {
    mock(() => value);
  }

  /// Fixes the result of this computation to the given exception.
  ///
  /// See [mock].
  @visibleForTesting
  void fixException(Object e) {
    mock(() => throw e);
  }

  /// Replaces the original [f] with [mock].
  ///
  /// This will trigger a re-computation.
  @visibleForTesting
  void mock(T Function() mock);

  /// Replaces [f] with the original, undoing [fix], [fixException] and [mock].
  @visibleForTesting
  void unmock();

  Stream<T> get asStream;

  /// Gets the current value of this computation, if one exists, and subscribes to it.
  ///
  /// Can only be used inside computations.
  /// If this computation threw an exception other than [NoValueException],
  /// throws it.
  /// Throws [NoValueException] if a data source [use]d by this
  /// computation or another computation [use]d by it has no value yet.
  /// Throws [CyclicUseException] if this usage would cause a cyclic dependency.
  T get use;

  /// Returns the result of this computation during the previous run of the current computation, if one exists.
  /// If called on the current computaition, returns its last result which was different to those before it.
  ///
  /// This will never trigger a re-computation.
  /// Can only be used inside computations.
  /// Throws [NoValueException] if the current computation did not [use] this computation
  /// during its previous run.
  T get prev;
}

extension ComputedStreamExtension<T> on Stream<T> {
  T get use => ComputedStreamExtensionImpl<T>(this).use;

  /// Returns the value of this stream during the last run of the current computation which returned a different value.
  ///
  /// Can only be used inside computations.
  /// Throws [NoValueException] if the current computation did not [use] this stream
  /// during its previous run.
  T get prev => ComputedStreamExtensionImpl<T>(this).prev;
}

extension ComputedFutureExtension<T> on Future<T> {
  T get use => ComputedFutureExtensionImpl<T>(this).use;
}

/// Thrown when a data source [use]d by a computation
/// has not produced a value yet.
class NoValueException implements Exception {}

/// Thrown by [Computed.use] if this usage
/// would cause a cyclic dependency.
class CyclicUseException implements Exception {}
