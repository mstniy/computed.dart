import 'computed.dart';
import 'src/computed_stream.dart';
import 'src/stream_extension.dart';

extension ComputedStreamExtension<T> on Computed<T> {
  /// Returns the result of the computation as a [Stream].
  Stream<T> get asStream => ComputedStreamExtensionImpl<T>(this).asStream;

  /// Returns the result of the computation as a broadcast [Stream].
  Stream<T> get asBroadcastStream =>
      ComputedStreamExtensionImpl<T>(this).asBroadcastStream;
}

extension ComputedStreamUnwrapExtension<T> on Computed<Stream<T>> {
  /// Returns a computation representing the last value produced by the last [Stream] returned by this computation.
  Computed<T> get unwrap => $(() => use.use);
}

extension StreamComputedExtension<T> on Stream<T> {
  /// Returns the current value of this stream and subscribes to it.
  ///
  /// Unlike [react], [use] does not trigger a re-computation if this stream
  /// consecutively produces values comparing equal to each other.
  /// Can only be used inside computations.
  /// Cannot be used inside [react] callbacks.
  /// If the last item in this stream is an error, throws it.
  /// Throws [NoValueException] if this stream does not have a known value yet.
  T get use => StreamComputedExtensionImpl<T>(this).use;

  /// As [use], but returns [value] instead of throwing [NoValueException].
  T useOr(T value) => StreamComputedExtensionImpl<T>(this).useOr(value);

  /// If this stream has produced a value or error since the last time the current computation notified its downstream, runs the given functional on the value or error produced by this stream.
  ///
  /// If no onError is provided and the stream has produced an error, the current computation
  /// will be assumed to have thrown that error at the end if it returns a value.
  /// Also subscribes the current computation to all values and errors produced by this stream.
  /// As a rule of thumb, you should use [react] over [use] if this stream
  /// represents a sequence of events rather than a state.
  /// Unlike [use], [react] does trigger a re-computation if the stream
  /// consecutively produces values comparing equal to each other.
  /// Can only be used inside computations.
  /// Cannot be used inside [react] callbacks.
  /// If the last item in the stream is an error, throws it.
  /// [onError] has the same semantics as in [Stream.listen]
  void react(void Function(T) onData, [Function? onError]) =>
      StreamComputedExtensionImpl<T>(this).react(onData, onError);

  /// Returns the value of this stream during the last run of the current computation.
  ///
  /// Can only be used inside computations.
  /// Throws [NoValueException] if the current computation did not [use] this stream
  /// during its previous run.
  /// Note that [prev] does not subscribe to this stream. To do that, see [use].
  T get prev => StreamComputedExtensionImpl<T>(this).prev;

  /// As [prev], but returns [or] instead of throwing [NoValueException].
  T prevOr(T or) => StreamComputedExtensionImpl<T>(this).prevOr(or);
}
