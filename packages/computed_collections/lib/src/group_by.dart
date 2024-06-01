import 'dart:async';

import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../icomputedmap.dart';
import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';
import 'utils/snapshot_computation.dart';

class GroupByComputedMap<K, V, KParent>
    with OperatorsMixin<K, IComputedMap<KParent, V>>
    implements IComputedMap<K, IComputedMap<KParent, V>> {
  late final MockManager<K, IComputedMap<KParent, V>> _mm;
  final IComputedMap<KParent, V> _parent;
  final K Function(KParent key, V value) _convert;
  final Computed<bool> isEmpty;
  final Computed<bool> isNotEmpty;
  late final Computed<int> length;
  late final Computed<ChangeEvent<K, IComputedMap<KParent, V>>> _changes;
  Computed<ChangeEvent<K, IComputedMap<KParent, V>>> get changes => _mm.changes;
  late final Computed<IMap<K, IComputedMap<KParent, V>>> snapshot;

  final keyComputations = ComputationCache<K, IComputedMap<KParent, V>?>();
  final containsKeyComputations = ComputationCache<K, bool>();
  final containsValueComputations =
      ComputationCache<IComputedMap<KParent, V>, bool>();

  var _mappedKeys = <KParent, K>{};
  // TODO: GroupByComputedMap keeps its own snapshots (in `_m`), so do the groups' ChangeStreamComputedMap-s.
  //  Can we de-dup this replicated effort?
  var _m = <K,
      (
    StreamController<ChangeEvent<KParent, V>>,
    IMap<KParent, V>
  )>{}; // group key -> (change stream, group snapshot)

  IMap<K, IComputedMap<KParent, V>> _setM(IMap<KParent, V> m) {
    final (grouped, mappedKeys) = m.groupBy(_convert);

    _m = grouped.map((k, v) {
      final vlocked = v.lock;
      final cs = StreamController<ChangeEvent<KParent, V>>.broadcast();
      return MapEntry(k, (cs, vlocked));
    });
    _mappedKeys = mappedKeys;

    return _m.map((k, v) {
      final stream = v.$1.stream;
      return MapEntry(
          k,
          ChangeStreamComputedMap($(() => stream.use),
              initialValueComputer: () => _m[k]?.$2 ?? <KParent, V>{}.lock));
    }).lock;
  }

  GroupByComputedMap(this._parent, this._convert)
      // We wrap the parent's attributes into new computations
      // so that they are independently mockable
      : isEmpty = $(() => _parent.isEmpty.use),
        isNotEmpty = $(() => _parent.isNotEmpty.use) {
    _changes = Computed.async(() {
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

          final batchedChanges = <K, KeyChanges<KParent, V>>{};

          for (var e in valueKeysAndGroups.entries) {
            final groupKey = e.value.$1;
            final parentKey = e.key;
            final value = e.value.$2;
            _m.update(
              groupKey,
              (group) => (group.$1, group.$2.add(parentKey, value)),
              ifAbsent: () {
                final cs =
                    StreamController<ChangeEvent<KParent, V>>.broadcast();
                final stream = cs.stream;
                final group = (cs, {parentKey: value}.lock);
                keyChanges[groupKey] = ChangeRecordValue(
                    ChangeStreamComputedMap($(() => stream.use),
                        initialValueComputer: () =>
                            _m[groupKey]?.$2 ?? <KParent, V>{}.lock));
                return group;
              },
            );
            batchedChanges.update(
                groupKey,
                (changes) => KeyChanges(
                    changes.changes.add(e.key, ChangeRecordValue(e.value.$2))),
                ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                      e.key: ChangeRecordValue(e.value.$2)
                    }.lock));
            final oldGroupKey = _mappedKeys[parentKey];
            _mappedKeys[parentKey] = groupKey;
            if (oldGroupKey != null) {
              if (oldGroupKey != groupKey) {
                final oldGroup = _m.update(
                    oldGroupKey, (g) => (g.$1, g.$2.remove(parentKey)));
                if (oldGroup.$2.isEmpty) {
                  keyChanges[oldGroupKey] = ChangeRecordDelete();
                  _m.remove(oldGroupKey);
                  batchedChanges.remove(oldGroupKey);
                } else {
                  batchedChanges.update(
                      oldGroupKey,
                      (changes) => KeyChanges(
                          changes.changes.add(e.key, ChangeRecordDelete<V>())),
                      ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                            e.key: ChangeRecordDelete<V>()
                          }.lock));
                }
              }
            }
          }

          for (var deletedKey in deletedKeys) {
            if (!_mappedKeys.containsKey(deletedKey))
              continue; // Extraneous deletion from upstream?
            final oldGroup = _mappedKeys.remove(deletedKey) as K;
            _m.update(oldGroup, (group) {
              group = (group.$1, group.$2.remove(deletedKey));
              if (group.$2.isEmpty) {
                keyChanges[oldGroup] = ChangeRecordDelete();
                batchedChanges.remove(oldGroup);
              } else {
                batchedChanges.update(
                    oldGroup,
                    (changes) => KeyChanges(changes.changes
                        .add(deletedKey, ChangeRecordDelete<V>())),
                    ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                          deletedKey: ChangeRecordDelete<V>()
                        }.lock));
                group.$1.add(KeyChanges(<KParent, ChangeRecord<V>>{
                  deletedKey: ChangeRecordDelete<V>()
                }.lock));
              }
              return group;
            }); // Not passing `ifAbsent` as the key has to be present (ow/ we have a corrupt internal state)
          }

          for (var e in batchedChanges.entries) {
            final group = _m[e.key]!;
            group.$1.add(e.value);
          }

          return KeyChanges(keyChanges.lock);
      }
    }, onCancel: _onCancel);
    snapshot = snapshotComputation(_changes, () {
      final s = _parent.snapshot.use;
      return _setM(s);
    });

    length = $(() => snapshot.use.length);
    _mm = MockManager(_changes, snapshot, length, isEmpty, isNotEmpty,
        keyComputations, containsKeyComputations, containsValueComputations);
  }

  void _onCancel() {
    _mappedKeys = {};
    _m = {};
  }

  @override
  Computed<bool> containsKey(K key) =>
      containsKeyComputations.wrap(key, () => snapshot.use.containsKey(key));

  @override
  Computed<IComputedMap<KParent, V>?> operator [](K key) =>
      keyComputations.wrap(key, () => snapshot.use[key]);

  @override
  Computed<bool> containsValue(IComputedMap<KParent, V> value) =>
      containsValueComputations.wrap(
          value, () => snapshot.use.containsValue(value));

  @override
  void fix(IMap<K, IComputedMap<KParent, V>> value) => _mm.fix(value);

  @override
  void fixThrow(Object e) => _mm.fixThrow(e);

  @override
  void mock(IComputedMap<K, IComputedMap<KParent, V>> mock) => _mm.mock(mock);

  @override
  void unmock() => _mm.unmock();
}

extension<K, V> on IMap<K, V> {
  (Map<K2, Map<K, V>>, Map<K, K2>) groupBy<K2>(K2 Function(K key, V value) f) {
    final res = <K2, Map<K, V>>{};
    final maps = <K, K2>{};
    for (var e in this.entries) {
      final k2 = f(e.key, e.value);
      maps[e.key] = k2;
      res.update(k2, (v) {
        v[e.key] = e.value;
        return v;
      }, ifAbsent: () => {e.key: e.value});
    }
    return (res, maps);
  }
}
