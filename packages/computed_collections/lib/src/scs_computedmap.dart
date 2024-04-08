import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

/// An [IComputedMap] represented by a change and a snapshot stream.
class SnapshotChangeStreamComputedMap<K, V>
    with OperatorsMixin<K, V>, MockMixin<K, V>
    implements IComputedMap<K, V> {
  final Computed<bool> isEmpty;
  final Computed<bool> isNotEmpty;
  final Computed<int> length;
  final Computed<ChangeEvent<K, V>> changes;
  final Computed<IMap<K, V>> snapshot;

  final keyComputations = ComputationCache<K, V?>();
  final containsKeyComputations = ComputationCache<K, bool>();
  final containsValueComputations = ComputationCache<V, bool>();

  SnapshotChangeStreamComputedMap(
      Stream<ChangeEvent<K, V>> _changes, Stream<IMap<K, V>> _snapshot)
      : isEmpty = $(() => _snapshot.use.isEmpty),
        isNotEmpty = $(() => _snapshot.use.isNotEmpty),
        length = $(() => _snapshot.use.length),
        changes = $(() {
          ChangeEvent<K, V>? change;
          _changes.react((c) {
            change = c;
          });
          if (change == null) throw NoValueException();
          return change!;
        }),
        snapshot = $(() => _snapshot.use);

  @override
  Computed<bool> containsKey(K key) =>
      containsKeyComputations.wrap(key, () => snapshot.use.containsKey(key));

  @override
  Computed<V?> operator [](K key) =>
      keyComputations.wrap(key, () => snapshot.use[key]);

  @override
  Computed<bool> containsValue(V value) => containsValueComputations.wrap(
      value, () => snapshot.use.containsValue(value));
}
