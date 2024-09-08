import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:computed_collections/src/expandos.dart';
import 'package:computed_collections/src/utils/get_if_changed.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'utils/cs_tracker.dart';

class AddAllComputedComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  final ComputedMap<K, V> _m;
  final ComputedMap<K, V> _parent;
  late final CSTracker<K, V> _tracker;
  AddAllComputedComputedMap(this._parent, this._m) {
    changes = Computed(() {
      final parentSnapshot = _parent.snapshot.use;
      final mSnapshot = _m.snapshot.use;
      final parentChange = getIfChanged(_parent.changes);
      final mChange = getIfChanged(_m.changes);

      // Note that here we assume that .changes is in sync with .snapshot for both _parent and _m

      if (parentChange is ChangeEventReplace<K, V> ||
          mChange is ChangeEventReplace<K, V>) {
        return ChangeEventReplace(parentSnapshot.addAll(mSnapshot));
      }

      var res = <K, ChangeRecord<V>>{};

      if (parentChange != null) {
        // The parent has a new change

        final parentChanges = (parentChange as KeyChanges<K, V>).changes;

        res = Map.fromEntries(parentChanges.entries.map((upstreamChange) {
          if (mSnapshot.containsKey(upstreamChange.key)) {
            return <MapEntry<K, ChangeRecord<V>>>[];
          }
          return [upstreamChange];
        }).expand((e) => e));
      }
      if (mChange != null) {
        // The added collection has a new change

        final mChanges = (mChange as KeyChanges<K, V>).changes;

        res.addEntries(mChanges.entries.map((e) => MapEntry(
            e.key,
            switch (e.value) {
              ChangeRecordValue<V>() => e.value,
              ChangeRecordDelete<V>() => parentSnapshot.containsKey(e.key)
                  ? ChangeRecordValue(parentSnapshot[e.key] as V)
                  : ChangeRecordDelete<V>(),
            })));
      }

      if (res.isEmpty) throw NoValueException();
      return KeyChanges(res.lock);
    });
    snapshot = snapshotComputation(
        changes, () => _parent.snapshot.use.addAll(_m.snapshot.use));
    _tracker = CSTracker(changes, snapshot);
  }

  Computed<V?> operator [](K key) {
    final mContainsKey = _m.containsKey(key);
    final mKey = _m[key];
    final parentKey = _parent[key];
    return $(() => mContainsKey.use ? mKey.use : parentKey.use);
  }

  @override
  Computed<bool> containsKey(K key) {
    final mContainsKey = _m.containsKey(key);
    final parentContainsKey = _parent.containsKey(key);
    return $(() => mContainsKey.use ? true : parentContainsKey.use);
  }

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  late final Computed<ChangeEvent<K, V>> changes;
  late final Computed<IMap<K, V>> snapshot;
  Computed<bool> get isEmpty =>
      isEmptyExpando[this] ??= $(() => _parent.isEmpty.use && _m.isEmpty.use);
  Computed<bool> get isNotEmpty => isNotEmptyExpando[this] ??=
      $(() => _parent.isNotEmpty.use || _m.isNotEmpty.use);
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
