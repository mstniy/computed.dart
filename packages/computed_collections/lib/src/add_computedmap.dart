import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class AddComputedMap<K, V>
    with OperatorsMixin<K, V>
    implements IComputedMap<K, V> {
  K _key;
  V _value;
  late final MockManager<K, V> _mm;
  final IComputedMap<K, V> _parent;
  final _keyComputations = ComputationCache<K, V?>();
  final _containsKeyComputations = ComputationCache<K, bool>();
  final _containsValueComputations = ComputationCache<V, bool>();
  AddComputedMap(this._parent, this._key, this._value) {
    final parentContainsKey = _parent.containsKey(_key);
    final length =
        $(() => _parent.length.use + (parentContainsKey.use ? 0 : 1));
    final snapshot = $(() => _parent.snapshot.use.add(this._key, this._value));
    final changes = Computed(() {
      final changeEvent = _parent.changes.use;
      switch (changeEvent) {
        case ChangeEventReplace<K, V>():
          return ChangeEventReplace(
              changeEvent.newCollection.add(_key, _value));
        case KeyChanges<K, V>():
          final changes = changeEvent.changes.entries.map((upstreamChange) {
            if (upstreamChange.key == _key) {
              return <MapEntry<K, ChangeRecord<V>>>[];
            }
            return [upstreamChange];
          }).expand((e) => e);
          if (changes.isEmpty) throw NoValueException();
          return KeyChanges(IMap.fromEntries(changes));
      }
    });
    _mm = MockManager(changes, snapshot, length, $(() => false), $(() => true),
        _keyComputations, _containsKeyComputations, _containsValueComputations);
  }

  Computed<V?> operator [](K key) {
    final parentKey = _parent[key];
    return _keyComputations.wrap(key, () {
      // We make this decision inside the computation as opposed to directly inside `operator[]`
      // so that even mocks changing the value of `key` are possible.
      if (key == _key) return _value;
      return parentKey.use;
    });
  }

  @override
  IComputedMap<K, V> add(K key, V value) {
    if (key == _key) {
      return AddComputedMap(_parent, key, value);
    } else {
      return AddComputedMap(this, key, value);
    }
  }

  @override
  Computed<bool> containsKey(K key) {
    final parentContainsKey = _parent.containsKey(key);
    return _containsKeyComputations.wrap(key, () {
      if (key == _key) return true;
      return parentContainsKey.use;
    });
  }

  @override
  Computed<bool> containsValue(V value) {
    final parentContainsValue = _parent.containsValue(value);
    return _containsValueComputations.wrap(value, () {
      if (value == _value) return true;
      return parentContainsValue.use;
    });
  }

  @override
  void fix(IMap<K, V> value) => _mm.fix(value);

  @override
  void fixThrow(Object e) => _mm.fixThrow(e);

  @override
  void mock(IComputedMap<K, V> mock) => _mm.mock(mock);

  @override
  void unmock() => _mm.unmock();

  Computed<ChangeEvent<K, V>> get changes => _mm.changes;
  Computed<IMap<K, V>> get snapshot => _mm.snapshot;
  Computed<bool> get isEmpty => _mm.isEmpty;
  Computed<bool> get isNotEmpty => _mm.isNotEmpty;
  Computed<int> get length => _mm.length;
}
