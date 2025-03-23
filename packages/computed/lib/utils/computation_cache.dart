import '../computed.dart';

/// A cache for uniting computations by a key.
class ComputationCache<K, V> {
  final _m = <K, Computed<V>>{};
  final void Function(V value)? _dispose;
  final void Function()? _onCancel;
  final bool _assertIdempotent;

  /// Constructs an empty cache.
  /// The configs are as with [Computed.new].
  ComputationCache(
      {bool assertIdempotent = true,
      void Function(V value)? dispose,
      void Function()? onCancel})
      : _assertIdempotent = assertIdempotent,
        _dispose = dispose,
        _onCancel = onCancel;

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

    newComputation = Computed(() {
      final cachedComputation = _m[key];
      if (cachedComputation != null &&
          !identical(cachedComputation, newComputation)) {
        return cachedComputation.use;
      }
      // No cached result
      _m[key] = newComputation;
      return computation();
    },
        assertIdempotent: _assertIdempotent,
        dispose: _dispose,
        onCancel: onCancel);
    return newComputation;
  }
}
