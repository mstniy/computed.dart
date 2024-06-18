import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed/utils/streams.dart';
import 'package:computed_collections/src/utils/merging_change_stream.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../change_event.dart';
import '../icomputedmap.dart';
import 'computedmap_mixins.dart';
import 'cs_computedmap.dart';
import 'utils/option.dart';
import 'utils/snapshot_computation.dart';

class GroupByComputedComputedMap<K, V, KParent>
    with OperatorsMixin<K, IComputedMap<KParent, V>>
    implements IComputedMap<K, IComputedMap<KParent, V>> {
  late final MockManager<K, IComputedMap<KParent, V>> _mm;
  final IComputedMap<KParent, V> _parent;
  final Computed<K> Function(KParent key, V value) _convert;

  late final MergingChangeStream<K, IComputedMap<KParent, V>> _changes;

  late final Computed<IMap<K, IComputedMap<KParent, V>>> _snapshot;
  final _keyComputations = ComputationCache<K, IComputedMap<KParent, V>?>();
  final _containsKeyComputations = ComputationCache<K, bool>();
  final _containsValueComputations =
      ComputationCache<IComputedMap<KParent, V>, bool>();

  var _mappedKeysSubs = <KParent, (Option<K>, ComputedSubscription<K>)>{};
  var _m = <K,
      (
    MergingChangeStream<KParent, V>,
    IMap<KParent, V>,
    ValueStream<IMap<KParent, V>>,
  )>{}; // group key -> (change stream, group snapshot, group snapshot stream)

  void _onConvertGroup(KParent parentKey, V value, K groupKey) {
    late final Option<K> oldGroupKey;
    _mappedKeysSubs.update(parentKey, (keySub) {
      oldGroupKey = keySub.$1;
      return (Option.some(groupKey), keySub.$2);
    });
    if (oldGroupKey.is_) {
      // This element has left the old group
      final oldGroup = _m.update(oldGroupKey.value as K, (oldGroup) {
        final newGroupSnapshot = oldGroup.$2.remove(parentKey);
        if (newGroupSnapshot.length > 0) {
          // Otherwise we will remove the group altogether
          if (oldGroup.$1.hasListener) {
            oldGroup.$1
                .add(KeyChanges({parentKey: ChangeRecordDelete<V>()}.lock));
          }
          oldGroup.$3.add(newGroupSnapshot);
        }
        return (oldGroup.$1, newGroupSnapshot, oldGroup.$3);
      });
      if (oldGroup.$2.length == 0) {
        _changes.add(KeyChanges(<K, ChangeRecord<IComputedMap<KParent, V>>>{
          oldGroupKey.value as K: ChangeRecordDelete<IComputedMap<KParent, V>>()
        }.lock));
        _m.remove(oldGroupKey.value as K);
      }
    }
    final group = _m.update(
      groupKey,
      (group) => (group.$1, group.$2.add(parentKey, value), group.$3),
      ifAbsent: () {
        final cs = MergingChangeStream<KParent, V>();
        final snapshot = {parentKey: value}.lock;
        final ss = ValueStream.seeded(snapshot);
        final group = (cs, snapshot, ss);
        final groupCSCM = ChangeStreamComputedMap($(() => cs.use),
            snapshotStream: $(() => ss.use));
        _changes.add(KeyChanges({groupKey: ChangeRecordValue(groupCSCM)}.lock));
        return group;
      },
    );
    if (group.$1.hasListener) {
      group.$1.add(KeyChanges({parentKey: ChangeRecordValue(value)}.lock));
    }
    group.$3.add(group.$2);
  }

  void _onConvertError(Object err) {
    for (var group in _m.values) {
      // TODO: We need cancelOnError semantics
      group.$1.addError(err);
      group.$3.addError(err);
    }
  }

  void _setM(IMap<KParent, V> m) {
    for (var keySub in _mappedKeysSubs.values) {
      keySub.$2.cancel();
    }
    _m.clear();

    _mappedKeysSubs = Map.fromEntries(m.entries.map((e) => MapEntry(e.key, (
          Option.none(),
          _convert(e.key, e.value).listen(
              (group) => _onConvertGroup(e.key, e.value, group),
              _onConvertError)
        ))));
  }

  GroupByComputedComputedMap(this._parent, this._convert) {
    final computedChanges = Computed.async(() {
      final change = _parent.changes.use;

      switch (change) {
        case ChangeEventReplace<KParent, V>():
          _setM(change.newCollection);
          // The new listeners will definitely not be fired synchronously
          // (as per the stream contract), so we can safely emit an empty
          // replacement here.
          return ChangeEventReplace(<K, IComputedMap<KParent, V>>{}.lock);
        case KeyChanges<KParent, V>():
          final (groupedByIsDelete, _) =
              change.changes.groupBy((_, e) => e is ChangeRecordDelete);
          final deletedKeys =
              groupedByIsDelete[true]?.keys.toSet() ?? <KParent>{};
          final valueKeysAndSubs = groupedByIsDelete[false]?.map((k, v_) {
                final v = (v_ as ChangeRecordValue<V>).value;
                return MapEntry(k, (
                  _convert(k, v).listen(
                      (group) => _onConvertGroup(k, v, group), _onConvertError),
                  v
                ));
              }) ??
              <KParent, (ComputedSubscription<K>, V)>{};

          final keyChanges = <K, ChangeRecord<IComputedMap<KParent, V>>>{};

          final batchedChanges = <K,
              KeyChanges<KParent,
                  V>?>{}; // If null -> just notify the snapshot stream

          void _removeOrReplaceKeyGroupSub(
              KParent parentKey, ComputedSubscription<K>? newSub) {
            late final (Option<K>, ComputedSubscription<K>)? oldGroupKeySub;
            if (newSub != null) {
              final newKeySub = (Option<K>.none(), newSub);
              _mappedKeysSubs.update(parentKey, (keySub) {
                oldGroupKeySub = keySub;
                return newKeySub;
              }, ifAbsent: () {
                oldGroupKeySub = null;
                return newKeySub;
              });
            } else {
              oldGroupKeySub = _mappedKeysSubs.remove(parentKey);
            }
            if (oldGroupKeySub != null) {
              if (oldGroupKeySub!.$1.is_) {
                final oldGroupKey = oldGroupKeySub!.$1.value as K;
                final oldGroup = _m.update(
                    oldGroupKey, (g) => (g.$1, g.$2.remove(parentKey), g.$3));

                if (oldGroup.$2.isEmpty) {
                  keyChanges[oldGroupKey] = ChangeRecordDelete();
                  batchedChanges.remove(oldGroupKey);
                  _m.remove(oldGroupKey);
                } else {
                  if (!oldGroup.$1.hasListener) {
                    batchedChanges[oldGroupKey] = null;
                  } else {
                    batchedChanges.update(
                        oldGroupKey,
                        (changes) => KeyChanges(changes!.changes
                            .add(parentKey, ChangeRecordDelete<V>())),
                        ifAbsent: () => KeyChanges(<KParent, ChangeRecord<V>>{
                              parentKey: ChangeRecordDelete<V>()
                            }.lock));
                  }
                }
              }
              oldGroupKeySub!.$2.cancel();
            }
          }

          for (var e in valueKeysAndSubs.entries) {
            _removeOrReplaceKeyGroupSub(e.key, e.value.$1);
          }

          for (var deletedKey in deletedKeys) {
            _removeOrReplaceKeyGroupSub(deletedKey, null);
          }

          // Publish the aggregated changes
          for (var e in batchedChanges.entries) {
            final group = _m[e.key]!;
            if (e.value != null) {
              group.$1.add(e.value!);
            }
            group.$3.add(group.$2);
          }

          return KeyChanges(keyChanges.lock);
      }
      // We set memoized to false as this is a change stream merged with another change stream
      // (coming from the group computations - see [_onConvertGroup])
    }, memoized: false);
    ComputedSubscription<ChangeEvent<K, IComputedMap<KParent, V>>>?
        computedChangesSubscription;
    _changes = MergingChangeStream(
        onListen: () => computedChangesSubscription =
            computedChanges.listen(_changes.add, _changes.addError),
        onCancel: () {
          computedChangesSubscription!.cancel();
          for (var ksub in _mappedKeysSubs.values) {
            ksub.$2.cancel();
          }
          _mappedKeysSubs = {};
          _m = {};
        });
    final changesComputed = $(() => _changes.use);
    _snapshot = snapshotComputation(changesComputed, () {
      _setM(_parent.snapshot.use);
      return <K, IComputedMap<KParent, V>>{}.lock;
    });

    _mm = MockManager(
        changesComputed,
        _snapshot,
        $(() => snapshot.use.length),
        $(() => _parent.isEmpty.use),
        $(() => _parent.isNotEmpty.use),
        _keyComputations,
        _containsKeyComputations,
        _containsValueComputations);
  }

  @override
  Computed<bool> containsKey(K key) =>
      _containsKeyComputations.wrap(key, () => _snapshot.use.containsKey(key));

  @override
  Computed<IComputedMap<KParent, V>?> operator [](K key) =>
      _keyComputations.wrap(key, () => _snapshot.use[key]);

  @override
  Computed<bool> containsValue(IComputedMap<KParent, V> value) =>
      _containsValueComputations.wrap(
          value, () => _snapshot.use.containsValue(value));

  @override
  void fix(IMap<K, IComputedMap<KParent, V>> value) => _mm.fix(value);

  @override
  void fixThrow(Object e) => _mm.fixThrow(e);

  @override
  void mock(IComputedMap<K, IComputedMap<KParent, V>> mock) => _mm.mock(mock);

  @override
  void unmock() => _mm.unmock();

  @override
  Computed<IMap<K, IComputedMap<KParent, V>>> get snapshot => _mm.snapshot;

  @override
  Computed<ChangeEvent<K, IComputedMap<KParent, V>>> get changes => _mm.changes;

  @override
  Computed<bool> get isEmpty => _mm.isEmpty;
  @override
  Computed<bool> get isNotEmpty => _mm.isNotEmpty;

  @override
  Computed<int> get length => _mm.length;
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
