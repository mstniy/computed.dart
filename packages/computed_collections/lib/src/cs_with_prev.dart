import 'package:computed/computed.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/computedmap.dart';
import 'package:computed_collections/src/utils/cs_tracker.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';
import 'expandos.dart';

class ChangeStreamWithPrevComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements ComputedMap<K, V> {
  late final CSTracker<K, V> _tracker;

  final ChangeEvent<K, V> Function(IMap<K, V>? prev) _f;
  IMap<K, V>? _snapshot;

  ChangeStreamWithPrevComputedMap(this._f) {
    changes = Computed(() {
      final newChange = _f(_snapshot);
      _snapshot = (_snapshot ?? IMap<K, V>.empty()).withChange(newChange);
      return newChange;
    }, assertIdempotent: false, onCancel: () => _snapshot = null);
    snapshot = $(() {
      changes.use;
      return _snapshot!;
    });
    _tracker = CSTracker(changes, snapshot);
  }

  @override
  Computed<V?> operator [](K key) => _tracker[key];

  @override
  Computed<bool> containsKey(K key) => _tracker.containsKey(key);

  @override
  Computed<bool> containsValue(V value) => _tracker.containsValue(value);

  @override
  late final Computed<ChangeEvent<K, V>> changes;

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
