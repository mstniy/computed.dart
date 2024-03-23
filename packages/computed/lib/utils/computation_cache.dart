import '../computed.dart';

class ComputationCache<K, V> {
  final _m = <K, Computed<V>>{};

  Computed<V> wrap(K key, V Function() computation,
      {bool memoized = true,
      bool assertIdempotent = true,
      void Function(V value)? onDispose,
      void Function(Object error)? onDisposeError}) {
    final cachedComputation = _m[key];
    if (cachedComputation != null) return cachedComputation;
    late final Computed<V> newComputation;

    void _onDisposeFinally() {
      final cachedComputation = _m[key];
      if (identical(cachedComputation, newComputation)) {
        _m.remove(key);
      }
    }

    void _onDispose(V v) {
      _onDisposeFinally();
      if (onDispose != null) onDispose(v);
    }

    void _onDisposeError(Object o) {
      _onDisposeFinally();
      if (onDisposeError != null) onDisposeError(o);
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
        memoized: memoized,
        assertIdempotent: assertIdempotent,
        onDispose: _onDispose,
        onDisposeError: _onDisposeError);
    return newComputation;
  }
}
