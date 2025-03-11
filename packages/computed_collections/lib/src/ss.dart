import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../computedmap.dart';
import 'computedmap_mixins.dart';
import 'expandos.dart';

class SnapshotStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  final Computed<IMap<K, V>> _snapshotStream;
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
          .where((e) =>
              (prev.containsKey(e) != cur.containsKey(e)) ||
              (prev[e] != cur[e]))
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
  Computed<V?> operator [](K key) => _tracker[key];

  @override
  late final Computed<ChangeEvent<K, V>> changes;

  @override
  Computed<bool> containsKey(K key) => _tracker.containsKey(key);

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  Computed<bool> get isEmpty =>
      isEmptyExpando[this] ??= $(() => _snapshotStream.use.isEmpty);

  @override
  Computed<bool> get isNotEmpty =>
      isNotEmptyExpando[this] ??= $(() => _snapshotStream.use.isNotEmpty);

  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => _snapshotStream.use.length);

  @override
  Computed<IMap<K, V>> get snapshot => _snapshotStream;
}
