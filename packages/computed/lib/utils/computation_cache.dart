import '../computed.dart';

class ComputationCache<K, V> {
  final _m = <K, Computed<V>>{};
  final void Function(V value)? _dispose;
  final void Function()? _onCancel;
  final bool _memoized;
  final bool _assertIdempotent;

  ComputationCache(
      {bool memoized = true,
      bool assertIdempotent = true,
      void Function(V value)? dispose,
      void Function()? onCancel})
      : _memoized = memoized,
        _assertIdempotent = assertIdempotent,
        _dispose = dispose,
        _onCancel = onCancel;

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
          !identical(cachedComputation, newComputation))
        return cachedComputation.use;
      // No cached result
      _m[key] = newComputation;
      return computation();
    },
        memoized: _memoized,
        assertIdempotent: _assertIdempotent,
        dispose: _dispose,
        onCancel: onCancel);
    return newComputation;
  }
}
