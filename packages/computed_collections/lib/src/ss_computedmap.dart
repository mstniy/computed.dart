import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../icomputedmap.dart';
import 'computedmap_mixins.dart';

class SnapshotStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  Computed<IMap<K, V>> _snapshotStream;
  SnapshotStreamComputedMap(Computed<IMap<K, V>> snapshotStream)
      // Wrap the given computation so that we can mock it
      : _snapshotStream = $(() => snapshotStream.use);

  @override
  Computed<V?> operator [](K key) => $(() => _snapshotStream.use[key]);

  @override
  Computed<ChangeEvent<K, V>> get changes {
    final snapshotPrev = $(() {
      _snapshotStream.use;
      try {
        return (_snapshotStream.prev, true);
      } on NoValueException {
        return (<K, V>{}.lock, false);
      }
    });
    return $(() {
      final (prev, prevExists) = snapshotPrev.use;
      if (!prevExists) {
        return ChangeEventReplace(_snapshotStream.use);
      }
      final cur = _snapshotStream.use;
      final allKeys = prev.keys.toSet().union(cur.keys.toSet());
      final changes = IMap.fromEntries(allKeys
          .where((e) => prev[e] != cur[e])
          .map((e) => MapEntry(
              e,
              cur.containsKey(e)
                  ? ChangeRecordValue(cur[e] as V)
                  : ChangeRecordDelete<V>())));
      return KeyChanges(changes);
    });
  }

  @override
  Computed<bool> containsKey(K key) =>
      $(() => _snapshotStream.use.containsKey(key));

  final _containsValueCache = ComputationCache<V, bool>();

  @override
  Computed<bool> containsValue(V value) => _containsValueCache.wrap(
      value, () => _snapshotStream.use.containsValue(value));

  @override
  Computed<bool> get isEmpty => $(() => _snapshotStream.use.isEmpty);

  @override
  Computed<bool> get isNotEmpty => $(() => _snapshotStream.use.isNotEmpty);

  @override
  Computed<int> get length => $(() => _snapshotStream.use.length);

  @override
  Computed<IMap<K, V>> get snapshot => $(() => _snapshotStream.use);
}
