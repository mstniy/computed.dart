import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:computed_collections/src/utils/get_if_changed.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'expandos.dart';
import 'utils/cs_tracker.dart';
import 'utils/option.dart';

class JoinComputedMap<K, V1, V2>
    with OperatorsMixin<K, (V1, V2)>
    implements ComputedMap<K, (V1, V2)> {
  final ComputedMap<K, V1> _parent1;
  final ComputedMap<K, V2> _parent2;
  late final CSTracker<K, (V1, V2)> _tracker;
  JoinComputedMap(this._parent1, this._parent2) {
    changes = Computed(() {
      final parent1Snapshot = _parent1.snapshot.use;
      final parent2Snapshot = _parent2.snapshot.use;
      final parent1Change = getIfChanged(_parent1.changes);
      final parent2Change = getIfChanged(_parent2.changes);

      // Note that here we assume that .changes is in sync with .snapshot for both parents

      if (parent1Change is ChangeEventReplace ||
          parent2Change is ChangeEventReplace) {
        return ChangeEventReplace(
            _computeSnapshot(parent1Snapshot, parent2Snapshot));
      }

      final keyChanges = <K, ChangeRecord<(V1, V2)>>{};

      if (parent1Change != null) {
        // _parent1 has a new change
        for (var e in (parent1Change as KeyChanges<K, V1>).changes.entries) {
          switch (e.value) {
            case ChangeRecordValue<V1>(value: final v1):
              if (parent2Snapshot.containsKey(e.key)) {
                keyChanges[e.key] =
                    ChangeRecordValue((v1, parent2Snapshot[e.key] as V2));
              }
            case ChangeRecordDelete<V1>():
              // There is no immediately obvious way to know if we used to have this key,
              // so broadcast a deletion just to be safe
              keyChanges[e.key] = ChangeRecordDelete();
          }
        }
      }

      if (parent2Change != null) {
        // _parent2 has a new change
        for (var e in (parent2Change as KeyChanges<K, V2>).changes.entries) {
          switch (e.value) {
            case ChangeRecordValue<V2>(value: final v2):
              if (parent1Snapshot.containsKey(e.key)) {
                keyChanges[e.key] =
                    ChangeRecordValue((parent1Snapshot[e.key] as V1, v2));
              }
            case ChangeRecordDelete<V2>():
              // There is no immediately obvious way to know if we used to have this key,
              // so broadcast a deletion just to be safe
              keyChanges[e.key] = ChangeRecordDelete();
          }
        }
      }

      if (keyChanges.isEmpty) {
        throw NoValueException();
      }

      return KeyChanges(keyChanges.lock);
    });
    snapshot = snapshotComputation(changes,
        () => _computeSnapshot(_parent1.snapshot.use, _parent2.snapshot.use));
    _tracker = CSTracker(changes, snapshot);
  }

  IMap<K, (V1, V2)> _computeSnapshot(IMap<K, V1> s1, IMap<K, V2> s2) =>
      IMap.fromEntries(switch (s1.length < s2.length) {
        true => s1.entries
            .where((e) => s2.containsKey(e.key))
            .map((e) => MapEntry(e.key, (e.value, s2[e.key] as V2))),
        false => s2.entries
            .where((e) => s1.containsKey(e.key))
            .map((e) => MapEntry(e.key, (s1[e.key] as V1, e.value))),
      });

  final _keyComputationCache = ComputationCache<K, Option<(V1, V2)>>();

  Computed<Option<(V1, V2)>> _getKeyComputation(K key) {
    final p1containsKey = _parent1.containsKey(key);
    final p2containsKey = _parent2.containsKey(key);
    final p1Value = _parent1[key];
    final p2Value = _parent2[key];
    return _keyComputationCache.wrap(key, () {
      if (!(p1containsKey.use && p2containsKey.use)) {
        return Option.none();
      }
      return Option.some((p1Value.use as V1, p2Value.use as V2));
    });
  }

  @override
  Computed<(V1, V2)?> operator [](K key) {
    final keyComputation = _getKeyComputation(key);
    return $(() => keyComputation.use.value);
  }

  @override
  Computed<bool> containsKey(K key) {
    final keyComputation = _getKeyComputation(key);
    return $(() => keyComputation.use.is_);
  }

  @override
  Computed<bool> containsValue((V1, V2) value) {
    return _tracker.containsValue(value);
  }

  @override
  late final Computed<ChangeEvent<K, (V1, V2)>> changes;
  @override
  late final Computed<IMap<K, (V1, V2)>> snapshot;
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
