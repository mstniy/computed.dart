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
  final _mappedKeysReverse = <K,
      Set<KParent>>{}; // So that we know when to emit deletion events for the collection
  var _streams =
      <K, (MergingChangeStream<KParent, V>, ValueStream<IMap<KParent, V>>)>{};
  var _m = <K, IMap<KParent, V>>{};

  IMap<K, IComputedMap<KParent, V>> _setM(IMap<KParent, V> m) {
    final (grouped, mappedKeys) = m.groupBy(_convert);

    _m = grouped.map((k, v) => MapEntry(k, v.lock));
    _mappedKeys = mappedKeys;
    _mappedKeysReverse.clear();
    for (var e in _mappedKeys.entries) {
      _mappedKeysReverse.update(e.value, (s) {
        s.add(e.key);
        return s;
      }, ifAbsent: () => {e.key});
    }

    _streams = _m.map(
        (k, v) => MapEntry(k, (MergingChangeStream(), ValueStream.seeded(v))));

    return grouped.map((k, v) {
      final streams = _streams[k]!;
      return MapEntry(
          k, SnapshotChangeStreamComputedMap(streams.$1, streams.$2));
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

          final extinctKeys = <K>{};
          for (var deletedKey in deletedKeys) {
            if (!_mappedKeys.containsKey(deletedKey))
              continue; // Extraneous deletion from upstream?
            final oldGroup = _mappedKeys[deletedKey] as K;
            final newReverseKeys = _mappedKeysReverse.update(oldGroup, (s) {
              s.remove(deletedKey);
              return s;
            });
            _mappedKeys.remove(deletedKey);
            final groupMap = _m.update(
                oldGroup,
                (m) => m.remove(
                    deletedKey)); // Not passing `ifAbsent` as the key has to be present (ow/ we have a corrupt internal state)
            if (newReverseKeys.isEmpty) {
              extinctKeys.add(oldGroup);
            } else {
              final streams = _streams[oldGroup]!;
              streams.$1
                  .add(KeyChanges({deletedKey: ChangeRecordDelete<V>()}.lock));
              streams.$2.add(groupMap);
            }
          }

          final newKeys = <K>{};
          for (var e in valueKeysAndGroups.entries) {
            final groupKey = e.value.$1;
            final parentKey = e.key;
            final value = e.value.$2;
            late final IMap<KParent, V> groupMap;
            late final bool groupIsNew;
            _mappedKeysReverse.update(groupKey, (s) {
              groupIsNew = false;
              s.add(parentKey);
              groupMap = _m.update(
                  groupKey,
                  (m) => m.add(parentKey,
                      value)); // Not passing `ifAbsent` as the key has to be present (ow/ we have a corrupt internal state)
              return s;
            }, ifAbsent: () {
              groupIsNew = true;
              newKeys.add(groupKey);
              groupMap = {parentKey: value}.lock;
              _m[groupKey] = groupMap;
              return {parentKey};
            });
            final oldGroupKey = _mappedKeys[parentKey];
            _mappedKeys[parentKey] = groupKey;
            if (oldGroupKey != null) {
              if (oldGroupKey != groupKey) {
                final newReverseKeys =
                    _mappedKeysReverse.update(oldGroupKey, (s) {
                  s.remove(parentKey);
                  return s;
                }); // Not passing `ifAbsent` as the key has to be present (ow/ we have a corrupt internal state)
                final oldGroupMap =
                    _m.update(oldGroupKey, (m) => m.remove(parentKey));
                if (newReverseKeys.isEmpty) {
                  extinctKeys.add(oldGroupKey);
                  _m.remove(oldGroupKey);
                } else {
                  final streams = _streams[oldGroupKey]!;
                  streams.$1.add(
                      KeyChanges({parentKey: ChangeRecordDelete<V>()}.lock));
                  streams.$2.add(oldGroupMap);
                }
              }
            } else {}
            late final (
              MergingChangeStream<KParent, V>,
              ValueStream<IMap<KParent, V>>
            ) streams;
            if (groupIsNew) {
              streams = (MergingChangeStream(), ValueStream());
              _streams[groupKey] = streams;
            } else {
              streams = _streams[groupKey]!;
            }
            streams.$1
                .add(KeyChanges({parentKey: ChangeRecordValue<V>(value)}.lock));
            streams.$2.add(groupMap);
          }

          return KeyChanges(IMap.fromEntries([
            ...extinctKeys.map((k) =>
                MapEntry(k, ChangeRecordDelete<IComputedMap<KParent, V>>())),
            ...newKeys.map((k) {
              final streams = _streams[k]!;
              return MapEntry(
                  k,
                  ChangeRecordValue(
                      SnapshotChangeStreamComputedMap(streams.$1, streams.$2)));
            })
          ]));
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
    _mappedKeysReverse.clear();
    _streams = {};
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
