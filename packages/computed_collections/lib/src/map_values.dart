import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class MapValuesComputedMap<K, V, VParent>
    with OperatorsMixin<K, V>, MockMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final V Function(K key, VParent value) _convert;
  final Computed<bool> isEmpty;
  final Computed<bool> isNotEmpty;
  final Computed<int> length;
  late final Computed<ChangeEvent<K, V>> changes;
  late final Computed<IMap<K, V>> snapshot;

  final keyComputations = ComputationCache<K, V?>();
  final containsKeyComputations = ComputationCache<K, bool>();
  final containsValueComputations = ComputationCache<V, bool>();

  MapValuesComputedMap(this._parent, this._convert)
      // We wrap the parent's attributes into new computations
      // so that they are independently mockable
      : isEmpty = $(() => _parent.isEmpty.use),
        isNotEmpty = $(() => _parent.isNotEmpty.use),
        length = $(() => _parent.length.use) {
    changes = Computed(() {
      // TODO: make this a stream map instead? does it have laziness?
      final change = _parent.changes.use;
      return switch (change) {
        ChangeEventReplace<K, VParent>() => ChangeEventReplace(change
            .newCollection
            .map(((key, value) => MapEntry(key, _convert(key, value))))),
        KeyChanges<K, VParent>() =>
          KeyChanges(IMap.fromEntries(change.changes.entries.map((e) {
            final key = e.key;
            return switch (e.value) {
              ChangeRecordValue<VParent>(value: var value) =>
                MapEntry(key, ChangeRecordValue(_convert(key, value))),
              ChangeRecordDelete<VParent>() =>
                MapEntry(key, ChangeRecordDelete<V>())
            };
          }))),
      };
    });
    // TODO: asStream introduces a lag of one microtask here
    //  Can we change it to make the api more uniform?
    snapshot = ChangeStreamComputedMap(
            changes.asBroadcastStream,
            () => _parent.snapshot.use
                .map(((key, value) => MapEntry(key, _convert(key, value)))))
        .snapshot;
  }

  @override
  Computed<bool> containsKey(K key) {
    final parentContainsKey = _parent.containsKey(key);
    // TODO: This is inefficient. Make the computation map take computations as parameter?
    return containsKeyComputations.wrap(key, () => parentContainsKey.use);
  }

  @override
  Computed<V?> operator [](K key) {
    final parentContainsKey = _parent.containsKey(key);
    final parentKey = _parent[key];
    return keyComputations.wrap(key, () {
      if (parentContainsKey.use) {
        return _convert(key, parentKey.use as VParent);
      }
      return null;
    });
  }

  @override
  Computed<bool> containsValue(V value) => containsValueComputations.wrap(
      value, () => snapshot.use.containsValue(value));
}
