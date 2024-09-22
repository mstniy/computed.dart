import 'src/computed.dart';
export 'future_extension.dart';
export 'stream_extension.dart';

/// Shorthand for creating reactive computations. See [Computed].
Computed<T> $<T>(T Function() f, {bool memoized = true}) =>
    Computed(f, memoized: memoized);

/// Reactive computation with a return type of [T].
abstract interface class Computed<T> {
  /// Creates a reactive computation whose value is computed by the given function.
  ///
  /// If [memoized] is set to false, listeners of this computation as well as
  /// other computations using its value will be re-run every time this computation
  /// is re-run, even if it's value stays the same, except for the extra computations
  /// being done in debug mode to check for non-idempotency.
  ///
  /// If [assertIdempotent] is set to false, disables the idempotency assertion.
  /// This is useful for computations returning incomparable values, like other computations.
  ///
  /// If [dispose] is set, it will be called with the previous value of the computation
  /// when it changes value, switches from producing values to throwing exceptions,
  /// or loses all of its listeners and non-weak downstream computations,
  /// if it previously had a value.
  ///
  /// If [onCancel] is set, it will be called when the computation loses all of its listeners
  /// and non-weak downstream computations. Called after [dispose].
  factory Computed(
    T Function() f, {
    bool memoized = true,
    bool assertIdempotent = true,
    void Function(T value)? dispose,
    void Function()? onCancel,
  }) =>
      ComputedImpl(f, memoized, assertIdempotent, false, dispose, onCancel);

  /// Creates an "async" computation, which is allowed to run asynchronous operations.
  /// This implicitly disables the idempotency assertion.
  /// See [Computed.new].
  factory Computed.async(T Function() f,
          {bool memoized = true,
          void Function(T value)? dispose,
          void Function()? onCancel}) =>
      ComputedImpl(f, memoized, false, true, dispose, onCancel);

  /// As [Computed.new], but calls the given function with its last value.
  ///
  /// If the computation has no value yet, it is called with [initialPrev].
  /// See [Computed.new] and [Computed.async].
  factory Computed.withPrev(
    T Function(T prev) f, {
    required T initialPrev,
    bool memoized = true,
    bool assertIdempotent = true,
    bool async = false,
    void Function(T value)? dispose,
    void Function()? onCancel,
  }) =>
      ComputedImpl.withPrev(
          f, initialPrev, memoized, assertIdempotent, async, dispose, onCancel);

  /// Defines an "effect", which is a computation meant to have side effects.
  static ComputedSubscription<void> effect(void Function() f) =>
      Computed.async(f).listen(null, null);

  /// Subscribes to this computation.
  ///
  /// For non-memoized computations, the listener will be called every time
  /// this computation is re-run, even if it's value stays the same,
  /// except for the extra computations being done in debug mode to check
  /// for non-idempotency.
  /// For memoized computations, the listener will be called only
  /// when the result of the computation changes.
  /// [onError] has the same semantics as in [Stream.listen].
  ComputedSubscription<T> listen(void Function(T event)? onData,
      [Function? onError]);

  /// Returns the current value of this computation, if one exists, and subscribes to it.
  ///
  /// Can only be used inside computations.
  /// If this computation threw an exception, throws it.
  /// Throws [NoValueException] if a data source [use]d by this
  /// computation or another computation [use]d by it has no value yet.
  /// Throws [CyclicUseException] if this usage would cause a cyclic dependency.
  T get use;

  /// Weakly uses this computation.
  ///
  /// Like [use], but throws [NoStrongUserException] instead of running the computation if
  /// there are no non-weak downstream computations or listeners.
  T get useWeak;

  /// As [use], but returns [value] instead of throwing [NoValueException].
  T useOr(T value);

  /// Returns the result of this computation during the last run of the current computation.
  /// If called on the current computation, returns its last result.
  ///
  /// This will never trigger a re-computation.
  /// Can only be used inside computations.
  /// Throws [NoValueException] if the current computation did not [use] this computation
  /// during its previous run and this computations is not the current computation.
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

/// Thrown if this data source does not have a value yet.
class NoValueException implements Exception {
  @override
  bool operator ==(Object other) => other is NoValueException;

  @override
  int get hashCode => Object.hash(NoValueException, null);
}

/// Thrown when [Computed.useWeak] is called on a computation which
/// has no non-weak downstream computations or listeners.
class NoStrongUserException implements Exception {
  @override
  bool operator ==(Object other) => other is NoStrongUserException;

  @override
  int get hashCode => Object.hash(NoStrongUserException, null);
}

/// Thrown by [Computed.use]/[Computed.useWeak] if this usage
/// would cause a cyclic dependency.
class CyclicUseException implements Exception {
  @override
  bool operator ==(Object other) => other is CyclicUseException;

  @override
  int get hashCode => Object.hash(CyclicUseException, null);
}

/// Thrown when non-async computations attempt to do async operations.
class ComputedAsyncError extends Error {
  @override
  bool operator ==(Object other) => other is ComputedAsyncError;

  @override
  int get hashCode => Object.hash(ComputedAsyncError, null);
}
