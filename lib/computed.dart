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
  factory Computed.withPrev(T Function(T prev) f, {required T initialPrev}) =>
      ComputedImpl.withPrev(f, initialPrev);

  ComputedSubscription<T> listen(
      void Function(T event)? onData, Function? onError);

  /// Fixes the result of this computation to the given value.
  ///
  /// See [mock].
  @visibleForTesting
  void fix(T value) {
    mock(() => value);
  }

  /// Fixes this computation to throw the given object.
  ///
  /// See [mock].
  @visibleForTesting
  void fixThrow(Object e) {
    mock(() => throw e);
  }

  /// Replaces the original [f] with [mock].
  ///
  /// This will trigger a re-computation.
  @visibleForTesting
  void mock(T Function() mock);

  /// Replaces [f] with the original, undoing [fix], [fixThrow] and [mock].
  @visibleForTesting
  void unmock();

  /// Returns the current value of this computation, if one exists, and subscribes to it.
  ///
  /// Can only be used inside computations.
  /// If this computation threw an exception, throws it.
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

/// The result of [Computed.listen].
abstract class ComputedSubscription<T> {
  /// Changes the data handler for this subscription.
  void onData(void Function(T data)? handleData);

  /// Changes the error handler for this subscription.
  void onError(Function? handleError);

  /// Cancels this subscription.
  void cancel();
}

extension ComputedStreamExtension<T> on Computed<T> {
  /// Returns the result of the computation as a [Stream].
  Stream<T> get asStream => ComputedStreamExtensionImpl<T>(this).asStream;

  /// Returns the result of the computation as a broadcast [Stream].
  Stream<T> get asBroadcastStream =>
      ComputedStreamExtensionImpl<T>(this).asBroadcastStream;
}

extension StreamComputedExtension<T> on Stream<T> {
  /// Returns the current value of this stream and subscribes to it.
  ///
  /// Unlike [react], [use] does not trigger a re-computation if this stream
  /// consecutively produces values comparing equal to each other.
  /// Can only be used inside computations.
  /// If the last item in this stream is an error, throws it.
  /// Throws [NoValueException] if this stream does not have a known value yet.
  T get use => StreamComputedExtensionImpl<T>(this).use;

  /// If this stream has produced a value or error since the last time the current computation changed its value, runs the given functional on the value or error produced by this stream.
  ///
  /// Also subscribes the current computation to all values and errors produced by this stream.
  /// As a rule of thumb, you should use [react] over [use] if this stream
  /// represents a sequence of events rather than a state.
  /// Unlike [use], [react] does trigger a re-computation if the stream
  /// consecutively produces values comparing equal to each other.
  /// Can only be used inside computations.
  /// If the last item in the stream is an error, throws it.
  void react(void Function(T) onData, void Function(Object)? onError) =>
      StreamComputedExtensionImpl<T>(this).react(onData, onError);

  /// Returns the value of this stream during the last run of the current computation which returned a different value to the previous one.
  ///
  /// Can only be used inside computations.
  /// Throws [NoValueException] if the current computation did not [use] this stream
  /// during its previous run.
  /// Note that [prev] does not subscribe to this stream. To do that, see [use].
  T get prev => StreamComputedExtensionImpl<T>(this).prev;

  /// Makes computations listening on this stream behave as if it emmitted the given value.
  @visibleForTesting
  void mockEmit(T value) {
    StreamComputedExtensionImpl<T>(this).mockEmit(value);
  }

  /// Makes computations listening on this stream behave as if it emmitted the given error.
  @visibleForTesting
  void mockEmitError(Object e) {
    StreamComputedExtensionImpl<T>(this).mockEmitError(e);
  }
}

extension FutureComputedExtension<T> on Future<T> {
  /// Returns the result of this future. Subscribes to it if it has not been resolved yet.
  ///
  /// Can only be used inside computations.
  /// If the future gets resolved with an error, throws it.
  /// Throws [NoValueException] if this future has not been resolved yet.
  T get use => FutureComputedExtensionImpl<T>(this).use;
}

/// Thrown when a data source [use]d by a computation
/// has not produced a value yet.
class NoValueException implements Exception {}

/// Thrown by [Computed.use] if this usage
/// would cause a cyclic dependency.
class CyclicUseException implements Exception {}
