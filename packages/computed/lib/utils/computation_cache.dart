import '../computed.dart';

class ComputationCache<K, V> {
  final _m = <K, Computed<V>>{};

  Computed<V> wrap(K key, V Function() computation) {
    final cachedComputation = _m[key];
    if (cachedComputation != null) return cachedComputation;
    late final Computed<V> newComputation;

    void onDispose<T>(T _) {
      final cachedComputation = _m[key];
      if (identical(cachedComputation, newComputation)) {
        _m.remove(key);
      }
    }

    newComputation = Computed(() {
      final cachedComputation = _m[key];
      if (cachedComputation != null &&
          !identical(cachedComputation, newComputation))
        return cachedComputation.use;
      // No cached result
      _m[key] = newComputation;
      return computation();
    }, onDispose: onDispose, onDisposeError: onDispose);
    return newComputation;
  }
}
