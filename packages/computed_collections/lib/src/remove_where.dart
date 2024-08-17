import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/expandos.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'utils/option.dart';

class RemoveWhereComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, V> _parent;
  final bool Function(K key, V value) _filter;

  final _keyOptionComputations = ComputationCache<K, Option<V>>();

  late final CSTracker<K, V> _tracker;

  RemoveWhereComputedMap(this._parent, this._filter) {
    changes = Computed(() {
      final change = _parent.changes.use;
      return switch (change) {
        ChangeEventReplace<K, V>() =>
          ChangeEventReplace(change.newCollection.removeWhere(_filter)),
        KeyChanges<K, V>() => KeyChanges(
            IMap.fromEntries(change.changes.entries.map((e) => MapEntry(
                e.key,
                switch (e.value) {
                  ChangeRecordValue<V>(value: var value) => _filter(
                          e.key, value)
                      // This might be a duplicate. This is fine. Downstream must be able to handle this.
                      ? ChangeRecordDelete<V>()
                      : ChangeRecordValue(value),
                  ChangeRecordDelete<V>() => ChangeRecordDelete<V>()
                })))),
      };
    });
    snapshot = snapshotComputation(
        changes, () => _parent.snapshot.use.removeWhere(_filter));

    _tracker = CSTracker(changes, snapshot);
  }

  Computed<Option<V>> _getOptionComputation(K key) {
    final parentContainsKey = _parent.containsKey(key);
    final parentValue = _parent[key];
    return _keyOptionComputations.wrap(key, () {
      try {
        final s = snapshot.useWeak;
        // If there is a snapshot, use the value from there
        return s.containsKey(key) ? Option.some(s[key] as V) : Option.none();
      } on NoStrongUserException {
        // We compute the existence of the key ourselves
        if (!parentContainsKey.use) {
          return Option.none();
        } else {
          final parentValueUsed = parentValue.use as V;
          return _filter(key, parentValueUsed)
              ? Option.none()
              : Option.some(parentValueUsed);
        }
      }
    });
  }

  @override
  Computed<bool> containsKey(K key) {
    final c = _getOptionComputation(key);
    return $(() => c.use.is_);
  }

  @override
  Computed<V?> operator [](K key) {
    final c = _getOptionComputation(key);
    return $(() => c.use.value);
  }

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  late final Computed<ChangeEvent<K, V>> changes;
  @override
  late final Computed<IMap<K, V>> snapshot;
  @override
  Computed<bool> get isEmpty =>
      isEmptyExpando[this] ??= $(() => snapshot.use.isEmpty);
  @override
  Computed<bool> get isNotEmpty =>
      isNotEmptyExpando[this] ??= $(() => snapshot.use.isNotEmpty);
  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
