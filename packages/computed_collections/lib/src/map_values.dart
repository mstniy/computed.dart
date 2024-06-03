import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:computed_collections/src/utils/snapshot_computation.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class MapValuesComputedMap<K, V, VParent>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  late final MockManager<K, V> _mm;
  final IComputedMap<K, VParent> _parent;
  final V Function(K key, VParent value) _convert;
  late final Computed<ChangeEvent<K, V>> _changes;
  late final Computed<IMap<K, V>> _snapshot;

  final _keyComputations = ComputationCache<K, V?>();
  final _containsKeyComputations = ComputationCache<K, bool>();
  final _containsValueComputations = ComputationCache<V, bool>();

  MapValuesComputedMap(this._parent, this._convert) {
    _changes = Computed(() {
      final change = _parent.changes.use;
      return switch (change) {
        ChangeEventReplace<K, VParent>() => ChangeEventReplace(change
            .newCollection
            .map(((key, value) => MapEntry(key, _convert(key, value))))),
        KeyChanges<K, VParent>() =>
          KeyChanges(IMap.fromEntries(change.changes.entries.map((e) {
            final key = e.key;
            return switch (e.value) {
              ChangeRecordValue<VParent>(value: var value) =>
                MapEntry(key, ChangeRecordValue(_convert(key, value))),
              ChangeRecordDelete<VParent>() =>
                MapEntry(key, ChangeRecordDelete<V>())
            };
          }))),
      };
    });
    _snapshot = snapshotComputation(
        _changes,
        () => _parent.snapshot.use
            .map(((key, value) => MapEntry(key, _convert(key, value)))));

    _mm = MockManager(
        _changes,
        _snapshot,
        $(() => _parent.length.use),
        $(() => _parent.isEmpty.use),
        $(() => _parent.isNotEmpty.use),
        _keyComputations,
        _containsKeyComputations,
        _containsValueComputations);
  }

  @override
  Computed<bool> containsKey(K key) {
    final parentContainsKey = _parent.containsKey(key);
    // TODO: This is inefficient. Make the computation map take computations as parameter?
    return _containsKeyComputations.wrap(key, () => parentContainsKey.use);
  }

  @override
  Computed<V?> operator [](K key) {
    final parentContainsKey = _parent.containsKey(key);
    final parentKey = _parent[key];
    return _keyComputations.wrap(key, () {
      try {
        final s = _snapshot.useWeak;
        // If there is a snapshot, use the value from there
        return s[key];
      } on NoStrongUserException {
        // We compute the value ourselves
        if (parentContainsKey.use) {
          return _convert(key, parentKey.use as VParent);
        }
        return null;
      }
    });
  }

  @override
  Computed<bool> containsValue(V value) => _containsValueComputations.wrap(
      value, () => _snapshot.use.containsValue(value));

  @override
  void fix(IMap<K, V> value) => _mm.fix(value);

  @override
  void fixThrow(Object e) => _mm.fixThrow(e);

  @override
  void mock(IComputedMap<K, V> mock) => _mm.mock(mock);

  @override
  void unmock() => _mm.unmock();

  @override
  Computed<ChangeEvent<K, V>> get changes => _mm.changes;
  @override
  Computed<IMap<K, V>> get snapshot => _mm.snapshot;
  @override
  Computed<bool> get isEmpty => _mm.isEmpty;
  @override
  Computed<bool> get isNotEmpty => _mm.isNotEmpty;
  @override
  Computed<int> get length => _mm.length;
}
