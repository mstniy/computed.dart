import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'expandos.dart';

class ChangeStreamComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  late final CSTracker<K, V> _tracker;
  ChangeStreamComputedMap(this.changes,
      {IMap<K, V> Function()? initialValueComputer,
      Computed<IMap<K, V>>? snapshotStream}) {
    snapshot =
        snapshotStream ?? snapshotComputation(changes, initialValueComputer);
    _tracker = CSTracker(changes, snapshot);
  }

  Computed<V?> operator [](K key) => _tracker[key];

  @override
  Computed<bool> containsKey(K key) => _tracker.containsKey(key);

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  Computed<ChangeEvent<K, V>> changes;

  @override
  Computed<bool> get isEmpty =>
      isEmptyExpando[this] ??= $(() => snapshot.use.isEmpty);

  @override
  Computed<bool> get isNotEmpty =>
      isNotEmptyExpando[this] ??= $(() => snapshot.use.isNotEmpty);

  @override
  Computed<int> get length =>
      lengthExpando[this] ??= $(() => snapshot.use.length);

  @override
  late final Computed<IMap<K, V>> snapshot;
}
