import 'dart:async';
import 'package:computed/src/computed_stream.dart';
import 'package:meta/meta.dart';

import 'src/computed.dart';
import 'src/future_extension.dart';
import 'src/stream_extension.dart';

/// Reactive computation with a return type of [T].
///
/// Note that the equality operator [==] should be meaningful for [T],
/// as it is used for memoization.
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
  /// If called on the current computation, returns its last result which was different to the previous one.
  ///
  /// This will never trigger a re-computation.
  /// Can only be used inside computations.
  /// Throws [NoValueException] if the current computation did not [use] this computation
  /// during its previous run.
  /// Note that [prev] does not subscribe to this computation. To do that, see [use].
  T get prev;
}

extension ComputedStreamExtension<T> on Computed<T> {
  Stream<T> get asStream => ComputedStream<T>(this);
}

extension StreamComputedExtension<T> on Stream<T> {
  T get use => StreamComputedExtensionImpl<T>(this).use;

  /// Returns the value of this stream during the last run of the current computation which returned a different value to the previous one.
  ///
  /// Can only be used inside computations.
  /// Throws [NoValueException] if the current computation did not [use] this stream
  /// during its previous run.
  /// Note that [prev] does not subscribe to this stream. To do that, see [use].
  T get prev => StreamComputedExtensionImpl<T>(this).prev;
}

extension FutureComputedExtension<T> on Future<T> {
  T get use => FutureComputedExtensionImpl<T>(this).use;
}

/// Thrown when a data source [use]d by a computation
/// has not produced a value yet.
class NoValueException implements Exception {}

/// Thrown by [Computed.use] if this usage
/// would cause a cyclic dependency.
class CyclicUseException implements Exception {}
