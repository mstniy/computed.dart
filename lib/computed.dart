import 'package:meta/meta.dart';

import 'src/computed.dart';
export 'future_extension.dart';
export 'stream_extension.dart';

/// Shorthand for creating reactive computations. See [Computed].
Computed<T> $<T>(T Function() f, {bool memoized = true}) =>
    Computed(f, memoized: memoized);

/// Reactive computation with a return type of [T].
///
/// Note that the equality operator [==] should be meaningful for [T],
/// as it is used for memoization.
class Computed<T> {
  /// Creates a reactive computation whose value is computed by the given function.
  ///
  /// If [memoized] is set to false, listeners of this computation as well as
  /// other computations using its value will be re-run every time this computation
  /// is re-run, even if it's value stays the same, except for the extra computations
  /// being done in debug mode to check for non-idempotency.
  Computed(T Function() f, {bool memoized = true})
      : _impl = ComputedImpl(f, memoized, false);

  /// Creates an "async" computation, which is allowed to run asynchronous operations
  /// and will only be re-run if absolutely necessary. This disables some idempotency and
  /// cyclic dependency checks.
  Computed.async(T Function() f, {bool memoized = true})
      : _impl = ComputedImpl(f, memoized, true);

  /// As [Computed], but calls the given function with its last value.
  ///
  /// If the computation has no value yet, [prev] is set to [initialPrev].
  Computed.withPrev(T Function(T prev) f,
      {required T initialPrev, bool memoized = true, bool async = false})
      : _impl = ComputedImpl.withPrev(f, initialPrev, memoized, async);

  /// Subscribes to this computation.
  ///
  /// For non-memoized computations, the listener will be called every time
  /// this computation is re-run, even if it's value stays the same,
  /// except for the extra computations being done in debug mode to check
  /// for non-idempotency.
  /// For memoized computations, the listener will be called only
  /// when the result of the computation changes.
  ComputedSubscription<T> listen(
          void Function(T event)? onData, Function? onError) =>
      _impl.listen(onData, onError);

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
  void mock(T Function() mock) => _impl.mock(mock);

  /// Replaces [f] with the original, undoing [fix], [fixThrow] and [mock].
  @visibleForTesting
  void unmock() => _impl.unmock();

  /// Returns the current value of this computation, if one exists, and subscribes to it.
  ///
  /// Can only be used inside computations.
  /// If this computation threw an exception, throws it.
  /// Throws [NoValueException] if a data source [use]d by this
  /// computation or another computation [use]d by it has no value yet.
  /// Throws [CyclicUseException] if this usage would cause a cyclic dependency.
  T get use => _impl.use;

  /// As [use], but returns [value] instead of throwing [NoValueException].
  T useOr(T value) {
    try {
      return use;
    } on NoValueException {
      return value;
    }
  }

  /// Returns the result of this computation during the last run of the current computation which notified the current computation's downstream, if one exists.
  /// If called on the current computation, returns its last result which was different to the previous one.
  ///
  /// This will never trigger a re-computation.
  /// Can only be used inside computations.
  /// Throws [NoValueException] if the current computation did not [use] this computation
  /// during its previous run.
  /// Note that [prev] does not subscribe to this computation. To do that, see [use].
  T get prev => _impl.prev;

  final ComputedImpl<T> _impl;
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

/// Thrown when a data source [use]d by a computation
/// has not produced a value yet.
class NoValueException implements Exception {}

/// Thrown by [Computed.use] if this usage
/// would cause a cyclic dependency.
class CyclicUseException implements Exception {}

/// Thrown when non-async computations attempt to do async operations
class ComputedAsyncError extends Error {}
