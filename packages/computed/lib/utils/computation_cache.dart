import '../computed.dart';

/// A cache for uniting computations by a key.
class ComputationCache<K, V> {
  final _m = <K, Computed<V>>{};
  final void Function()? _onCancel;
  final Computed<V> Function(
    V Function() f,
    void Function()? onCancel,
  ) cons;

  /// Constructs an empty cache.
  /// The configs are as with [Computed.new].
  ComputationCache(
      {bool assertIdempotent = true,
      void Function(V value)? dispose,
      void Function()? onCancel})
      : _onCancel = onCancel,
        cons = ((f, onCancel) => Computed(f,
            assertIdempotent: assertIdempotent,
            dispose: dispose,
            onCancel: onCancel));

  /// Same as [ComputationCache.new], but uses
  /// [Computed.async] to construct computations.
  ComputationCache.async(
      {void Function(V value)? dispose, void Function()? onCancel})
      : _onCancel = onCancel,
        cons = ((f, onCancel) =>
            Computed.async(f, dispose: dispose, onCancel: onCancel));

  /// Returns a computation that creates and uses a leader for the given [key].
  ///
  /// The leader, in turn, runs the given [computation].
  /// For each [key] there is at most a single leader. This means
  /// the given [computation] will be run at most once per upstream
  /// changes no matter how many [wrap] calls with the same [key] was made.
  Computed<V> wrap(K key, V Function() computation) {
    final cachedComputation = _m[key];
    if (cachedComputation != null) return cachedComputation;
    late final Computed<V> newComputation;

    void onCancel() {
      final cachedComputation = _m[key];
      if (identical(cachedComputation, newComputation)) {
        final removed = _m.remove(key);
        assert(removed != null);
      }
      if (_onCancel != null) _onCancel();
    }

    newComputation = cons(() {
      final cachedComputation = _m[key];
      if (cachedComputation != null &&
          !identical(cachedComputation, newComputation)) {
        return cachedComputation.use;
      }
      // No cached result
      _m[key] = newComputation;
      return computation();
    }, onCancel);
    return newComputation;
  }
}
