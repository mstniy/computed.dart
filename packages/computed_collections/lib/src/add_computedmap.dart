import 'package:computed/computed.dart';
import 'package:computed/utils/computation_cache.dart';
import 'package:computed_collections/change_event.dart';
import 'package:computed_collections/icomputedmap.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'computedmap_mixins.dart';

class AddComputedMap<K, V>
    with OperatorsMixin<K, V>, MockMixin<K, V>
    implements IComputedMap<K, V> {
  K _key;
  V _value;
  final IComputedMap<K, V> _parent;
  late final Computed<ChangeEvent<K, V>> changes;
  late final Computed<IMap<K, V>> snapshot;
  final keyComputations = ComputationCache<K, V?>();
  final containsKeyComputations = ComputationCache<K, bool>();
  final containsValueComputations = ComputationCache<V, bool>();
  final isEmpty = $(() => false);
  final isNotEmpty = $(() => true);
  final Computed<int> length;
  AddComputedMap(this._parent, this._key, this._value)
      : length = $(() =>
            _parent.length.use + (_parent.containsKey(_key).use ? 0 : 1)) {
    snapshot = $(() => _parent.snapshot.use.add(this._key, this._value));
    changes = Computed(() {
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
  }

  Computed<V?> operator [](K key) {
    final parentKey = _parent[key];
    return keyComputations.wrap(key, () {
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
    return containsKeyComputations.wrap(key, () {
      if (key == _key) return true;
      return parentContainsKey.use;
    });
  }

  @override
  Computed<bool> containsValue(V value) {
    final parentContainsValue = _parent.containsValue(value);
    return containsValueComputations.wrap(value, () {
      if (value == _value) return true;
      return parentContainsValue.use;
    });
  }
}
