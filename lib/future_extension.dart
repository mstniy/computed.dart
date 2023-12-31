import 'computed.dart';
import 'src/future_extension.dart';

extension FutureComputedExtension<T> on Future<T> {
  /// Returns the result of this future. Subscribes to it if it has not been resolved yet.
  ///
  /// Can only be used inside computations.
  /// If the future gets resolved with an error, throws it.
  /// Throws [NoValueException] if this future has not been resolved yet.
  T get use => FutureComputedExtensionImpl<T>(this).use;

  /// As [use], but returns [value] instead of throwing [NoValueException].
  T useOr(T value) => FutureComputedExtensionImpl<T>(this).useOr(value);
}

extension ComputedFutureUnwrapExtension<T> on Computed<Future<T>> {
  /// Returns a computation representing the value the last [Future] returned by this computation resolves to.
  Computed<T> get unwrap => $(() => use.use);
}
