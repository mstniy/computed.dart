import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/expandos.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'utils/cs_tracker.dart';

class AddAllComputedComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  final IComputedMap<K, V> _m;
  final IComputedMap<K, V> _parent;
  late final CSTracker<K, V> _tracker;
  AddAllComputedComputedMap(this._parent, this._m) {
    changes = Computed(() {
      final parentSnapshot = _parent.snapshot.use;
      final mSnapshot = _m.snapshot.use;
      ChangeEvent<K, V>? parentChangeEventPrev, parentChangeEventNow;
      ChangeEvent<K, V>? mChangeEventPrev, mChangeEventNow;
      try {
        parentChangeEventPrev = _parent.changes.prev;
      } catch (NoValueException) {}
      try {
        parentChangeEventNow = _parent.changes.use;
      } catch (NoValueException) {}
      try {
        mChangeEventPrev = _m.changes.prev;
      } catch (NoValueException) {}
      try {
        mChangeEventNow = _m.changes.use;
      } catch (NoValueException) {}

      // Note that here we assume that .changes is in sync with .snapshot for both _parent and _m

      ChangeEvent<K, V>? res;

      if (!identical(parentChangeEventPrev, parentChangeEventNow)) {
        // The parent has a new change
        switch (parentChangeEventNow!) {
          case ChangeEventReplace<K, V>(newCollection: final newCollection):
            res = ChangeEventReplace(newCollection.addAll(mSnapshot));
          case KeyChanges<K, V>(changes: final parentChanges):
            res = KeyChanges(
                IMap.fromEntries(parentChanges.entries.map((upstreamChange) {
              if (mSnapshot.containsKey(upstreamChange.key)) {
                return <MapEntry<K, ChangeRecord<V>>>[];
              }
              return [upstreamChange];
            }).expand((e) => e)));
        }
      }
      if (!identical(mChangeEventPrev, mChangeEventNow)) {
        // The added collection has a new change

        mapMChanges(IMap<K, ChangeRecord<V>> mChanges) {
          return mChanges.entries.map((e) => MapEntry(
              e.key,
              switch (e.value) {
                ChangeRecordValue<V>() => e.value,
                ChangeRecordDelete<V>() => parentSnapshot.containsKey(e.key)
                    ? ChangeRecordValue(parentSnapshot[e.key] as V)
                    : ChangeRecordDelete<V>(),
              }));
        }

        switch (mChangeEventNow!) {
          case ChangeEventReplace<K, V>(newCollection: final newCollection):
            res = ChangeEventReplace(parentSnapshot.addAll(newCollection));
          case KeyChanges<K, V>(changes: final mChanges):
            res = switch (res) {
              null => KeyChanges(IMap.fromEntries(mapMChanges(mChanges))),
              KeyChanges<K, V>() =>
                KeyChanges(res.changes.addEntries(mapMChanges(mChanges))),
              ChangeEventReplace<K, V>() => ChangeEventReplace(res.newCollection
                  .addEntries(mChanges.entries
                      .where((e) => e.value is ChangeRecordValue<V>)
                      .map((e) => MapEntry(
                          e.key, (e.value as ChangeRecordValue<V>).value)))),
            };
        }
      }

      switch (res) {
        case null:
          throw NoValueException();
        case KeyChanges<K, V>():
          if (res.changes.isEmpty) throw NoValueException();
          return res;
        case ChangeEventReplace<K, V>():
          return res;
      }
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
