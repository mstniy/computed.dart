import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../computedmap.dart';
import 'computedmap_mixins.dart';
import 'expandos.dart';
import 'utils/option.dart';

class PiecewiseComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  // This is not powerful enough to represent uncountably infinite domains :(
  final Iterable<K> _domain;
  final V Function(K) _f;
  final _keyCache = ComputationCache<K, Option<V>>(assertIdempotent: false);
  final _containsValueCache = ComputationCache<V, bool>();

  PiecewiseComputedMap(this._domain, this._f) {
    snapshot = Computed(() => IMap.fromKeys(keys: _domain, valueMapper: _f),
        assertIdempotent: false);
  }

  Option<V> Function() _getKeyComputation(K key) =>
      () => _domain.contains(key) ? Option.some(_f(key)) : Option.none();

  @override
  Computed<V?> operator [](K key) {
    final cache = _keyCache.wrap(key, _getKeyComputation(key));
    return $(() => cache.use.value);
  }

  @override
  Computed<ChangeEvent<K, V>> get changes => $(() => throw NoValueException());

  @override
  Computed<bool> containsKey(K key) {
    final cache = _keyCache.wrap(key, _getKeyComputation(key));
    return $(() => cache.use.is_);
  }

  @override
  Computed<bool> containsValue(V value) => _containsValueCache.wrap(value, () {
        try {
          return snapshot.useWeak.containsValue(value);
        } on NoStrongUserException {
          return _domain.map(_f).contains(value);
        }
      });

  @override
  Computed<bool> get isEmpty =>
      // We still cache this with an expando as the attributes of the iterable might be non-trivial
      isEmptyExpando[this] ??= $(() => _domain.isEmpty);

  @override
  Computed<bool> get isNotEmpty =>
      isNotEmptyExpando[this] ??= $(() => _domain.isNotEmpty);

  @override
  Computed<int> get length => lengthExpando[this] ??= $(() => _domain.length);

  @override
  late final Computed<IMap<K, V>> snapshot;
}
