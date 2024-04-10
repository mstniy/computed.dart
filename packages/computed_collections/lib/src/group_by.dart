import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/scs_computedmap.dart';
import 'package:computed_collections/src/utils/merging_change_stream.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';

class GroupByComputedMap<K, V, KParent>
    with
        OperatorsMixin<K, IComputedMap<KParent, V>>,
        MockMixin<K, IComputedMap<KParent, V>>
    implements IComputedMap<K, IComputedMap<KParent, V>> {
  final IComputedMap<KParent, V> _parent;
  final K Function(KParent key, V value) _convert;
  final Computed<bool> isEmpty;
  final Computed<bool> isNotEmpty;
  late final Computed<int> length;
  late final Computed<ChangeEvent<K, IComputedMap<KParent, V>>> changes;
  late final Computed<IMap<K, IComputedMap<KParent, V>>> snapshot;

  final keyComputations = ComputationCache<K, IComputedMap<KParent, V>?>();
  final containsKeyComputations = ComputationCache<K, bool>();
  final containsValueComputations =
      ComputationCache<IComputedMap<KParent, V>, bool>();

  var _mappedKeys = <KParent, K>{};
  var _m = <K,
      (
    MergingChangeStream<KParent, V>,
    ValueStream<IMap<KParent, V>>,
    IMap<KParent, V>
  )>{};

  IMap<K, IComputedMap<KParent, V>> _setM(IMap<KParent, V> m) {
    final (grouped, mappedKeys) = m.groupBy(_convert);

    _m = grouped.map((k, v) {
      final vlocked = v.lock;
      return MapEntry(
          k, (MergingChangeStream(), ValueStream.seeded(vlocked), vlocked));
    });
    _mappedKeys = mappedKeys;

    return _m.map((k, v) {
      return MapEntry(k, SnapshotChangeStreamComputedMap(v.$1, v.$2));
    }).lock;
  }

  GroupByComputedMap(this._parent, this._convert)
      // We wrap the parent's attributes into new computations
      // so that they are independently mockable
      : isEmpty = $(() => _parent.isEmpty.use),
        isNotEmpty = $(() => _parent.isNotEmpty.use) {
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
          final valueKeysAndGroups =
              groupedByIsDelete[false]?.map((k, v) => MapEntry(k, (
                        // TODO: Can we idempotency-check the user-supplied key?
                        _convert(k, (v as ChangeRecordValue<V>).value),
                        v.value
                      ))) ??
                  <KParent, (K, V)>{};

          final keyChanges = <K, ChangeRecord<IComputedMap<KParent, V>>>{};
          for (var deletedKey in deletedKeys) {
            if (!_mappedKeys.containsKey(deletedKey))
              continue; // Extraneous deletion from upstream?
            final oldGroup = _mappedKeys[deletedKey] as K;
            _mappedKeys.remove(deletedKey);
            _m.update(oldGroup, (group) {
              group = (group.$1, group.$2, group.$3.remove(deletedKey));
              if (group.$3.isEmpty) {
                keyChanges[oldGroup] = ChangeRecordDelete();
              } else {
                group.$1.add(
                    KeyChanges({deletedKey: ChangeRecordDelete<V>()}.lock));
                group.$2.add(group.$3);
              }
              return group;
            }); // Not passing `ifAbsent` as the key has to be present (ow/ we have a corrupt internal state)
          }

          for (var e in valueKeysAndGroups.entries) {
            final groupKey = e.value.$1;
            final parentKey = e.key;
            final value = e.value.$2;
            final group = _m.update(
              groupKey,
              (group) => (group.$1, group.$2, group.$3.add(parentKey, value)),
              ifAbsent: () {
                final group = (
                  MergingChangeStream<KParent, V>(),
                  ValueStream<IMap<KParent, V>>(),
                  {parentKey: value}.lock
                );
                keyChanges[groupKey] = ChangeRecordValue(
                    SnapshotChangeStreamComputedMap(group.$1, group.$2));
                return group;
              },
            );
            group.$1
                .add(KeyChanges({parentKey: ChangeRecordValue<V>(value)}.lock));
            group.$2.add(group.$3);
            final oldGroupKey = _mappedKeys[parentKey];
            _mappedKeys[parentKey] = groupKey;
            if (oldGroupKey != null) {
              if (oldGroupKey != groupKey) {
                final oldGroup = _m.update(
                    oldGroupKey, (g) => (g.$1, g.$2, g.$3.remove(parentKey)));
                if (oldGroup.$3.isEmpty) {
                  keyChanges[oldGroupKey] = ChangeRecordDelete();
                  _m.remove(oldGroupKey);
                } else {
                  oldGroup.$1.add(
                      KeyChanges({parentKey: ChangeRecordDelete<V>()}.lock));
                  oldGroup.$2.add(oldGroup.$3);
                }
              }
            }
          }

          return KeyChanges(keyChanges.lock);
      }
    }, onDispose: (e) => _onDispose(), onDisposeError: (o) => _onDispose());
    snapshot = ChangeStreamComputedMap(changes.asBroadcastStream, () {
      final s = _parent.snapshot.use;
      return _setM(s);
    }).snapshot;

    length = $(() => snapshot.use.length);
  }

  void _onDispose() {
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
