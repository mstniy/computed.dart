import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:computed_collections/src/expandos.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'utils/cs_tracker.dart';

class AddAllComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  final IMap<K, V> _m;
  final ComputedMap<K, V> _parent;
  late final CSTracker<K, V> _tracker;
  AddAllComputedMap(this._parent, this._m) {
    changes = Computed(() {
      final changeEvent = _parent.changes.use;
      switch (changeEvent) {
        case ChangeEventReplace<K, V>():
          return ChangeEventReplace(changeEvent.newCollection.addAll(_m));
        case KeyChanges<K, V>():
          final changes = changeEvent.changes.entries.map((upstreamChange) {
            if (_m.containsKey(upstreamChange.key)) {
              return <MapEntry<K, ChangeRecord<V>>>[];
            }
            return [upstreamChange];
          }).expand((e) => e);
          if (changes.isEmpty) throw NoValueException();
          return KeyChanges(IMap.fromEntries(changes));
      }
    });
    snapshot =
        snapshotComputation(changes, () => _parent.snapshot.use.addAll(_m));
    _tracker = CSTracker(changes, snapshot);
  }

  Computed<V?> operator [](K key) {
    if (_m.containsKey(key)) return $(() => _m[key]);
    return _parent[key];
  }

  @override
  Computed<bool> containsKey(K key) {
    if (_m.containsKey(key)) return $(() => true);
    return _parent.containsKey(key);
  }

  @override
  Computed<bool> containsValue(V value) {
    if (_m.containsValue(value)) return $(() => true);
    // Cannot just return _parent.containsValue(value) here - we might overwrite it
    return _tracker.containsValue(value);
  }

  late final Computed<ChangeEvent<K, V>> changes;
  late final Computed<IMap<K, V>> snapshot;
  Computed<bool> get isEmpty =>
      isEmptyExpando[this] ??= _m.isNotEmpty ? $(() => false) : _parent.isEmpty;
  Computed<bool> get isNotEmpty => isNotEmptyExpando[this] ??=
      _m.isNotEmpty ? $(() => true) : _parent.isNotEmpty;
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);
}
