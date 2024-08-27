import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/streams.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../icomputedmap.dart';
import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';
import 'utils/cs_tracker.dart';
import 'utils/snapshot_computation.dart';
import 'utils/group_by.dart';
import 'expandos.dart';

class GroupByComputedMap<K, V, KParent>
    with OperatorsMixin<K, IComputedMap<KParent, V>>
    implements IComputedMap<K, IComputedMap<KParent, V>> {
  final IComputedMap<KParent, V> _parent;
  final K Function(KParent key, V value) _convert;

  late final CSTracker<K, IComputedMap<KParent, V>> _tracker;

  var _mappedKeys = <KParent, K>{};
  var _m = <K,
      (
    StreamController<ChangeEvent<KParent, V>>,
    IMap<KParent, V>,
    ValueStream<IMap<KParent, V>>,
  )>{}; // group key -> (change stream, group snapshot, group snapshot stream)

  IMap<K, IComputedMap<KParent, V>> _setM(IMap<KParent, V> m) {
    final (grouped, mappedKeys) = m.groupBy(_convert);

    _m = grouped.map((k, v) {
      final vlocked = v.lock;
      final cs = StreamController<ChangeEvent<KParent, V>>.broadcast();
      final ss = ValueStream.seeded(vlocked);
      return MapEntry(k, (cs, vlocked, ss));
    });
    _mappedKeys = mappedKeys;

    return _m.map((k, v) {
      final cstream = v.$1.stream;
      return MapEntry<K, IComputedMap<KParent, V>>(
          k,
          ChangeStreamComputedMap($(() => cstream.use),
              snapshotStream: $(() => v.$3.use)));
    }).lock;
  }

  GroupByComputedMap(this._parent, this._convert) {
    changes = Computed.async(() {
      final change = _parent.changes.use;

      switch (change) {
        case ChangeEventReplace<KParent, V>():
          return ChangeEventReplace(_setM(change.newCollection));
        case KeyChanges<KParent, V>():
          final (groupedByIsDelete, _) =
              change.changes.groupBy((_, e) => e is ChangeRecordDelete);
          final deletedKeys =
              groupedByIsDelete[true]?.keys.toSet() ?? <KParent>{};
          final valueKeysAndGroups = groupedByIsDelete[false]?.map((k, v) =>
                  MapEntry(k, (
                    _convert(k, (v as ChangeRecordValue<V>).value),
                    v.value
                  ))) ??
              <KParent, (K, V)>{};

          final keyChanges = <K, ChangeRecord<IComputedMap<KParent, V>>>{};

          final batchedChanges = <K,
              KeyChanges<KParent,
                  V>?>{}; // If null -> just notify the snapshot stream

          for (var e in valueKeysAndGroups.entries) {
            final groupKey = e.value.$1;
            final parentKey = e.key;
            final value = e.value.$2;
            final group = _m.update(
              groupKey,
              (group) => (group.$1, group.$2.add(parentKey, value), group.$3),
              ifAbsent: () {
                final cs =
                    StreamController<ChangeEvent<KParent, V>>.broadcast();
                final snapshot = {parentKey: value}.lock;
                final ss = ValueStream.seeded(snapshot);
                final cstream = cs.stream;
                final group = (cs, snapshot, ss);
                keyChanges[groupKey] = ChangeRecordValue(
                    ChangeStreamComputedMap($(() => cstream.use),
                        snapshotStream: $(() => ss.use)));
                return group;
              },
            );
            if (!group.$1.hasListener) {
              batchedChanges[groupKey] = null;
            } else {
              batchedChanges.update(
                  groupKey,
                  (changes) => KeyChanges(changes!.changes
                      .add(e.key, ChangeRecordValue(e.value.$2))),
                  ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                        e.key: ChangeRecordValue(e.value.$2)
                      }.lock));
            }
            final hasOldGroup = _mappedKeys.containsKey(parentKey);
            final oldGroupKey = _mappedKeys[parentKey];
            _mappedKeys[parentKey] = groupKey;
            if (hasOldGroup) {
              if (oldGroupKey != groupKey) {
                final oldGroup = _m.update(oldGroupKey as K,
                    (g) => (g.$1, g.$2.remove(parentKey), g.$3));
                if (oldGroup.$2.isEmpty) {
                  keyChanges[oldGroupKey] = ChangeRecordDelete();
                  _m.remove(oldGroupKey);
                  batchedChanges.remove(oldGroupKey);
                } else {
                  if (!oldGroup.$1.hasListener) {
                    batchedChanges[oldGroupKey] = null;
                  } else {
                    batchedChanges.update(
                        oldGroupKey,
                        (changes) => KeyChanges(changes!.changes
                            .add(e.key, ChangeRecordDelete<V>())),
                        ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                              e.key: ChangeRecordDelete<V>()
                            }.lock));
                  }
                }
              }
            }
          }

          for (var deletedKey in deletedKeys) {
            if (!_mappedKeys.containsKey(deletedKey))
              continue; // Extraneous deletion from upstream?
            final oldGroupKey = _mappedKeys.remove(deletedKey) as K;
            final oldGroup = _m.update(
                oldGroupKey,
                (oldGroup) => (
                      oldGroup.$1,
                      oldGroup.$2.remove(deletedKey),
                      oldGroup.$3
                    )); // Not passing `ifAbsent` as the key has to be present (ow/ we have a corrupt internal state)
            if (oldGroup.$2.isEmpty) {
              keyChanges[oldGroupKey] = ChangeRecordDelete();
              _m.remove(
                  oldGroupKey); // TODO: Have a regression test for this -> delete an upstream key, removing a group, re-add that group, whiile not subbed to it -> breaks, the re-introduction of the group is never announced on the main CS
              batchedChanges.remove(oldGroupKey);
            } else {
              if (!oldGroup.$1.hasListener) {
                batchedChanges[oldGroupKey] = null;
              } else {
                batchedChanges.update(
                    oldGroupKey,
                    (changes) => KeyChanges(changes!.changes
                        .add(deletedKey, ChangeRecordDelete<V>())),
                    ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                          deletedKey: ChangeRecordDelete<V>()
                        }.lock));
              }
            }
          }

          for (var e in batchedChanges.entries) {
            final group = _m[e.key]!;
            if (e.value != null) {
              group.$1.add(e.value!);
            }
            group.$3.add(group.$2);
          }

          if (keyChanges.isNotEmpty) {
            return KeyChanges(keyChanges.lock);
          } else {
            throw NoValueException();
          }
      }
    }, onCancel: _onCancel);
    snapshot = snapshotComputation(changes, () {
      final s = _parent.snapshot.use;
      return _setM(s);
    });

    _tracker = CSTracker(changes, snapshot);
  }

  void _onCancel() {
    _mappedKeys = {};
    _m = {};
  }

  @override
  Computed<bool> containsKey(K key) => _tracker.containsKey(key);

  @override
  Computed<IComputedMap<KParent, V>?> operator [](K key) => _tracker[key];

  @override
  Computed<bool> containsValue(IComputedMap<KParent, V> value) =>
      _tracker.containsValue(value);

  @override
  late final Computed<IMap<K, IComputedMap<KParent, V>>> snapshot;

  @override
  late final Computed<ChangeEvent<K, IComputedMap<KParent, V>>> changes;

  @override
  Computed<bool> get isEmpty => _parent.isEmpty;
  @override
  Computed<bool> get isNotEmpty => _parent.isNotEmpty;

  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
