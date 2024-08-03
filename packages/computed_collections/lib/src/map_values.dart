import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class MapValuesComputedMap<K, V, VParent>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, VParent> _parent;
  final V Function(K key, VParent value) _convert;

  final _keyComputations = ComputationCache<K, V?>();

  late final CSTracker<K, V> _tracker;

  MapValuesComputedMap(this._parent, this._convert) {
    changes = Computed(() {
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
    snapshot = snapshotComputation(
        changes,
        () => _parent.snapshot.use
            .map(((key, value) => MapEntry(key, _convert(key, value)))));

    _tracker = CSTracker(changes, snapshot);
  }

  @override
  Computed<bool> containsKey(K key) => _parent.containsKey(key);

  @override
  Computed<V?> operator [](K key) {
    final parentContainsKey = _parent.containsKey(key);
    final parentKey = _parent[key];
    return _keyComputations.wrap(key, () {
      try {
        final s = snapshot.useWeak;
        // If there is a snapshot, use the value from there
        return s[key];
      } on NoStrongUserException {
        // We compute the value ourselves
        if (parentContainsKey.use) {
          return _convert(key, parentKey.use as VParent);
        }
        return null;
      }
    });
  }

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  late final Computed<ChangeEvent<K, V>> changes;
  @override
  late final Computed<IMap<K, V>> snapshot;
  @override
  Computed<bool> get isEmpty => _parent.isEmpty;
  @override
  Computed<bool> get isNotEmpty => _parent.isNotEmpty;
  @override
  Computed<int> get length => _parent.length;
}
