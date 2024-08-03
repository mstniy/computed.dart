import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../icomputedmap.dart';
import 'computedmap_mixins.dart';

class SnapshotStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  Computed<IMap<K, V>> _snapshotStream;
  late final CSTracker<K, V> _tracker;
  SnapshotStreamComputedMap(this._snapshotStream) {
    final snapshotPrev = $(() {
      _snapshotStream.use;
      try {
        return (_snapshotStream.prev, true);
      } on NoValueException {
        return (<K, V>{}.lock, false);
      }
    });
    changes = $(() {
      final (prev, prevExists) = snapshotPrev.use;
      if (!prevExists) {
        return ChangeEventReplace(_snapshotStream.use);
      }
      final cur = _snapshotStream.use;
      final allKeys = prev.keys.toSet().union(cur.keys.toSet());
      final changes = IMap.fromEntries(allKeys
          .where((e) => prev[e] != cur[e])
          .map((e) => MapEntry(
              e,
              cur.containsKey(e)
                  ? ChangeRecordValue(cur[e] as V)
                  : ChangeRecordDelete<V>())));
      return KeyChanges(changes);
    });
    _tracker = CSTracker(changes, _snapshotStream);
  }

  @override
  Computed<V?> operator [](K key) {
    final sub = _tracker.subKey(key);
    return $(() {
      final used = sub.use;
      return used.is_ ? used.value : null;
    });
  }

  @override
  late final Computed<ChangeEvent<K, V>> changes;

  @override
  Computed<bool> containsKey(K key) {
    final sub = _tracker.subKey(key);
    return $(() => sub.use.is_);
  }

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  Computed<bool> get isEmpty => $(() => _snapshotStream.use.isEmpty);

  @override
  Computed<bool> get isNotEmpty => $(() => _snapshotStream.use.isNotEmpty);

  @override
  Computed<int> get length => $(() => _snapshotStream.use.length);

  @override
  Computed<IMap<K, V>> get snapshot => $(() => _snapshotStream.use);
}
